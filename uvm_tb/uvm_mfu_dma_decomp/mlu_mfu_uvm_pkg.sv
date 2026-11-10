// =============================================================================
// File: uvm_tb/uvm_mfu_dma_decomp/mlu_mfu_uvm_pkg.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Accellera IEEE 1800.2-2020 UVM Verification Package for Suite 5:
//              mlu_mfu_dma_engine (All 6 BANG DMA Opcodes & Zero-Bitmap Decomp).
// =============================================================================
`ifndef MLU_MFU_UVM_PKG_SV
`define MLU_MFU_UVM_PKG_SV

`timescale 1ns/1ps
`include "uvm_macros.svh"
`include "mlu_pkg.sv"

package mlu_mfu_uvm_pkg;
  import uvm_pkg::*;
  import mlu_pkg::*;

  // ---------------------------------------------------------------------------
  // DPI-C Bit-Exact Reference Model Imports
  // ---------------------------------------------------------------------------
  import "DPI-C" function void             dpi_mfu_set_status(int status);
  import "DPI-C" function int              dpi_mfu_get_status();
  import "DPI-C" function int unsigned     dpi_mfu_get_calls();
  import "DPI-C" function void             dpi_mfu_ref_reset();
  import "DPI-C" function void             dpi_mfu_ref_eval_beat(
    int unsigned     opcode,
    int unsigned     src_base,
    int unsigned     dst_base,
    int unsigned     src1_or_strd,
    int unsigned     len_or_dims,
    int unsigned     beat_idx,
    longint unsigned idx_offset,
    int unsigned     decomp_bitmap,
    longint unsigned raw_rd_data
  );
  import "DPI-C" function int unsigned     dpi_mfu_exp_rd_addr();
  import "DPI-C" function int unsigned     dpi_mfu_exp_wr_addr();
  import "DPI-C" function longint unsigned dpi_mfu_exp_wr_data();
  import "DPI-C" function int unsigned     dpi_mfu_exp_comp_bytes();
  import "DPI-C" function int unsigned     dpi_mfu_exp_uncomp_bytes();
  import "DPI-C" function int unsigned     dpi_mfu_exp_tr_mode();

  // ---------------------------------------------------------------------------
  // 1. UVM Sequence Item: mfu_seq_item
  // ---------------------------------------------------------------------------
  class mfu_seq_item extends uvm_sequence_item;
    `uvm_object_utils(mfu_seq_item)

    int unsigned    txn_id;
    mlu_opcode_e    opcode;
    mlu_mem_space_e src_space;
    mlu_mem_space_e dst_space;
    bit [7:0]       tag_id;
    bit [31:0]      src_base;
    bit [31:0]      dst_base;
    bit [15:0]      src1_or_strd;
    bit [15:0]      len_or_dims;
    bit [63:0]      idx_offset;
    bit [7:0]       decomp_bitmap;
    bit [63:0]      seed64;
    bit             resp_delay_en;

    // Observed per-beat fields
    int unsigned    beat_idx;
    logic [63:0]    raw_rd_data;
    logic [31:0]    act_rd_addr;
    logic [2:0]     act_rd_space;
    logic [31:0]    act_wr_addr;
    logic [2:0]     act_wr_space;
    logic [63:0]    act_wr_data;
    logic [31:0]    act_comp_bytes;
    logic [31:0]    act_uncomp_bytes;
    logic           act_tr_mode;

    function new(string name = "mfu_seq_item");
      super.new(name);
    endfunction
  endclass : mfu_seq_item

  // ---------------------------------------------------------------------------
  // 2. UVM Sequence: mfu_sequence (All 6 DMA Opcodes + All 256 Sparsity Bitmaps)
  // ---------------------------------------------------------------------------
  class mfu_sequence extends uvm_sequence #(mfu_seq_item);
    `uvm_object_utils(mfu_sequence)

    int unsigned     num_cmds   = 320;
    longint unsigned prng_state = 64'h5906_90DF_A123_4567;

    function new(string name = "mfu_sequence");
      super.new(name);
    endfunction

    function longint unsigned next_rand64();
      prng_state ^= (prng_state << 13);
      prng_state ^= (prng_state >> 7);
      prng_state ^= (prng_state << 17);
      return prng_state;
    endfunction

    task body();
      mlu_opcode_e ops[6] = '{
        OP_BANG_MEMCPY_1D, OP_BANG_MEMCPY_2D, OP_BANG_GATHER,
        OP_BANG_SCATTER,   OP_BANG_DECOMP_DMA, OP_BANG_TRANSPOSE
      };
      mlu_mem_space_e spaces[4] = '{
        MEM_SPACE_GDRAM, MEM_SPACE_SRAM, MEM_SPACE_NRAM, MEM_SPACE_WRAM
      };

      for (int unsigned t = 0; t < num_cmds; t++) begin
        mfu_seq_item item = mfu_seq_item::type_id::create("item");
        longint unsigned r0 = next_rand64();
        longint unsigned r1 = next_rand64();

        start_item(item);
        item.txn_id        = t;
        // First 256 commands include full sweep of all 256 bitmaps (0x00..0xFF) on DECOMP_DMA
        // interleaved with all 6 DMA opcodes
        if (t < 256) begin
          item.opcode        = (t % 4 == 0) ? ops[(t / 4) % 6] : OP_BANG_DECOMP_DMA;
          item.decomp_bitmap = 8'(t & 8'hFF);
        end else begin
          item.opcode        = ops[t % 6];
          item.decomp_bitmap = r0[7:0];
        end

        item.src_space     = spaces[r0[9:8]];
        item.dst_space     = spaces[r0[11:10]];
        item.tag_id        = 8'(t & 8'hFF);
        item.src_base      = {16'h0010, r0[31:19], 3'b000};
        item.dst_base      = {16'h0020, r0[47:35], 3'b000};
        item.idx_offset    = {r1[63:51], 3'b000, r1[47:35], 3'b000,
                              r1[31:19], 3'b000, r1[15:3],  3'b000};
        item.seed64        = next_rand64();
        item.resp_delay_en = bit'(t[0]);

        if (item.opcode == OP_BANG_MEMCPY_2D) begin
          bit [7:0] rows = 8'(1 + (r0[51:50])); // 1..4 rows
          bit [7:0] cols = 8'(1 + (r0[53:52])); // 1..4 cols
          bit [7:0] s_st = cols + 8'(r0[55:54]);
          bit [7:0] d_st = cols + 8'(r0[57:56]);
          item.len_or_dims  = {rows, cols};
          item.src1_or_strd = {s_st, d_st};
        end else if (item.opcode == OP_BANG_TRANSPOSE) begin
          item.len_or_dims  = 16'd8;
          item.src1_or_strd = 16'd0;
        end else begin
          item.len_or_dims  = 16'(1 + (r0[51:50])); // 1..4 beats
          item.src1_or_strd = 16'd0;
        end
        finish_item(item);
      end
    endtask
  endclass : mfu_sequence

  // ---------------------------------------------------------------------------
  // 3. UVM Sequencer: mfu_sequencer
  // ---------------------------------------------------------------------------
  class mfu_sequencer extends uvm_sequencer #(mfu_seq_item);
    `uvm_component_utils(mfu_sequencer)
    function new(string name = "mfu_sequencer", uvm_component parent = null);
      super.new(name, parent);
    endfunction
  endclass : mfu_sequencer

  // ---------------------------------------------------------------------------
  // 4. UVM Driver: mfu_driver
  // ---------------------------------------------------------------------------
  class mfu_driver extends uvm_driver #(mfu_seq_item);
    `uvm_component_utils(mfu_driver)

    virtual mlu_mfu_if vif;
    int unsigned driven_cmds = 0;

    function new(string name = "mfu_driver", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual mlu_mfu_if)::get(this, "", "vif", vif))
        `uvm_fatal("NO_VIF", "Virtual interface mlu_mfu_if missing in mfu_driver")
    endfunction

    task run_phase(uvm_phase phase);
      mfu_seq_item item;
      mlu_inst_t   inst;
      logic [63:0] beat_data;

      vif.rst_ni          = 1'b0;
      vif.cmd_valid_i     = 1'b0;
      vif.cmd_inst_i      = '0;
      vif.idx_offset_i    = '0;
      vif.decomp_bitmap_i = '0;
      vif.rd_resp_valid_i = 1'b0;
      vif.rd_resp_data_i  = '0;
      vif.mon_beat_idx    = 16'd0;
      repeat (4) @(posedge vif.clk);
      #1ns;
      vif.rst_ni = 1'b1;
      @(posedge vif.clk);
      #1ns;

      forever begin
        seq_item_port.get_next_item(item);
        while (!vif.cmd_ready_o) begin
          @(posedge vif.clk);
          #1ns;
        end

        inst              = '0;
        inst.opcode       = item.opcode;
        inst.engine       = ENG_MFU_DMA;
        inst.src_space    = item.src_space;
        inst.dst_space    = item.dst_space;
        inst.tag_id       = item.tag_id;
        inst.src0_addr    = item.src_base;
        inst.dst_addr     = item.dst_base;
        inst.src1_or_strd = item.src1_or_strd;
        inst.len_or_dims  = item.len_or_dims;

        vif.cmd_valid_i       = 1'b1;
        vif.cmd_inst_i        = inst;
        vif.idx_offset_i      = item.idx_offset;
        vif.decomp_bitmap_i   = item.decomp_bitmap;
        vif.mon_cmd_inst      = inst;
        vif.mon_idx_offset    = item.idx_offset;
        vif.mon_decomp_bitmap = item.decomp_bitmap;
        vif.mon_beat_idx      = 16'd0;

        @(posedge vif.clk);
        #1ns;
        vif.cmd_valid_i = 1'b0;

        forever begin
          vif.mon_latched_rd_addr  = vif.rd_req_addr_o;
          vif.mon_latched_rd_space = vif.rd_req_space_o;
          beat_data = item.seed64 ^ (64'(vif.mon_beat_idx) * 64'h0102_0304_0506_0708);
          vif.mon_raw_rd_data = beat_data;

          if (item.resp_delay_en) begin
            vif.rd_resp_valid_i = 1'b0;
            @(posedge vif.clk);
            #1ns;
          end

          vif.rd_resp_valid_i = 1'b1;
          vif.rd_resp_data_i  = beat_data;
          @(posedge vif.clk);
          #1ns;
          vif.rd_resp_valid_i = 1'b0;

          // Now in DMA_WR_REQ; monitor samples at negedge clk inside this cycle
          @(posedge vif.clk);
          #1ns;
          vif.mon_beat_idx = vif.mon_beat_idx + 16'd1;
          if (vif.done_valid_o) break;
        end

        driven_cmds++;
        seq_item_port.item_done();
      end
    endtask
  endclass : mfu_driver

  // ---------------------------------------------------------------------------
  // 5. UVM Monitor: mfu_monitor (with Functional Covergroup)
  // ---------------------------------------------------------------------------
  class mfu_monitor extends uvm_monitor;
    `uvm_component_utils(mfu_monitor)

    virtual mlu_mfu_if vif;
    uvm_analysis_port #(mfu_seq_item) ap;
    int unsigned seen_beats = 0;

    covergroup mfu_cg with function sample(
      bit [5:0] op,
      bit [2:0] s_space,
      bit [2:0] d_space,
      bit [1:0] bmp_cat
    );
      option.per_instance = 1;
      cp_op: coverpoint op {
        bins b_memcpy_1d  = {OP_BANG_MEMCPY_1D};
        bins b_memcpy_2d  = {OP_BANG_MEMCPY_2D};
        bins b_gather     = {OP_BANG_GATHER};
        bins b_scatter    = {OP_BANG_SCATTER};
        bins b_decomp_dma = {OP_BANG_DECOMP_DMA};
        bins b_transpose  = {OP_BANG_TRANSPOSE};
      }
      cp_bmp: coverpoint bmp_cat {
        bins bmp_all_zero = {2'd0};
        bins bmp_sparse   = {2'd1};
        bins bmp_dense    = {2'd2};
      }
    endgroup

    function new(string name = "mfu_monitor", uvm_component parent = null);
      super.new(name, parent);
      ap     = new("ap", this);
      mfu_cg = new();
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual mlu_mfu_if)::get(this, "", "vif", vif))
        `uvm_fatal("NO_VIF", "Virtual interface mlu_mfu_if missing in mfu_monitor")
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        @(negedge vif.clk);
        if (vif.rst_ni && vif.wr_req_valid_o) begin
          mfu_seq_item item = mfu_seq_item::type_id::create("mon_beat");
          mlu_inst_t   inst = vif.mon_cmd_inst;
          bit [1:0]    bcat = (vif.mon_decomp_bitmap == 8'h00) ? 2'd0 :
                              ((vif.mon_decomp_bitmap == 8'hFF) ? 2'd2 : 2'd1);

          item.txn_id           = seen_beats;
          item.opcode           = inst.opcode;
          item.src_space        = inst.src_space;
          item.dst_space        = inst.dst_space;
          item.tag_id           = inst.tag_id;
          item.src_base         = inst.src0_addr;
          item.dst_base         = inst.dst_addr;
          item.src1_or_strd     = inst.src1_or_strd;
          item.len_or_dims      = inst.len_or_dims;
          item.idx_offset       = vif.mon_idx_offset;
          item.decomp_bitmap    = vif.mon_decomp_bitmap;
          item.beat_idx         = int'(vif.mon_beat_idx);
          item.raw_rd_data      = vif.mon_raw_rd_data;
          item.act_rd_addr      = vif.mon_latched_rd_addr;
          item.act_rd_space     = vif.mon_latched_rd_space;
          item.act_wr_addr      = vif.wr_req_addr_o;
          item.act_wr_space     = vif.wr_req_space_o;
          item.act_wr_data      = vif.wr_req_data_o;
          item.act_comp_bytes   = vif.compressed_bytes_rd_o;
          item.act_uncomp_bytes = vif.uncompressed_bytes_wr_o;
          item.act_tr_mode      = vif.nram_transpose_mode_o;

          mfu_cg.sample(inst.opcode, inst.src_space, inst.dst_space, bcat);
          seen_beats++;
          ap.write(item);
        end
      end
    endtask
  endclass : mfu_monitor

  // ---------------------------------------------------------------------------
  // 6. UVM Agent: mfu_agent
  // ---------------------------------------------------------------------------
  class mfu_agent extends uvm_agent;
    `uvm_component_utils(mfu_agent)

    mfu_sequencer sequencer;
    mfu_driver    driver;
    mfu_monitor   monitor;

    function new(string name = "mfu_agent", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      sequencer = mfu_sequencer::type_id::create("sequencer", this);
      driver    = mfu_driver::type_id::create("driver", this);
      monitor   = mfu_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
  endclass : mfu_agent

  // ---------------------------------------------------------------------------
  // 7. UVM Scoreboard: mfu_scoreboard (Bit-Exact DPI-C Reference Check)
  // ---------------------------------------------------------------------------
  class mfu_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(mfu_scoreboard)

    uvm_analysis_imp #(mfu_seq_item, mfu_scoreboard) analysis_export;
    int unsigned checked_beats = 0;
    int unsigned mismatches    = 0;

    function new(string name = "mfu_scoreboard", uvm_component parent = null);
      super.new(name, parent);
      analysis_export = new("analysis_export", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      dpi_mfu_ref_reset();
    endfunction

    function void write(mfu_seq_item item);
      logic [31:0] exp_rd_addr, exp_wr_addr, exp_comp, exp_uncomp;
      logic [63:0] exp_wr_data;
      logic        exp_tr_mode;

      dpi_mfu_ref_eval_beat(
        int'(item.opcode),
        item.src_base,
        item.dst_base,
        int'(item.src1_or_strd),
        int'(item.len_or_dims),
        item.beat_idx,
        item.idx_offset,
        int'(item.decomp_bitmap),
        item.raw_rd_data
      );

      exp_rd_addr = dpi_mfu_exp_rd_addr();
      exp_wr_addr = dpi_mfu_exp_wr_addr();
      exp_wr_data = dpi_mfu_exp_wr_data();
      exp_comp    = dpi_mfu_exp_comp_bytes();
      exp_uncomp  = dpi_mfu_exp_uncomp_bytes();
      exp_tr_mode = 1'(dpi_mfu_exp_tr_mode());

      if (item.act_rd_addr      !== exp_rd_addr ||
          item.act_wr_addr      !== exp_wr_addr ||
          item.act_wr_data      !== exp_wr_data ||
          item.act_comp_bytes   !== exp_comp    ||
          item.act_uncomp_bytes !== exp_uncomp  ||
          item.act_tr_mode      !== exp_tr_mode ||
          item.act_rd_space     !== item.src_space ||
          item.act_wr_space     !== item.dst_space) begin
        mismatches++;
        `uvm_error("MFU_MISMATCH", $sformatf(
          "beat=%0d op=%02x rd_addr=%08x/%08x wr_addr=%08x/%08x wr_data=%016x/%016x comp=%0d/%0d uncomp=%0d/%0d tr=%0b/%0b",
          item.txn_id, item.opcode, item.act_rd_addr, exp_rd_addr,
          item.act_wr_addr, exp_wr_addr, item.act_wr_data, exp_wr_data,
          item.act_comp_bytes, exp_comp, item.act_uncomp_bytes, exp_uncomp,
          item.act_tr_mode, exp_tr_mode))
      end
      checked_beats++;
    endfunction
  endclass : mfu_scoreboard

  // ---------------------------------------------------------------------------
  // 8. UVM Environment & Test: mfu_env, mfu_dma_decomp_test
  // ---------------------------------------------------------------------------
  class mfu_env extends uvm_env;
    `uvm_component_utils(mfu_env)
    mfu_agent      agent;
    mfu_scoreboard scoreboard;
    function new(string name = "mfu_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent      = mfu_agent::type_id::create("agent", this);
      scoreboard = mfu_scoreboard::type_id::create("scoreboard", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent.monitor.ap.connect(scoreboard.analysis_export);
    endfunction
  endclass : mfu_env

  class mfu_dma_decomp_test extends uvm_test;
    `uvm_component_utils(mfu_dma_decomp_test)
    mfu_env env;
    function new(string name = "mfu_dma_decomp_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = mfu_env::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
      mfu_sequence seq = mfu_sequence::type_id::create("seq");
      phase.raise_objection(this);
      seq.start(env.agent.sequencer);
      phase.drop_objection(this);
    endtask
    function void report_phase(uvm_phase phase);
      int unsigned dpi_calls = dpi_mfu_get_calls();
      real         func_cov  = env.agent.monitor.mfu_cg.get_inst_coverage();
      bit          pass_gate = (env.agent.driver.driven_cmds == 320) &&
                               (env.scoreboard.checked_beats >= 800) &&
                               (dpi_calls == env.scoreboard.checked_beats) &&
                               (env.scoreboard.mismatches == 0) &&
                               (func_cov == 100.0);
      super.report_phase(phase);
      dpi_mfu_set_status(pass_gate ? 0 : 1);
      if (!pass_gate) begin
        `uvm_fatal("UVM_MFU_FAIL", $sformatf(
          "MFU UVM failed: cmds=%0d beats=%0d mismatches=%0d cov=%0.2f%%",
          env.agent.driver.driven_cmds, env.scoreboard.checked_beats,
          env.scoreboard.mismatches, func_cov))
      end else begin
        `uvm_info("UVM_MFU_PASS", $sformatf(
          "PASS: %0d DMA commands (%0d beats) verified bit-exact via DPI-C, 0 mismatches, %0.2f%% functional coverage",
          env.agent.driver.driven_cmds, env.scoreboard.checked_beats, func_cov), UVM_LOW)
      end
    endfunction
  endclass : mfu_dma_decomp_test

endpackage : mlu_mfu_uvm_pkg

`endif // MLU_MFU_UVM_PKG_SV
