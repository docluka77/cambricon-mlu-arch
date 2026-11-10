// =============================================================================
// File: uvm_tb/uvm_cambricon_llm_kv/mlu_cambricon_llm_kv_uvm_pkg.sv
// Description: Accellera IEEE 1800.2-2020 UVM Package for Suite 10:
//              Cambricon-LLM (MICRO 2024) Flash-Assisted INT4/FP8 KV-Cache
//              Quant-Pack & Speculative Decoding Tree Verification Engine.
// =============================================================================
`ifndef MLU_CAMBRICON_LLM_KV_UVM_PKG_SV
`define MLU_CAMBRICON_LLM_KV_UVM_PKG_SV

`timescale 1ns/1ps
`include "uvm_macros.svh"

package mlu_cambricon_llm_kv_uvm_pkg;
  import uvm_pkg::*;
  import mlu_pkg::*;

  import "DPI-C" function void dpi_cambricon_llm_kv_pack_ref(
    input  int              prec_int4,
    input  longint unsigned kv_lo,
    input  longint unsigned kv_hi,
    output longint unsigned exp_packed_out,
    output longint unsigned exp_dequant_lo,
    output longint unsigned exp_dequant_hi
  );

  import "DPI-C" function void dpi_cambricon_llm_spec_verify_ref(
    input  longint unsigned draft_lo,
    input  longint unsigned draft_hi,
    input  longint unsigned target_lo,
    input  longint unsigned target_hi,
    input  int              tree_mask,
    input  int              accept_thresh,
    output int              exp_bitmap,
    output int              exp_len,
    output int              exp_bonus_idx
  );

  import "DPI-C" function void dpi_cambricon_llm_record_result(input int pass);
  import "DPI-C" function int  dpi_cambricon_llm_get_status();

  class mlu_llm_kv_seq_item extends uvm_sequence_item;
    `uvm_object_utils(mlu_llm_kv_seq_item)

    mlu_opcode_e  opcode;
    mlu_prec_e    prec;
    logic [7:0]   cmd_tag;
    logic [3:0]   kv_wr_slot;
    logic [31:0]  flash_base_page;
    logic [127:0] kv_fp16_in;
    logic         flash_ecc_clean;
    logic [127:0] draft_prob;
    logic [127:0] target_prob;
    logic [7:0]   tree_mask;
    logic [15:0]  accept_thresh;

    // Observed outputs
    logic [63:0]  act_packed_out;
    logic [127:0] act_dequant_out;
    logic         act_flash_req_valid;
    logic [31:0]  act_flash_page_addr;
    logic         act_done_valid;
    logic [7:0]   act_done_tag;
    logic [7:0]   act_accepted_bitmap;
    logic [3:0]   act_accepted_len;
    logic [2:0]   act_bonus_token_idx;

    function new(string name = "mlu_llm_kv_seq_item");
      super.new(name);
    endfunction
  endclass : mlu_llm_kv_seq_item

  class mlu_llm_kv_sequencer extends uvm_sequencer #(mlu_llm_kv_seq_item);
    `uvm_component_utils(mlu_llm_kv_sequencer)
    function new(string name = "mlu_llm_kv_sequencer", uvm_component parent = null);
      super.new(name, parent);
    endfunction
  endclass : mlu_llm_kv_sequencer

  class mlu_llm_kv_sequence extends uvm_sequence #(mlu_llm_kv_seq_item);
    `uvm_object_utils(mlu_llm_kv_sequence)

    function new(string name = "mlu_llm_kv_sequence");
      super.new(name);
    endfunction

    task body();
      for (int i = 0; i < 300; i++) begin
        mlu_llm_kv_seq_item req = mlu_llm_kv_seq_item::type_id::create($sformatf("req_%0d", i));
        start_item(req);
        req.cmd_tag         = i[7:0];
        req.kv_wr_slot      = i[3:0];
        req.flash_base_page = 32'h0010_0000 + (i * 32'h10);
        req.flash_ecc_clean = (i % 29 != 0);
        if (i < 150) begin
          req.opcode = OP_LLM_KV_PACK;
          req.prec   = (i % 2 == 0) ? PREC_INT4 : PREC_FP8_E4M3;
          for (int k = 0; k < 8; k++) begin
            if (i < 20) begin
              // Small dynamic range (lossless INT4 test)
              req.kv_fp16_in[k*16 +: 16] = 16'(signed'(16'sd100 + k * 2 - (i % 5)));
            end else begin
              req.kv_fp16_in[k*16 +: 16] = 16'((i * 257 + k * 1999) ^ 16'h5A3C);
            end
          end
          req.draft_prob    = 128'd0;
          req.target_prob   = 128'd0;
          req.tree_mask     = 8'hFF;
          req.accept_thresh = 16'd0;
        end else begin
          req.opcode     = OP_LLM_SPEC_VERIFY;
          req.prec       = PREC_FP16;
          req.kv_fp16_in = 128'd0;
          req.tree_mask  = (i % 15 == 0) ? 8'h3F : 8'hFF;
          req.accept_thresh = 16'(signed'(16'sd16 * ((i % 5) - 1)));
          for (int k = 0; k < 8; k++) begin
            automatic shortint d_v = shortint'((i * 37 + k * 53) & 16'h07FF);
            automatic shortint t_v;
            if (i % 6 == 0)      t_v = d_v + 16'sd50; // All 8 accepted
            else if (i % 6 == 1) t_v = d_v - 16'sd200; // Token 0 rejected
            else if (k < (i % 8)) t_v = d_v + 16'sd20; // Prefix 0..(i%8)-1 accepted
            else                  t_v = d_v - 16'sd200;
            req.draft_prob[k*16 +: 16]  = 16'(d_v);
            req.target_prob[k*16 +: 16] = 16'(t_v);
          end
        end
        finish_item(req);
      end
    endtask
  endclass : mlu_llm_kv_sequence

  class mlu_llm_kv_driver extends uvm_driver #(mlu_llm_kv_seq_item);
    `uvm_component_utils(mlu_llm_kv_driver)

    virtual mlu_cambricon_llm_kv_if vif;
    int unsigned driven = 0;

    function new(string name = "mlu_llm_kv_driver", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual mlu_cambricon_llm_kv_if)::get(this, "", "vif", vif)) begin
        `uvm_fatal("NO_VIF", "Virtual interface missing in mlu_llm_kv_driver")
      end
    endfunction

    task run_phase(uvm_phase phase);
      mlu_llm_kv_seq_item item;
      vif.rst_ni            = 1'b0;
      vif.cmd_valid_i       = 1'b0;
      vif.opcode_i          = OP_NOP;
      vif.prec_i            = PREC_INT4;
      vif.cmd_tag_i         = 8'd0;
      vif.kv_wr_slot_i      = 4'd0;
      vif.flash_base_page_i = 32'd0;
      vif.kv_fp16_in_i      = 128'd0;
      vif.kv_rd_en_i        = 1'b0;
      vif.kv_rd_addr_i      = 4'd0;
      vif.flash_ecc_clean_i = 1'b1;
      vif.draft_prob_i      = 128'd0;
      vif.target_prob_i     = 128'd0;
      vif.tree_mask_i       = 8'hFF;
      vif.accept_thresh_i   = 16'd0;

      repeat (3) @(posedge vif.clk_i);
      @(negedge vif.clk_i);
      vif.rst_ni = 1'b1;

      forever begin
        seq_item_port.get_next_item(item);
        vif.cmd_valid_i       = 1'b1;
        vif.opcode_i          = item.opcode;
        vif.prec_i            = item.prec;
        vif.cmd_tag_i         = item.cmd_tag;
        vif.kv_wr_slot_i      = item.kv_wr_slot;
        vif.flash_base_page_i = item.flash_base_page;
        vif.kv_fp16_in_i      = item.kv_fp16_in;
        vif.kv_rd_en_i        = 1'b1;
        vif.kv_rd_addr_i      = item.kv_wr_slot;
        vif.flash_ecc_clean_i = item.flash_ecc_clean;
        vif.draft_prob_i      = item.draft_prob;
        vif.target_prob_i     = item.target_prob;
        vif.tree_mask_i       = item.tree_mask;
        vif.accept_thresh_i   = item.accept_thresh;

        @(posedge vif.clk_i);
        driven++;
        @(negedge vif.clk_i);
        vif.cmd_valid_i = 1'b0;
        seq_item_port.item_done();
      end
    endtask
  endclass : mlu_llm_kv_driver

  class mlu_llm_kv_monitor extends uvm_monitor;
    `uvm_component_utils(mlu_llm_kv_monitor)

    virtual mlu_cambricon_llm_kv_if vif;
    uvm_analysis_port #(mlu_llm_kv_seq_item) ap;
    int unsigned seen = 0;

    covergroup llm_kv_cg with function sample(
      bit       is_spec,
      bit       is_int4,
      bit [3:0] slot,
      bit [3:0] acc_len
    );
      option.per_instance = 1;
      cp_mode: coverpoint is_spec { bins kv_pack = {0}; bins spec_ver = {1}; }
      cp_prec: coverpoint is_int4 { bins fp8 = {0};     bins int4 = {1}; }
      cp_slot: coverpoint slot;
      cp_alen: coverpoint acc_len {
        bins zero = {4'd0};
        bins mid  = {[4'd1:4'd7]};
        bins full = {4'd8};
      }
    endgroup

    function new(string name = "mlu_llm_kv_monitor", uvm_component parent = null);
      super.new(name, parent);
      ap = new("ap", this);
      llm_kv_cg = new();
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual mlu_cambricon_llm_kv_if)::get(this, "", "vif", vif)) begin
        `uvm_fatal("NO_VIF", "Virtual interface missing in mlu_llm_kv_monitor")
      end
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        @(posedge vif.clk_i);
        #2ns;
        if (vif.rst_ni && vif.done_valid_o) begin
          mlu_llm_kv_seq_item obs = mlu_llm_kv_seq_item::type_id::create("obs");
          obs.opcode              = vif.opcode_i;
          obs.prec                = vif.prec_i;
          obs.cmd_tag             = vif.cmd_tag_i;
          obs.kv_wr_slot          = vif.kv_wr_slot_i;
          obs.flash_base_page     = vif.flash_base_page_i;
          obs.kv_fp16_in          = vif.kv_fp16_in_i;
          obs.flash_ecc_clean     = vif.flash_ecc_clean_i;
          obs.draft_prob          = vif.draft_prob_i;
          obs.target_prob         = vif.target_prob_i;
          obs.tree_mask           = vif.tree_mask_i;
          obs.accept_thresh       = vif.accept_thresh_i;
          obs.act_packed_out      = vif.kv_packed_out_o;
          obs.act_dequant_out     = vif.kv_dequant_out_o;
          obs.act_flash_req_valid = vif.flash_req_valid_o;
          obs.act_flash_page_addr = vif.flash_page_addr_o;
          obs.act_done_valid      = vif.done_valid_o;
          obs.act_done_tag        = vif.done_tag_o;
          obs.act_accepted_bitmap = vif.accepted_bitmap_o;
          obs.act_accepted_len    = vif.accepted_len_o;
          obs.act_bonus_token_idx = vif.bonus_token_idx_o;
          llm_kv_cg.sample(
            (vif.opcode_i == OP_LLM_SPEC_VERIFY),
            (vif.prec_i == PREC_INT4),
            vif.kv_wr_slot_i,
            vif.accepted_len_o
          );
          seen++;
          ap.write(obs);
        end
      end
    endtask
  endclass : mlu_llm_kv_monitor

  class mlu_llm_kv_agent extends uvm_agent;
    `uvm_component_utils(mlu_llm_kv_agent)
    mlu_llm_kv_sequencer sequencer;
    mlu_llm_kv_driver    driver;
    mlu_llm_kv_monitor   monitor;

    function new(string name = "mlu_llm_kv_agent", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      sequencer = mlu_llm_kv_sequencer::type_id::create("sequencer", this);
      driver    = mlu_llm_kv_driver::type_id::create("driver", this);
      monitor   = mlu_llm_kv_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
  endclass : mlu_llm_kv_agent

  class mlu_llm_kv_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(mlu_llm_kv_scoreboard)
    uvm_analysis_imp #(mlu_llm_kv_seq_item, mlu_llm_kv_scoreboard) analysis_export;

    int unsigned checked_txns    = 0;
    int unsigned kv_pack_txns    = 0;
    int unsigned spec_ver_txns   = 0;
    int unsigned mismatches      = 0;

    function new(string name = "mlu_llm_kv_scoreboard", uvm_component parent = null);
      super.new(name, parent);
      analysis_export = new("analysis_export", this);
    endfunction

    function void write(mlu_llm_kv_seq_item item);
      bit pass = 1'b1;
      checked_txns++;

      if (item.act_done_tag !== item.cmd_tag) begin
        `uvm_error("TAG_MISMATCH", $sformatf("Tag mismatch: act=%02h exp=%02h", item.act_done_tag, item.cmd_tag))
        pass = 1'b0;
      end

      if (item.opcode == OP_LLM_KV_PACK) begin
        longint unsigned exp_packed, exp_deq_lo, exp_deq_hi;
        logic [127:0] exp_deq;
        kv_pack_txns++;
        dpi_cambricon_llm_kv_pack_ref(
          (item.prec == PREC_INT4) ? 1 : 0,
          item.kv_fp16_in[63:0],
          item.kv_fp16_in[127:64],
          exp_packed,
          exp_deq_lo,
          exp_deq_hi
        );
        exp_deq = {exp_deq_hi, exp_deq_lo};
        if (item.act_packed_out      !== exp_packed ||
            item.act_dequant_out     !== exp_deq    ||
            item.act_flash_req_valid !== 1'b1       ||
            item.act_flash_page_addr !== (item.flash_base_page + {28'd0, item.kv_wr_slot})) begin
          `uvm_error("KV_PACK_MISMATCH", $sformatf(
            "KV pack mismatch: act_pk=%016h(exp %016h) act_deq=%032h(exp %032h)",
            item.act_packed_out, exp_packed, item.act_dequant_out, exp_deq))
          pass = 1'b0;
        end
      end else if (item.opcode == OP_LLM_SPEC_VERIFY) begin
        int exp_bm, exp_len, exp_bonus;
        spec_ver_txns++;
        dpi_cambricon_llm_spec_verify_ref(
          item.draft_prob[63:0],
          item.draft_prob[127:64],
          item.target_prob[63:0],
          item.target_prob[127:64],
          int'({24'd0, item.tree_mask}),
          int'(signed'(item.accept_thresh)),
          exp_bm,
          exp_len,
          exp_bonus
        );
        if (item.act_accepted_bitmap !== exp_bm[7:0] ||
            item.act_accepted_len    !== exp_len[3:0] ||
            item.act_bonus_token_idx !== exp_bonus[2:0]) begin
          `uvm_error("SPEC_VERIFY_MISMATCH", $sformatf(
            "SpecVerify mismatch: bm=%02h(exp %02h) len=%0d(exp %0d) bonus=%0d(exp %0d)",
            item.act_accepted_bitmap, exp_bm[7:0], item.act_accepted_len, exp_len[3:0],
            item.act_bonus_token_idx, exp_bonus[2:0]))
          pass = 1'b0;
        end
      end

      if (!pass) mismatches++;
      dpi_cambricon_llm_record_result(pass ? 1 : 0);
    endfunction
  endclass : mlu_llm_kv_scoreboard

  class mlu_llm_kv_env extends uvm_env;
    `uvm_component_utils(mlu_llm_kv_env)
    mlu_llm_kv_agent      agent;
    mlu_llm_kv_scoreboard scoreboard;

    function new(string name = "mlu_llm_kv_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent      = mlu_llm_kv_agent::type_id::create("agent", this);
      scoreboard = mlu_llm_kv_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent.monitor.ap.connect(scoreboard.analysis_export);
    endfunction
  endclass : mlu_llm_kv_env

  class mlu_cambricon_llm_kv_test extends uvm_test;
    `uvm_component_utils(mlu_cambricon_llm_kv_test)
    mlu_llm_kv_env env;

    function new(string name = "mlu_cambricon_llm_kv_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = mlu_llm_kv_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
      mlu_llm_kv_sequence seq = mlu_llm_kv_sequence::type_id::create("seq");
      phase.raise_objection(this);
      seq.start(env.agent.sequencer);
      #20ns;
      phase.drop_objection(this);
    endtask

    function void report_phase(uvm_phase phase);
      real cov = env.agent.monitor.llm_kv_cg.get_inst_coverage();
      super.report_phase(phase);
      if (env.scoreboard.checked_txns != 300 || env.scoreboard.mismatches != 0) begin
        `uvm_fatal("SUITE10_FAIL", $sformatf("Suite 10 failed: checked=%0d mismatches=%0d",
          env.scoreboard.checked_txns, env.scoreboard.mismatches))
      end else begin
        `uvm_info("SUITE10_PASS", $sformatf(
          "SUITE 10 PASS: checked_txns=%0d (kv_pack=%0d, spec_verify=%0d) mismatches=0 func_cov=%0.2f%%",
          env.scoreboard.checked_txns, env.scoreboard.kv_pack_txns,
          env.scoreboard.spec_ver_txns, cov), UVM_LOW)
      end
    endfunction
  endclass : mlu_cambricon_llm_kv_test

endpackage : mlu_cambricon_llm_kv_uvm_pkg

`endif // MLU_CAMBRICON_LLM_KV_UVM_PKG_SV
