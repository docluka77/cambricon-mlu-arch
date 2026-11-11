//      // verilator_coverage annotation
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
        
%000000   class mlu_llm_kv_seq_item extends uvm_sequence_item;
~000300     `uvm_object_utils(mlu_llm_kv_seq_item)
        
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
        
~000600     function new(string name = "mlu_llm_kv_seq_item");
 000600       super.new(name);
            endfunction
          endclass : mlu_llm_kv_seq_item
        
          class mlu_llm_kv_sequencer extends uvm_sequencer #(mlu_llm_kv_seq_item);
%000001     `uvm_component_utils(mlu_llm_kv_sequencer)
%000001     function new(string name = "mlu_llm_kv_sequencer", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
          endclass : mlu_llm_kv_sequencer
        
          class mlu_llm_kv_sequence extends uvm_sequence #(mlu_llm_kv_seq_item);
%000001     `uvm_object_utils(mlu_llm_kv_sequence)
        
%000001     function new(string name = "mlu_llm_kv_sequence");
%000001       super.new(name);
            endfunction
        
%000001     task body();
~000300       for (int i = 0; i < 300; i++) begin
 000300         mlu_llm_kv_seq_item req = mlu_llm_kv_seq_item::type_id::create($sformatf("req_%0d", i));
 000300         start_item(req);
 000300         req.cmd_tag         = i[7:0];
 000300         req.kv_wr_slot      = i[3:0];
 000300         req.flash_base_page = 32'h0010_0000 + (i * 32'h10);
 000300         req.flash_ecc_clean = (i % 29 != 0);
 000150         if (i < 150) begin
                  // Sweep all 13 span_u priority buckets (shift_amt = 13, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0)
 000150           int span_max_lut[13] = '{
 000150             20000, 20000, 10000, 5000, 2500, 1200, 600, 300, 150, 80, 40, 20, 10
                  };
 000150           int span_min_lut[13] = '{
 000150             -20000, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                  };
 000150           req.opcode = OP_LLM_KV_PACK;
 000150           req.prec   = (i % 2 == 0) ? PREC_INT4 : PREC_FP8_E4M3;
 001200           for (int k = 0; k < 8; k++) begin
 000784             if (i < 52) begin
 000416               int b_idx = (i / 2) % 13;
 000416               int min_v = span_min_lut[b_idx];
 000416               int max_v = span_max_lut[b_idx];
 000416               int lane_v = min_v + ((max_v - min_v) * k) / 7;
 000416               req.kv_fp16_in[k*16 +: 16] = 16'(signed'(lane_v));
 000784             end else begin
 000784               req.kv_fp16_in[k*16 +: 16] = 16'((i * 257 + k * 1999) ^ 16'h5A3C);
                    end
                  end
 000150           req.draft_prob    = 128'd0;
 000150           req.target_prob   = 128'd0;
 000150           req.tree_mask     = 8'hFF;
 000150           req.accept_thresh = 16'd0;
 000150         end else begin
 000150           req.opcode     = OP_LLM_SPEC_VERIFY;
 000150           req.prec       = PREC_FP16;
 000150           req.kv_fp16_in = 128'd0;
 000150           req.tree_mask  = (i % 15 == 0) ? 8'h3F : 8'hFF;
 000150           req.accept_thresh = 16'(signed'(16'sd16 * ((i % 5) - 1)));
 001200           for (int k = 0; k < 8; k++) begin
 001200             automatic shortint d_v = shortint'((i * 37 + k * 53) & 16'h07FF);
 001200             automatic shortint t_v;
 000200             if (i % 6 == 0)      t_v = d_v + 16'sd50; // All 8 accepted
 000200             else if (i % 6 == 1) t_v = d_v - 16'sd200; // Token 0 rejected
 000458             else if (k < (i % 8)) t_v = d_v + 16'sd20; // Prefix 0..(i%8)-1 accepted
 000458             else                  t_v = d_v - 16'sd200;
 001200             req.draft_prob[k*16 +: 16]  = 16'(d_v);
 001200             req.target_prob[k*16 +: 16] = 16'(t_v);
                  end
                end
 000300         finish_item(req);
              end
            endtask
          endclass : mlu_llm_kv_sequence
        
          class mlu_llm_kv_driver extends uvm_driver #(mlu_llm_kv_seq_item);
%000001     `uvm_component_utils(mlu_llm_kv_driver)
        
            virtual mlu_cambricon_llm_kv_if vif;
%000001     int unsigned driven = 0;
        
%000001     function new(string name = "mlu_llm_kv_driver", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       if (!uvm_config_db#(virtual mlu_cambricon_llm_kv_if)::get(this, "", "vif", vif)) begin
%000000         `uvm_fatal("NO_VIF", "Virtual interface missing in mlu_llm_kv_driver")
              end
            endfunction
        
%000000     task run_phase(uvm_phase phase);
%000000       mlu_llm_kv_seq_item item;
%000000       vif.rst_ni            = 1'b0;
%000000       vif.cmd_valid_i       = 1'b0;
%000000       vif.opcode_i          = OP_NOP;
%000000       vif.prec_i            = PREC_INT4;
%000000       vif.cmd_tag_i         = 8'd0;
%000000       vif.kv_wr_slot_i      = 4'd0;
%000000       vif.flash_base_page_i = 32'd0;
%000000       vif.kv_fp16_in_i      = 128'd0;
%000000       vif.kv_rd_en_i        = 1'b0;
%000000       vif.kv_rd_addr_i      = 4'd0;
%000000       vif.flash_ecc_clean_i = 1'b1;
%000000       vif.draft_prob_i      = 128'd0;
%000000       vif.target_prob_i     = 128'd0;
%000000       vif.tree_mask_i       = 8'hFF;
%000000       vif.accept_thresh_i   = 16'd0;
        
%000003       repeat (3) @(posedge vif.clk_i);
%000000       @(negedge vif.clk_i);
%000000       vif.rst_ni = 1'b1;
        
 000300       forever begin
 000300         seq_item_port.get_next_item(item);
 000300         vif.cmd_valid_i       = 1'b1;
 000300         vif.opcode_i          = item.opcode;
 000300         vif.prec_i            = item.prec;
 000300         vif.cmd_tag_i         = item.cmd_tag;
 000300         vif.kv_wr_slot_i      = item.kv_wr_slot;
 000300         vif.flash_base_page_i = item.flash_base_page;
 000300         vif.kv_fp16_in_i      = item.kv_fp16_in;
 000300         vif.kv_rd_en_i        = 1'b1;
 000300         vif.kv_rd_addr_i      = item.kv_wr_slot;
 000300         vif.flash_ecc_clean_i = item.flash_ecc_clean;
 000300         vif.draft_prob_i      = item.draft_prob;
 000300         vif.target_prob_i     = item.target_prob;
 000300         vif.tree_mask_i       = item.tree_mask;
 000300         vif.accept_thresh_i   = item.accept_thresh;
        
 000300         @(posedge vif.clk_i);
 000300         driven++;
 000300         @(negedge vif.clk_i);
 000300         vif.cmd_valid_i = 1'b0;
 000300         seq_item_port.item_done();
              end
            endtask
          endclass : mlu_llm_kv_driver
        
          class mlu_llm_kv_monitor extends uvm_monitor;
%000001     `uvm_component_utils(mlu_llm_kv_monitor)
        
            virtual mlu_cambricon_llm_kv_if vif;
            uvm_analysis_port #(mlu_llm_kv_seq_item) ap;
%000001     int unsigned seen = 0;
        
            covergroup llm_kv_cg with function sample(
              bit       is_spec,
              bit       is_int4,
              bit [3:0] slot,
              bit [3:0] acc_len
            );
              option.per_instance = 1;
 000150       cp_mode: coverpoint is_spec { bins kv_pack = {0}; bins spec_ver = {1}; }
 000225       cp_prec: coverpoint is_int4 { bins fp8 = {0};     bins int4 = {1}; }
 000019       cp_slot: coverpoint slot;
              cp_alen: coverpoint acc_len {
 000188         bins zero = {4'd0};
 000092         bins mid  = {[4'd1:4'd7]};
 000020         bins full = {4'd8};
              }
            endgroup
        
%000001     function new(string name = "mlu_llm_kv_monitor", uvm_component parent = null);
%000001       super.new(name, parent);
%000001       ap = new("ap", this);
%000001       llm_kv_cg = new();
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       if (!uvm_config_db#(virtual mlu_cambricon_llm_kv_if)::get(this, "", "vif", vif)) begin
%000000         `uvm_fatal("NO_VIF", "Virtual interface missing in mlu_llm_kv_monitor")
              end
            endfunction
        
%000000     task run_phase(uvm_phase phase);
 000305       forever begin
 000305         @(posedge vif.clk_i);
 000305         #2ns;
~000300         if (vif.rst_ni && vif.done_valid_o) begin
 000300           mlu_llm_kv_seq_item obs = mlu_llm_kv_seq_item::type_id::create("obs");
 000300           obs.opcode              = vif.opcode_i;
 000300           obs.prec                = vif.prec_i;
 000300           obs.cmd_tag             = vif.cmd_tag_i;
 000300           obs.kv_wr_slot          = vif.kv_wr_slot_i;
 000300           obs.flash_base_page     = vif.flash_base_page_i;
 000300           obs.kv_fp16_in          = vif.kv_fp16_in_i;
 000300           obs.flash_ecc_clean     = vif.flash_ecc_clean_i;
 000300           obs.draft_prob          = vif.draft_prob_i;
 000300           obs.target_prob         = vif.target_prob_i;
 000300           obs.tree_mask           = vif.tree_mask_i;
 000300           obs.accept_thresh       = vif.accept_thresh_i;
 000300           obs.act_packed_out      = vif.kv_packed_out_o;
 000300           obs.act_dequant_out     = vif.kv_dequant_out_o;
 000300           obs.act_flash_req_valid = vif.flash_req_valid_o;
 000300           obs.act_flash_page_addr = vif.flash_page_addr_o;
 000300           obs.act_done_valid      = vif.done_valid_o;
 000300           obs.act_done_tag        = vif.done_tag_o;
 000300           obs.act_accepted_bitmap = vif.accepted_bitmap_o;
 000300           obs.act_accepted_len    = vif.accepted_len_o;
 000300           obs.act_bonus_token_idx = vif.bonus_token_idx_o;
 000300           llm_kv_cg.sample(
 000300             (vif.opcode_i == OP_LLM_SPEC_VERIFY),
 000300             (vif.prec_i == PREC_INT4),
 000300             vif.kv_wr_slot_i,
 000300             vif.accepted_len_o
                  );
 000300           seen++;
 000300           ap.write(obs);
                end
              end
            endtask
          endclass : mlu_llm_kv_monitor
        
          class mlu_llm_kv_agent extends uvm_agent;
%000001     `uvm_component_utils(mlu_llm_kv_agent)
            mlu_llm_kv_sequencer sequencer;
            mlu_llm_kv_driver    driver;
            mlu_llm_kv_monitor   monitor;
        
%000001     function new(string name = "mlu_llm_kv_agent", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       sequencer = mlu_llm_kv_sequencer::type_id::create("sequencer", this);
%000001       driver    = mlu_llm_kv_driver::type_id::create("driver", this);
%000001       monitor   = mlu_llm_kv_monitor::type_id::create("monitor", this);
            endfunction
        
%000001     function void connect_phase(uvm_phase phase);
%000001       super.connect_phase(phase);
%000001       driver.seq_item_port.connect(sequencer.seq_item_export);
            endfunction
          endclass : mlu_llm_kv_agent
        
          class mlu_llm_kv_scoreboard extends uvm_scoreboard;
%000001     `uvm_component_utils(mlu_llm_kv_scoreboard)
            uvm_analysis_imp #(mlu_llm_kv_seq_item, mlu_llm_kv_scoreboard) analysis_export;
        
%000001     int unsigned checked_txns    = 0;
%000001     int unsigned kv_pack_txns    = 0;
%000001     int unsigned spec_ver_txns   = 0;
%000001     int unsigned mismatches      = 0;
        
%000001     function new(string name = "mlu_llm_kv_scoreboard", uvm_component parent = null);
%000001       super.new(name, parent);
%000001       analysis_export = new("analysis_export", this);
            endfunction
        
 000300     function void write(mlu_llm_kv_seq_item item);
 000300       bit pass = 1'b1;
 000300       checked_txns++;
        
~000300       if (item.act_done_tag !== item.cmd_tag) begin
%000000         `uvm_error("TAG_MISMATCH", $sformatf("Tag mismatch: act=%02h exp=%02h", item.act_done_tag, item.cmd_tag))
%000000         pass = 1'b0;
              end
        
 000150       if (item.opcode == OP_LLM_KV_PACK) begin
 000150         longint unsigned exp_packed, exp_deq_lo, exp_deq_hi;
 000150         logic [127:0] exp_deq;
 000150         kv_pack_txns++;
 000150         dpi_cambricon_llm_kv_pack_ref(
 000150           (item.prec == PREC_INT4) ? 1 : 0,
 000150           item.kv_fp16_in[63:0],
 000150           item.kv_fp16_in[127:64],
 000150           exp_packed,
 000150           exp_deq_lo,
 000150           exp_deq_hi
                );
 000150         exp_deq = {exp_deq_hi, exp_deq_lo};
~000150         if (item.act_packed_out      !== exp_packed ||
                    item.act_dequant_out     !== exp_deq    ||
                    item.act_flash_req_valid !== 1'b1       ||
%000000             item.act_flash_page_addr !== (item.flash_base_page + {28'd0, item.kv_wr_slot})) begin
                  `uvm_error("KV_PACK_MISMATCH", $sformatf(
                    "KV pack mismatch: act_pk=%016h(exp %016h) act_deq=%032h(exp %032h)",
%000000             item.act_packed_out, exp_packed, item.act_dequant_out, exp_deq))
%000000           pass = 1'b0;
                end
~000150       end else if (item.opcode == OP_LLM_SPEC_VERIFY) begin
 000150         int exp_bm, exp_len, exp_bonus;
 000150         spec_ver_txns++;
 000150         dpi_cambricon_llm_spec_verify_ref(
 000150           item.draft_prob[63:0],
 000150           item.draft_prob[127:64],
 000150           item.target_prob[63:0],
 000150           item.target_prob[127:64],
 000150           int'({24'd0, item.tree_mask}),
 000150           int'(signed'(item.accept_thresh)),
 000150           exp_bm,
 000150           exp_len,
 000150           exp_bonus
                );
~000150         if (item.act_accepted_bitmap !== exp_bm[7:0] ||
                    item.act_accepted_len    !== exp_len[3:0] ||
%000000             item.act_bonus_token_idx !== exp_bonus[2:0]) begin
                  `uvm_error("SPEC_VERIFY_MISMATCH", $sformatf(
                    "SpecVerify mismatch: bm=%02h(exp %02h) len=%0d(exp %0d) bonus=%0d(exp %0d)",
                    item.act_accepted_bitmap, exp_bm[7:0], item.act_accepted_len, exp_len[3:0],
%000000             item.act_bonus_token_idx, exp_bonus[2:0]))
%000000           pass = 1'b0;
                end
              end
        
~000300       if (!pass) mismatches++;
 000300       dpi_cambricon_llm_record_result(pass ? 1 : 0);
            endfunction
          endclass : mlu_llm_kv_scoreboard
        
          class mlu_llm_kv_env extends uvm_env;
%000001     `uvm_component_utils(mlu_llm_kv_env)
            mlu_llm_kv_agent      agent;
            mlu_llm_kv_scoreboard scoreboard;
        
%000001     function new(string name = "mlu_llm_kv_env", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       agent      = mlu_llm_kv_agent::type_id::create("agent", this);
%000001       scoreboard = mlu_llm_kv_scoreboard::type_id::create("scoreboard", this);
            endfunction
        
%000001     function void connect_phase(uvm_phase phase);
%000001       super.connect_phase(phase);
%000001       agent.monitor.ap.connect(scoreboard.analysis_export);
            endfunction
          endclass : mlu_llm_kv_env
        
          class mlu_cambricon_llm_kv_test extends uvm_test;
%000002     `uvm_component_utils(mlu_cambricon_llm_kv_test)
            mlu_llm_kv_env env;
        
%000001     function new(string name = "mlu_cambricon_llm_kv_test", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       env = mlu_llm_kv_env::type_id::create("env", this);
            endfunction
        
%000001     task run_phase(uvm_phase phase);
%000001       mlu_llm_kv_sequence seq = mlu_llm_kv_sequence::type_id::create("seq");
%000001       phase.raise_objection(this);
%000001       seq.start(env.agent.sequencer);
%000001       #20ns;
%000001       phase.drop_objection(this);
            endtask
        
%000001     function void report_phase(uvm_phase phase);
%000001       real cov = env.agent.monitor.llm_kv_cg.get_inst_coverage();
%000001       super.report_phase(phase);
%000001       if (env.scoreboard.checked_txns != 300 || env.scoreboard.mismatches != 0) begin
                `uvm_fatal("SUITE10_FAIL", $sformatf("Suite 10 failed: checked=%0d mismatches=%0d",
%000000           env.scoreboard.checked_txns, env.scoreboard.mismatches))
%000001       end else begin
                `uvm_info("SUITE10_PASS", $sformatf(
                  "SUITE 10 PASS: checked_txns=%0d (kv_pack=%0d, spec_verify=%0d) mismatches=0 func_cov=%0.2f%%",
                  env.scoreboard.checked_txns, env.scoreboard.kv_pack_txns,
%000001           env.scoreboard.spec_ver_txns, cov), UVM_LOW)
              end
            endfunction
          endclass : mlu_cambricon_llm_kv_test
        
        endpackage : mlu_cambricon_llm_kv_uvm_pkg
        
        `endif // MLU_CAMBRICON_LLM_KV_UVM_PKG_SV
        
