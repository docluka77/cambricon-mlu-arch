// =============================================================================
// File: uvm_tb/uvm_mtp_cluster/mlu_mtp_cluster_uvm_pkg.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Accellera IEEE 1800.2-2020 UVM Verification Package for Suite 7:
//              mlu_mtp_cluster (4x mlu_ipu_core + 1x mlu_mpu_core +
//              Hardware Union-Task Barrier + 4-to-1 HBM2e GDRAM Arbiter).
// =============================================================================
`ifndef MLU_MTP_CLUSTER_UVM_PKG_SV
`define MLU_MTP_CLUSTER_UVM_PKG_SV

`timescale 1ns/1ps
`include "uvm_macros.svh"
`include "mlu_pkg.sv"

package mlu_mtp_cluster_uvm_pkg;
  import uvm_pkg::*;
  import mlu_pkg::*;

  // DPI-C C++17 Reference Model Imports
  import "DPI-C" function void             dpi_cluster_set_status(int status);
  import "DPI-C" function int              dpi_cluster_get_status();
  import "DPI-C" function int unsigned     dpi_cluster_get_calls();
  import "DPI-C" function longint unsigned dpi_cluster_ref_allreduce(
    longint unsigned dst_init,
    longint unsigned src_val
  );

  // Helper to construct 128-bit BANG ISA instructions
  function automatic logic [127:0] make_bang_inst(
    input mlu_opcode_e      op,
    input mlu_engine_e      eng,
    input mlu_prec_e        prec,
    input mlu_sparse_mode_e sp_mode,
    input mlu_mem_space_e   src_sp,
    input mlu_mem_space_e   dst_sp,
    input logic [3:0]       dep,
    input logic [7:0]       tag,
    input logic [31:0]      dst_a,
    input logic [31:0]      src0_a,
    input logic [15:0]      src1_s,
    input logic [15:0]      len_d
  );
    mlu_inst_t s;
    s.opcode       = op;
    s.engine       = eng;
    s.prec         = prec;
    s.sparse_mode  = sp_mode;
    s.src_space    = src_sp;
    s.dst_space    = dst_sp;
    s.dep_mask     = dep;
    s.tag_id       = tag;
    s.dst_addr     = dst_a;
    s.src0_addr    = src0_a;
    s.src1_or_strd = src1_s;
    s.len_or_dims  = len_d;
    return s;
  endfunction

  // ---------------------------------------------------------------------------
  // 1. UVM Sequence Item: mlu_mtp_cluster_seq_item
  // ---------------------------------------------------------------------------
  class mlu_mtp_cluster_seq_item extends uvm_sequence_item;
    `uvm_object_utils(mlu_mtp_cluster_seq_item)

    int unsigned        cycle_id;
    int unsigned        subtest_id;

    // Stimulus Fields
    logic [3:0]         ipu_inst_valid;
    logic [3:0][127:0]  ipu_inst;
    logic               mpu_cmd_valid;
    logic [127:0]       mpu_cmd_inst;
    logic [3:0]         union_task_mask;
    logic               wram_ping_pong_sel;
    logic [63:0]        mfu_idx_offset;
    logic [7:0]         mfu_decomp_bitmap;
    logic [127:0]       vfu_cos_sin_lut;
    logic               ext_sram_valid;
    logic               ext_sram_we;
    logic [10:0]        ext_sram_addr;
    logic [63:0]        ext_sram_wdata;
    logic [2:0]         err_inject_bank;
    logic [71:0]        err_inject_mask;

    // Observed DUT Response Fields
    logic [3:0]         act_ipu_inst_ready;
    logic               act_mpu_cmd_ready;
    logic               act_mpu_done_valid;
    logic [7:0]         act_mpu_done_tag;
    logic               act_ext_sram_grant;
    logic [63:0]        act_ext_sram_rdata;
    logic               act_ext_sram_rvalid;
    logic               act_gdram_req_valid;
    logic               act_gdram_req_we;
    logic [31:0]        act_gdram_req_addr;
    logic               act_gdram_resp_valid;
    logic [63:0]        act_gdram_resp_rdata;
    logic               act_noc_tx_valid;
    logic [127:0]       act_noc_tx_flit;
    logic               act_noc_rx_valid;
    logic               act_cluster_sec_err;
    logic               act_cluster_ded_err;
    logic               act_cluster_busy;
    logic [31:0]        act_union_barrier_cnt;
    logic [31:0]        act_cluster_retired_insts;
    logic [31:0]        act_cluster_active_mac_cycles;
    logic [31:0]        act_cluster_gated_saved_cycles;
    logic [31:0]        act_cluster_total_mac_ops;

    function new(string name = "mlu_mtp_cluster_seq_item");
      super.new(name);
    endfunction
  endclass : mlu_mtp_cluster_seq_item

  // ---------------------------------------------------------------------------
  // 2. UVM Sequencer
  // ---------------------------------------------------------------------------
  typedef uvm_sequencer #(mlu_mtp_cluster_seq_item) mlu_mtp_cluster_sequencer;

  // ---------------------------------------------------------------------------
  // 3. UVM Sequence: mlu_mtp_cluster_sequence (600 Cycles Union-Task Verification)
  // ---------------------------------------------------------------------------
  class mlu_mtp_cluster_sequence extends uvm_sequence #(mlu_mtp_cluster_seq_item);
    `uvm_object_utils(mlu_mtp_cluster_sequence)

    int unsigned num_cycles = 600;

    function new(string name = "mlu_mtp_cluster_sequence");
      super.new(name);
    endfunction

    task body();
      for (int unsigned cyc = 0; cyc < num_cycles; cyc++) begin
        mlu_mtp_cluster_seq_item item = mlu_mtp_cluster_seq_item::type_id::create("item");
        start_item(item);

        item.cycle_id           = cyc;
        item.subtest_id         = (cyc < 80)  ? 0 : (cyc < 200) ? 1 : (cyc < 320) ? 2 :
                                  (cyc < 420) ? 3 : (cyc < 520) ? 4 : 5;
        item.ipu_inst_valid     = 4'b0000;
        item.ipu_inst           = '0;
        item.mpu_cmd_valid      = 1'b0;
        item.mpu_cmd_inst       = 128'd0;
        item.union_task_mask    = 4'b1111;
        item.wram_ping_pong_sel = (cyc >= 240 && cyc < 320);
        item.mfu_idx_offset     = {16'd24, 16'd16, 16'd8, 16'd0};
        item.mfu_decomp_bitmap  = 8'b1010_0101;
        item.vfu_cos_sin_lut    = {4{16'h0080, 16'h00DF}};
        item.ext_sram_valid     = 1'b0;
        item.ext_sram_we        = 1'b0;
        item.ext_sram_addr      = 11'd0;
        item.ext_sram_wdata     = 64'd0;
        item.err_inject_bank    = 3'd0;
        item.err_inject_mask    = 72'd0;

        // Phase 0 (0..79): Preload Shared SRAM & MPU 1-to-4 OP_MPU_BCAST_SRAM
        if (cyc >= 2 && cyc < 18) begin
          int idx = cyc - 2;
          item.ext_sram_valid = 1'b1;
          item.ext_sram_we    = 1'b1;
          item.ext_sram_addr  = 11'(idx);
          item.ext_sram_wdata = 64'((idx + 1) * 100);
        end else if (cyc >= 18 && cyc < 22) begin
          int idx = cyc - 18;
          item.ext_sram_valid = 1'b1;
          item.ext_sram_we    = 1'b1;
          item.ext_sram_addr  = 11'(16 + idx);
          item.ext_sram_wdata = 64'((idx + 5) * 10);
        end else if (cyc == 25) begin
          item.mpu_cmd_valid = 1'b1;
          item.mpu_cmd_inst  = make_bang_inst(
            OP_MPU_BCAST_SRAM, ENG_MPU_COL, PREC_FP16, SPARSE_DENSE,
            MEM_SPACE_SRAM, MEM_SPACE_NRAM, 4'b0000, 8'hA1,
            32'h0000_0000, 32'h0000_0000, 16'h0000, 16'd4
          );
        end else if (cyc == 40) begin
          item.mpu_cmd_valid = 1'b1;
          item.mpu_cmd_inst  = make_bang_inst(
            OP_MPU_BCAST_SRAM, ENG_MPU_COL, PREC_INT8, SPARSE_DENSE,
            MEM_SPACE_SRAM, MEM_SPACE_WRAM, 4'b0000, 8'hA2,
            32'h0000_0020, 32'h0000_0020, 16'h0000, 16'd8
          );
        end

        // Phase 1 (80..199): Concurrent 4-IPU MFU 1D/2D/Gather/Transpose/Decomp DMA over GDRAM
        else if (cyc == 85) begin
          item.ipu_inst_valid = 4'b1111;
          item.ipu_inst[0] = make_bang_inst(OP_BANG_MEMCPY_1D,  ENG_MFU_DMA, PREC_INT8, SPARSE_DENSE,
                                            MEM_SPACE_GDRAM, MEM_SPACE_NRAM, 4'b0000, 8'h10,
                                            32'h0000_0000, 32'h0000_0000, 16'h0008, 16'h0004);
          item.ipu_inst[1] = make_bang_inst(OP_BANG_MEMCPY_2D,  ENG_MFU_DMA, PREC_INT8, SPARSE_DENSE,
                                            MEM_SPACE_GDRAM, MEM_SPACE_NRAM, 4'b0000, 8'h11,
                                            32'h0000_0000, 32'h0000_0020, 16'h0010, 16'h0202);
          item.ipu_inst[2] = make_bang_inst(OP_BANG_DECOMP_DMA, ENG_MFU_DMA, PREC_INT8, SPARSE_2_OF_4,
                                            MEM_SPACE_GDRAM, MEM_SPACE_WRAM, 4'b0000, 8'h12,
                                            32'h0000_0000, 32'h0000_0040, 16'h0008, 16'h0004);
          item.ipu_inst[3] = make_bang_inst(OP_BANG_GATHER,     ENG_MFU_DMA, PREC_BF16, SPARSE_DENSE,
                                            MEM_SPACE_GDRAM, MEM_SPACE_NRAM, 4'b0000, 8'h13,
                                            32'h0000_0000, 32'h0000_0060, 16'h0008, 16'h0004);
        end else if (cyc == 135) begin
          item.ipu_inst_valid = 4'b1111;
          item.ipu_inst[0] = make_bang_inst(OP_BANG_TRANSPOSE,  ENG_MFU_DMA, PREC_FP16, SPARSE_DENSE,
                                            MEM_SPACE_GDRAM, MEM_SPACE_NRAM, 4'b0000, 8'h14,
                                            32'h0000_0040, 32'h0000_0080, 16'h0008, 16'h0004);
          item.ipu_inst[1] = make_bang_inst(OP_BANG_DECOMP_DMA, ENG_MFU_DMA, PREC_INT4, SPARSE_BLOCK_4X4,
                                            MEM_SPACE_GDRAM, MEM_SPACE_NRAM, 4'b0000, 8'h15,
                                            32'h0000_0040, 32'h0000_00A0, 16'h0008, 16'h0004);
          item.ipu_inst[2] = make_bang_inst(OP_BANG_MEMCPY_2D,  ENG_MFU_DMA, PREC_FP16, SPARSE_DENSE,
                                            MEM_SPACE_GDRAM, MEM_SPACE_NRAM, 4'b0000, 8'h16,
                                            32'h0000_0040, 32'h0000_00C0, 16'h0010, 16'h0202);
          item.ipu_inst[3] = make_bang_inst(OP_BANG_SCATTER,    ENG_MFU_DMA, PREC_FP16, SPARSE_DENSE,
                                            MEM_SPACE_NRAM,  MEM_SPACE_GDRAM, 4'b0000, 8'h17,
                                            32'h0000_0100, 32'h0000_0000, 16'h0008, 16'h0004);
        end

        // Phase 2 (200..319): Parallel 4-IPU TFU (MATMUL, SPARSE_MM, QUANT_MM)
        else if (cyc == 205) begin
          item.ipu_inst_valid = 4'b1111;
          item.ipu_inst[0] = make_bang_inst(OP_BANG_MATMUL,    ENG_TFU_MAT, PREC_INT8, SPARSE_DENSE,
                                            MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h20,
                                            32'h0000_0100, 32'h0000_0000, 16'h0000, 16'h0004);
          item.ipu_inst[1] = make_bang_inst(OP_BANG_SPARSE_MM, ENG_TFU_MAT, PREC_INT4, SPARSE_2_OF_4,
                                            MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h21,
                                            32'h0000_0100, 32'h0000_0000, 16'h0000, 16'h0004);
          item.ipu_inst[2] = make_bang_inst(OP_BANG_QUANT_MM,  ENG_TFU_MAT, PREC_INT8, SPARSE_DENSE,
                                            MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h22,
                                            32'h0000_0100, 32'h0000_0000, 16'h0000, 16'h0004);
          item.ipu_inst[3] = make_bang_inst(OP_BANG_MATMUL,    ENG_TFU_MAT, PREC_BF16, SPARSE_DENSE,
                                            MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h23,
                                            32'h0000_0100, 32'h0000_0000, 16'h0000, 16'h0004);
        end else if (cyc == 255) begin
          item.ipu_inst_valid = 4'b1111;
          item.ipu_inst[0] = make_bang_inst(OP_BANG_SPARSE_MM, ENG_TFU_MAT, PREC_INT8, SPARSE_2_OF_4,
                                            MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h24,
                                            32'h0000_0140, 32'h0000_0000, 16'h0000, 16'h0004);
          item.ipu_inst[1] = make_bang_inst(OP_BANG_QUANT_MM,  ENG_TFU_MAT, PREC_INT4, SPARSE_DENSE,
                                            MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h25,
                                            32'h0000_0140, 32'h0000_0000, 16'h0000, 16'h0004);
          item.ipu_inst[2] = make_bang_inst(OP_BANG_MATMUL,    ENG_TFU_MAT, PREC_FP16, SPARSE_DENSE,
                                            MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h26,
                                            32'h0000_0140, 32'h0000_0000, 16'h0000, 16'h0004);
          item.ipu_inst[3] = make_bang_inst(OP_BANG_SPARSE_MM, ENG_TFU_MAT, PREC_INT4, SPARSE_BLOCK_4X4,
                                            MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h27,
                                            32'h0000_0140, 32'h0000_0000, 16'h0000, 16'h0004);
        end

        // Phase 3 (320..419): Parallel 4-IPU VFU/SFU (RoPE, RMSNorm, Softmax, SwiGLU)
        else if (cyc == 325) begin
          item.ipu_inst_valid = 4'b1111;
          item.ipu_inst[0] = make_bang_inst(OP_BANG_ROPE,    ENG_VFU_VEC, PREC_FP16, SPARSE_DENSE,
                                            MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h30,
                                            32'h0000_0200, 32'h0000_0100, 16'h0000, 16'h0002);
          item.ipu_inst[1] = make_bang_inst(OP_BANG_RMSNORM, ENG_VFU_VEC, PREC_FP16, SPARSE_DENSE,
                                            MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h31,
                                            32'h0000_0200, 32'h0000_0100, 16'h0000, 16'h0002);
          item.ipu_inst[2] = make_bang_inst(OP_BANG_SOFTMAX, ENG_VFU_VEC, PREC_FP16, SPARSE_DENSE,
                                            MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h32,
                                            32'h0000_0200, 32'h0000_0100, 16'h0000, 16'h0002);
          item.ipu_inst[3] = make_bang_inst(OP_BANG_SWIGLU,  ENG_VFU_VEC, PREC_FP16, SPARSE_DENSE,
                                            MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h33,
                                            32'h0000_0200, 32'h0000_0100, 16'h0000, 16'h0002);
        end else if (cyc == 370) begin
          item.ipu_inst_valid = 4'b1111;
          item.ipu_inst[0] = make_bang_inst(OP_BANG_QUANT_STAT, ENG_VFU_VEC, PREC_BF16, SPARSE_DENSE,
                                            MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h34,
                                            32'h0000_0240, 32'h0000_0200, 16'h0000, 16'h0002);
          item.ipu_inst[1] = make_bang_inst(OP_LLM_KV_PACK,     ENG_VFU_VEC, PREC_BF16, SPARSE_DENSE,
                                            MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h35,
                                            32'h0000_0240, 32'h0000_0200, 16'h0000, 16'h0002);
          item.ipu_inst[2] = make_bang_inst(OP_BANG_VADD,       ENG_VFU_VEC, PREC_FP16, SPARSE_DENSE,
                                            MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h36,
                                            32'h0000_0240, 32'h0000_0200, 16'h0000, 16'h0002);
          item.ipu_inst[3] = make_bang_inst(OP_BANG_VMUL,       ENG_VFU_VEC, PREC_FP16, SPARSE_DENSE,
                                            MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h37,
                                            32'h0000_0240, 32'h0000_0200, 16'h0000, 16'h0002);
        end

        // Phase 4 (420..519): Multi-Core OP_SYNC_CLUSTER Barrier & OP_MPU_ALLREDUCE
        else if (cyc == 425) begin
          item.ipu_inst_valid = 4'b0111; // IPU 0..2 arrive first
          for (int i = 0; i < 3; i++) begin
            item.ipu_inst[i] = make_bang_inst(OP_SYNC_CLUSTER, ENG_ICU_CTRL, PREC_FP16, SPARSE_DENSE,
                                              MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'(8'h40 + i),
                                              32'd0, 32'd0, 16'd0, 16'd0);
          end
        end else if (cyc == 430) begin
          item.ipu_inst_valid = 4'b1000; // IPU 3 arrives -> barrier #1 completes
          item.ipu_inst[3]    = make_bang_inst(OP_SYNC_CLUSTER, ENG_ICU_CTRL, PREC_FP16, SPARSE_DENSE,
                                               MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h43,
                                               32'd0, 32'd0, 16'd0, 16'd0);
        end else if (cyc >= 440 && cyc <= 448) begin
          item.union_task_mask = 4'b0011; // 2-core Union-Task barrier #2
          if (cyc == 442) begin
            item.ipu_inst_valid = 4'b0011;
            item.ipu_inst[0] = make_bang_inst(OP_SYNC_CLUSTER, ENG_ICU_CTRL, PREC_FP16, SPARSE_DENSE,
                                              MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h44,
                                              32'd0, 32'd0, 16'd0, 16'd0);
            item.ipu_inst[1] = make_bang_inst(OP_SYNC_CLUSTER, ENG_ICU_CTRL, PREC_FP16, SPARSE_DENSE,
                                              MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h45,
                                              32'd0, 32'd0, 16'd0, 16'd0);
          end
        end else if (cyc == 460) begin
          // OP_MPU_ALLREDUCE: read src0_addr=0 (words 0..3: 100..400), accumulate into dst_addr=0x80 (words 16..19: 50..80)
          item.mpu_cmd_valid = 1'b1;
          item.mpu_cmd_inst  = make_bang_inst(
            OP_MPU_ALLREDUCE, ENG_MPU_COL, PREC_FP16, SPARSE_DENSE,
            MEM_SPACE_SRAM, MEM_SPACE_MLULK, 4'b0000, 8'hB1,
            32'h0000_0080, 32'h0000_0000, 16'h000C, 16'd4
          );
        end else if (cyc >= 485 && cyc < 489) begin
          // Read back Shared SRAM words 16..19 to verify in-SRAM atomic AllReduce result
          item.ext_sram_valid = 1'b1;
          item.ext_sram_we    = 1'b0;
          item.ext_sram_addr  = 11'(16 + (cyc - 485));
        end

        // Phase 5 (520..599): SECDED ECC SEC/DED Fault Injection & Barrier #3
        else if (cyc == 525) begin
          item.ipu_inst_valid = 4'b0001;
          item.ipu_inst[0]    = make_bang_inst(OP_BANG_MATMUL, ENG_TFU_MAT, PREC_INT8, SPARSE_DENSE,
                                               MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h50,
                                               32'h0000_0200, 32'h0000_0000, 16'h0000, 16'h0004);
        end else if (cyc == 526 || cyc == 527) begin
          item.err_inject_bank = 3'd0;
          item.err_inject_mask = 72'h00_0000_0000_0000_0001; // 1-bit SEC
        end else if (cyc == 528 || cyc == 529) begin
          item.err_inject_bank = 3'd0;
          item.err_inject_mask = 72'h00_0000_0000_0000_0003; // 2-bit DED
        end else if (cyc == 550) begin
          item.ipu_inst_valid = 4'b1111; // All 4 IPUs simultaneous barrier #3
          for (int i = 0; i < 4; i++) begin
            item.ipu_inst[i] = make_bang_inst(OP_SYNC_CLUSTER, ENG_ICU_CTRL, PREC_FP16, SPARSE_DENSE,
                                              MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'(8'h60 + i),
                                              32'd0, 32'd0, 16'd0, 16'd0);
          end
        end

        finish_item(item);
      end
    endtask
  endclass : mlu_mtp_cluster_sequence

  // ---------------------------------------------------------------------------
  // 4. UVM Driver: mlu_mtp_cluster_driver
  // ---------------------------------------------------------------------------
  class mlu_mtp_cluster_driver extends uvm_driver #(mlu_mtp_cluster_seq_item);
    `uvm_component_utils(mlu_mtp_cluster_driver)

    virtual mlu_mtp_cluster_if vif;
    int unsigned driven = 0;

    function new(string name = "mlu_mtp_cluster_driver", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual mlu_mtp_cluster_if)::get(this, "", "vif", vif)) begin
        `uvm_fatal("NO_VIF", "Virtual interface mlu_mtp_cluster_if missing in mlu_mtp_cluster_driver")
      end
    endfunction

    task run_phase(uvm_phase phase);
      mlu_mtp_cluster_seq_item item;
      vif.rst_n       = 1'b0;
      vif.cycle_valid = 1'b0;
      repeat (3) @(negedge vif.clk);

      forever begin
        seq_item_port.get_next_item(item);
        vif.rst_n              = 1'b1;
        vif.cycle_id           = item.cycle_id;
        vif.subtest_id         = item.subtest_id;
        vif.ipu_inst_valid     = item.ipu_inst_valid;
        vif.ipu_inst           = item.ipu_inst;
        vif.mpu_cmd_valid      = item.mpu_cmd_valid;
        vif.mpu_cmd_inst       = item.mpu_cmd_inst;
        vif.union_task_mask    = item.union_task_mask;
        vif.wram_ping_pong_sel = item.wram_ping_pong_sel;
        vif.mfu_idx_offset     = item.mfu_idx_offset;
        vif.mfu_decomp_bitmap  = item.mfu_decomp_bitmap;
        vif.vfu_cos_sin_lut    = item.vfu_cos_sin_lut;
        vif.ext_sram_valid     = item.ext_sram_valid;
        vif.ext_sram_we        = item.ext_sram_we;
        vif.ext_sram_addr      = item.ext_sram_addr;
        vif.ext_sram_wdata     = item.ext_sram_wdata;
        vif.err_inject_bank    = item.err_inject_bank;
        vif.err_inject_mask    = item.err_inject_mask;

        vif.cycle_valid = 1'b1;
        @(posedge vif.clk);
        #1ns;
        vif.cycle_valid = 1'b0;
        driven++;
        @(negedge vif.clk);
        seq_item_port.item_done();
      end
    endtask
  endclass : mlu_mtp_cluster_driver

  // ---------------------------------------------------------------------------
  // 5. UVM Monitor: mlu_mtp_cluster_monitor (with Functional Covergroup)
  // ---------------------------------------------------------------------------
  class mlu_mtp_cluster_monitor extends uvm_monitor;
    `uvm_component_utils(mlu_mtp_cluster_monitor)

    virtual mlu_mtp_cluster_if vif;
    uvm_analysis_port #(mlu_mtp_cluster_seq_item) ap;
    int unsigned seen = 0;

    covergroup mlu_mtp_cluster_cg with function sample(
      int unsigned subtest,
      bit          mpu_done,
      bit          gdram_req,
      bit          noc_tx,
      bit          sec_err,
      bit          ded_err,
      bit          barrier_hit
    );
      option.per_instance = 1;
      cp_subtest: coverpoint subtest {
        bins st_bcast     = {0};
        bins st_mfu_gdram = {1};
        bins st_tfu_4ipu  = {2};
        bins st_vfu_4ipu  = {3};
        bins st_sync_allr = {4};
        bins st_ecc_pmu   = {5};
      }
      cp_mpu_done: coverpoint mpu_done    { bins b0 = {0}; bins b1 = {1}; }
      cp_gdram:    coverpoint gdram_req   { bins b0 = {0}; bins b1 = {1}; }
      cp_noc_tx:   coverpoint noc_tx      { bins b0 = {0}; bins b1 = {1}; }
      cp_sec:      coverpoint sec_err     { bins b0 = {0}; bins b1 = {1}; }
      cp_ded:      coverpoint ded_err     { bins b0 = {0}; bins b1 = {1}; }
      cp_barrier:  coverpoint barrier_hit { bins b0 = {0}; bins b1 = {1}; }
    endgroup

    function new(string name = "mlu_mtp_cluster_monitor", uvm_component parent = null);
      super.new(name, parent);
      ap = new("ap", this);
      mlu_mtp_cluster_cg = new();
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual mlu_mtp_cluster_if)::get(this, "", "vif", vif)) begin
        `uvm_fatal("NO_VIF", "Virtual interface mlu_mtp_cluster_if missing in mlu_mtp_cluster_monitor")
      end
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        @(negedge vif.clk);
        #1ns;
        if (vif.rst_n && vif.cycle_valid) begin
          mlu_mtp_cluster_seq_item item = mlu_mtp_cluster_seq_item::type_id::create("obs_item");
          item.cycle_id                       = vif.cycle_id;
          item.subtest_id                     = vif.subtest_id;
          item.ipu_inst_valid                 = vif.ipu_inst_valid;
          item.ipu_inst                       = vif.ipu_inst;
          item.mpu_cmd_valid                  = vif.mpu_cmd_valid;
          item.mpu_cmd_inst                   = vif.mpu_cmd_inst;
          item.union_task_mask                = vif.union_task_mask;
          item.wram_ping_pong_sel             = vif.wram_ping_pong_sel;
          item.ext_sram_valid                 = vif.ext_sram_valid;
          item.ext_sram_we                    = vif.ext_sram_we;
          item.ext_sram_addr                  = vif.ext_sram_addr;
          item.ext_sram_wdata                 = vif.ext_sram_wdata;
          item.err_inject_bank                = vif.err_inject_bank;
          item.err_inject_mask                = vif.err_inject_mask;

          item.act_ipu_inst_ready             = vif.ipu_inst_ready;
          item.act_mpu_cmd_ready              = vif.mpu_cmd_ready;
          item.act_mpu_done_valid             = vif.mpu_done_valid;
          item.act_mpu_done_tag               = vif.mpu_done_tag;
          item.act_ext_sram_grant             = vif.ext_sram_grant;
          item.act_ext_sram_rdata             = vif.ext_sram_rdata;
          item.act_ext_sram_rvalid            = vif.ext_sram_rvalid;
          item.act_gdram_req_valid            = vif.gdram_req_valid;
          item.act_gdram_req_we               = vif.gdram_req_we;
          item.act_gdram_req_addr             = vif.gdram_req_addr;
          item.act_gdram_resp_valid           = vif.gdram_resp_valid;
          item.act_gdram_resp_rdata           = vif.gdram_resp_rdata;
          item.act_noc_tx_valid               = vif.noc_tx_valid;
          item.act_noc_tx_flit                = vif.noc_tx_flit;
          item.act_noc_rx_valid               = vif.noc_rx_valid;
          item.act_cluster_sec_err            = vif.cluster_sec_err;
          item.act_cluster_ded_err            = vif.cluster_ded_err;
          item.act_cluster_busy               = vif.cluster_busy;
          item.act_union_barrier_cnt          = vif.union_barrier_cnt;
          item.act_cluster_retired_insts      = vif.cluster_retired_insts;
          item.act_cluster_active_mac_cycles  = vif.cluster_active_mac_cycles;
          item.act_cluster_gated_saved_cycles = vif.cluster_gated_saved_cycles;
          item.act_cluster_total_mac_ops      = vif.cluster_total_mac_ops;

          mlu_mtp_cluster_cg.sample(
            vif.subtest_id,
            vif.mpu_done_valid,
            vif.gdram_req_valid,
            vif.noc_tx_valid,
            vif.cluster_sec_err,
            vif.cluster_ded_err,
            (vif.union_barrier_cnt > 0)
          );

          seen++;
          ap.write(item);
        end
      end
    endtask
  endclass : mlu_mtp_cluster_monitor

  // ---------------------------------------------------------------------------
  // 6. UVM Agent: mlu_mtp_cluster_agent
  // ---------------------------------------------------------------------------
  class mlu_mtp_cluster_agent extends uvm_agent;
    `uvm_component_utils(mlu_mtp_cluster_agent)
    mlu_mtp_cluster_sequencer sequencer;
    mlu_mtp_cluster_driver    driver;
    mlu_mtp_cluster_monitor   monitor;

    function new(string name = "mlu_mtp_cluster_agent", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      sequencer = mlu_mtp_cluster_sequencer::type_id::create("sequencer", this);
      driver    = mlu_mtp_cluster_driver::type_id::create("driver", this);
      monitor   = mlu_mtp_cluster_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
  endclass : mlu_mtp_cluster_agent

  // ---------------------------------------------------------------------------
  // 7. UVM Scoreboard: mlu_mtp_cluster_scoreboard (with DPI-C Golden Checks)
  // ---------------------------------------------------------------------------
  class mlu_mtp_cluster_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(mlu_mtp_cluster_scoreboard)

    uvm_analysis_imp #(mlu_mtp_cluster_seq_item, mlu_mtp_cluster_scoreboard) analysis_export;

    int unsigned checked_cycles       = 0;
    int unsigned mismatches           = 0;
    int unsigned mpu_bcast_done_cnt   = 0;
    int unsigned mpu_allred_done_cnt  = 0;
    int unsigned gdram_arb_reqs       = 0;
    int unsigned gdram_resp_beats     = 0;
    int unsigned noc_allred_flits     = 0;
    int unsigned allred_sram_checks   = 0;
    int unsigned sec_err_hits         = 0;
    int unsigned ded_err_hits         = 0;
    int unsigned max_barriers         = 0;
    int unsigned max_retired_insts    = 0;
    int unsigned max_active_mac_cycs  = 0;
    int unsigned max_gated_saved_cycs = 0;
    int unsigned max_total_mac_ops    = 0;

    function new(string name = "mlu_mtp_cluster_scoreboard", uvm_component parent = null);
      super.new(name, parent);
      analysis_export = new("analysis_export", this);
    endfunction

    function void write(mlu_mtp_cluster_seq_item item);
      checked_cycles++;

      if (item.act_mpu_done_valid) begin
        if (item.act_mpu_done_tag == 8'hA1 || item.act_mpu_done_tag == 8'hA2)
          mpu_bcast_done_cnt++;
        else if (item.act_mpu_done_tag == 8'hB1)
          mpu_allred_done_cnt++;
      end

      if (item.act_gdram_req_valid)  gdram_arb_reqs++;
      if (item.act_gdram_resp_valid) gdram_resp_beats++;
      if (item.act_noc_tx_valid)     noc_allred_flits++;
      if (item.act_cluster_sec_err)  sec_err_hits++;
      if (item.act_cluster_ded_err)  ded_err_hits++;

      if (item.act_union_barrier_cnt > max_barriers)
        max_barriers = item.act_union_barrier_cnt;
      if (item.act_cluster_retired_insts > max_retired_insts)
        max_retired_insts = item.act_cluster_retired_insts;
      if (item.act_cluster_active_mac_cycles > max_active_mac_cycs)
        max_active_mac_cycs = item.act_cluster_active_mac_cycles;
      if (item.act_cluster_gated_saved_cycles > max_gated_saved_cycs)
        max_gated_saved_cycs = item.act_cluster_gated_saved_cycles;
      if (item.act_cluster_total_mac_ops > max_total_mac_ops)
        max_total_mac_ops = item.act_cluster_total_mac_ops;

      // Verify In-SRAM Atomic AllReduce Readback against DPI-C Reference Model
      if (item.cycle_id >= 486 && item.cycle_id < 490 && item.act_ext_sram_rvalid) begin
        int idx = item.cycle_id - 486;
        longint unsigned exp_val = dpi_cluster_ref_allreduce(
          64'((idx + 5) * 10),
          64'((idx + 1) * 100)
        );
        if (item.act_ext_sram_rdata !== exp_val) begin
          `uvm_error("CLUSTER_ALLRED_MISMATCH", $sformatf(
            "Cyc %0d idx=%0d: act=%0d exp=%0d", item.cycle_id, idx, item.act_ext_sram_rdata, exp_val))
          mismatches++;
        end else begin
          allred_sram_checks++;
        end
      end
    endfunction
  endclass : mlu_mtp_cluster_scoreboard

  // ---------------------------------------------------------------------------
  // 8. UVM Environment & Test
  // ---------------------------------------------------------------------------
  class mlu_mtp_cluster_env extends uvm_env;
    `uvm_component_utils(mlu_mtp_cluster_env)
    mlu_mtp_cluster_agent      agent;
    mlu_mtp_cluster_scoreboard scoreboard;

    function new(string name = "mlu_mtp_cluster_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent      = mlu_mtp_cluster_agent::type_id::create("agent", this);
      scoreboard = mlu_mtp_cluster_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent.monitor.ap.connect(scoreboard.analysis_export);
    endfunction
  endclass : mlu_mtp_cluster_env

  class mlu_mtp_cluster_test extends uvm_test;
    `uvm_component_utils(mlu_mtp_cluster_test)
    mlu_mtp_cluster_env env;

    function new(string name = "mlu_mtp_cluster_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = mlu_mtp_cluster_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
      mlu_mtp_cluster_sequence seq = mlu_mtp_cluster_sequence::type_id::create("seq");
      phase.raise_objection(this);
      seq.start(env.agent.sequencer);
      phase.drop_objection(this);
    endtask

    function void report_phase(uvm_phase phase);
      real func_cov = env.agent.monitor.mlu_mtp_cluster_cg.get_inst_coverage();
      bit pass_gate = (env.agent.driver.driven == 600) &&
                      (env.scoreboard.checked_cycles == 600) &&
                      (env.scoreboard.mismatches == 0) &&
                      (env.scoreboard.mpu_bcast_done_cnt >= 2) &&
                      (env.scoreboard.mpu_allred_done_cnt >= 1) &&
                      (env.scoreboard.gdram_arb_reqs >= 10) &&
                      (env.scoreboard.gdram_resp_beats >= 6) &&
                      (env.scoreboard.noc_allred_flits == 4) &&
                      (env.scoreboard.allred_sram_checks == 4) &&
                      (env.scoreboard.max_barriers >= 2) &&
                      (env.scoreboard.max_retired_insts >= 25) &&
                      (env.scoreboard.max_active_mac_cycs >= 20) &&
                      (env.scoreboard.max_gated_saved_cycs >= 100) &&
                      (env.scoreboard.max_total_mac_ops >= 1000) &&
                      (env.scoreboard.sec_err_hits > 0) &&
                      (env.scoreboard.ded_err_hits > 0);
      super.report_phase(phase);
      dpi_cluster_set_status(pass_gate ? 0 : 1);
      if (!pass_gate) begin
        `uvm_fatal("UVM_CLUSTER_FAIL", $sformatf(
          "Suite 7 gate failed: mismatches=%0d bcast=%0d allred=%0d gdram=%0d sram_chk=%0d bar=%0d ret=%0d mac_ops=%0d sec=%0d ded=%0d cov=%0.2f%%",
          env.scoreboard.mismatches, env.scoreboard.mpu_bcast_done_cnt,
          env.scoreboard.mpu_allred_done_cnt, env.scoreboard.gdram_arb_reqs,
          env.scoreboard.allred_sram_checks, env.scoreboard.max_barriers,
          env.scoreboard.max_retired_insts, env.scoreboard.max_total_mac_ops,
          env.scoreboard.sec_err_hits, env.scoreboard.ded_err_hits, func_cov))
      end else begin
        `uvm_info("UVM_CLUSTER_PASS", $sformatf(
          "SUITE 7 PASS: cycles=%0d dpi_calls=%0d bcast=%0d allred_flits=%0d sram_chk=%0d gdram_reqs=%0d barriers=%0d retired=%0d mac_ops=%0d gated_cycs=%0d sec=%0d ded=%0d cov=%0.2f%%",
          env.scoreboard.checked_cycles, dpi_cluster_get_calls(),
          env.scoreboard.mpu_bcast_done_cnt, env.scoreboard.noc_allred_flits,
          env.scoreboard.allred_sram_checks, env.scoreboard.gdram_arb_reqs,
          env.scoreboard.max_barriers, env.scoreboard.max_retired_insts,
          env.scoreboard.max_total_mac_ops, env.scoreboard.max_gated_saved_cycs,
          env.scoreboard.sec_err_hits, env.scoreboard.ded_err_hits, func_cov), UVM_LOW)
      end
    endfunction
  endclass : mlu_mtp_cluster_test

endpackage : mlu_mtp_cluster_uvm_pkg

`endif // MLU_MTP_CLUSTER_UVM_PKG_SV
