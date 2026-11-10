//      // verilator_coverage annotation
        // =============================================================================
        // File: uvm_tb/uvm_mlu_chip_top/mlu_chip_top_uvm_pkg.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: Accellera IEEE 1800.2-2020 UVM Verification Package for Suite 8:
        //              mlu_chip_top (MTP Cluster + MLU-Link NoC Router + C2C SerDes PCS)
        // =============================================================================
        `ifndef MLU_CHIP_TOP_UVM_PKG_SV
        `define MLU_CHIP_TOP_UVM_PKG_SV
        
        `timescale 1ns/1ps
        `include "uvm_macros.svh"
        `include "mlu_pkg.sv"
        
        package mlu_chip_top_uvm_pkg;
          import uvm_pkg::*;
          import mlu_pkg::*;
        
          // DPI-C C++17 Reference Model Imports
          import "DPI-C" function void             dpi_chip_top_set_status(int status);
          import "DPI-C" function int              dpi_chip_top_get_status();
          import "DPI-C" function int unsigned     dpi_chip_top_get_calls();
          import "DPI-C" function longint unsigned dpi_chip_top_ref_allreduce(
            longint unsigned dst_init,
            longint unsigned src_val
          );
          import "DPI-C" function int unsigned     dpi_chip_top_ref_crc16(
            longint unsigned flit_hi,
            longint unsigned flit_lo
          );
        
          // Helper to construct 128-bit BANG ISA instructions
 000037   function automatic logic [127:0] make_bang_inst(
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
 000037     mlu_inst_t s;
 000037     s.opcode       = op;
 000037     s.engine       = eng;
 000037     s.prec         = prec;
 000037     s.sparse_mode  = sp_mode;
 000037     s.src_space    = src_sp;
 000037     s.dst_space    = dst_sp;
 000037     s.dep_mask     = dep;
 000037     s.tag_id       = tag;
 000037     s.dst_addr     = dst_a;
 000037     s.src0_addr    = src0_a;
 000037     s.src1_or_strd = src1_s;
 000037     s.len_or_dims  = len_d;
 000037     return s;
          endfunction
        
          // ---------------------------------------------------------------------------
          // 1. UVM Sequence Item: mlu_chip_top_seq_item
          // ---------------------------------------------------------------------------
%000000   class mlu_chip_top_seq_item extends uvm_sequence_item;
~000600     `uvm_object_utils(mlu_chip_top_seq_item)
        
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
            logic               noc_allreduce_en;
            logic               ext_sram_valid;
            logic               ext_sram_we;
            logic [10:0]        ext_sram_addr;
            logic [63:0]        ext_sram_wdata;
            logic               c2c_err_inject_crc;
            logic               c2c_replay_trigger;
            logic [4:0]         c2c_replay_seq;
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
            logic               act_c2c_tx_valid;
            logic [127:0]       act_c2c_tx_flit;
            logic               act_c2c_rx_valid;
            logic               act_c2c_ack_valid;
            logic [4:0]         act_c2c_ack_seq;
            logic               act_c2c_nack_valid;
            logic [4:0]         act_c2c_nack_seq;
            logic               act_chip_sec_err;
            logic               act_chip_ded_err;
            logic               act_chip_busy;
            logic [31:0]        act_total_retired_insts;
            logic [31:0]        act_total_active_mac_cycles;
            logic [31:0]        act_total_gated_saved_cycles;
            logic [31:0]        act_total_mac_ops;
            logic [31:0]        act_union_barrier_cnt;
            logic [31:0]        act_routed_flit_cnt;
            logic [31:0]        act_c2c_crc_err_cnt;
            logic [31:0]        act_c2c_retransmit_cnt;
        
~001200     function new(string name = "mlu_chip_top_seq_item");
 001200       super.new(name);
            endfunction
          endclass : mlu_chip_top_seq_item
        
          // ---------------------------------------------------------------------------
          // 2. UVM Sequencer
          // ---------------------------------------------------------------------------
          typedef uvm_sequencer #(mlu_chip_top_seq_item) mlu_chip_top_sequencer;
        
          // ---------------------------------------------------------------------------
          // 3. UVM Sequence: mlu_chip_top_sequence (600 Cycles Full-Chip Verification)
          // ---------------------------------------------------------------------------
          class mlu_chip_top_sequence extends uvm_sequence #(mlu_chip_top_seq_item);
%000001     `uvm_object_utils(mlu_chip_top_sequence)
        
%000001     int unsigned num_cycles = 600;
        
%000001     function new(string name = "mlu_chip_top_sequence");
%000001       super.new(name);
            endfunction
        
%000001     task body();
~000600       for (int unsigned cyc = 0; cyc < num_cycles; cyc++) begin
 000600         mlu_chip_top_seq_item item = mlu_chip_top_seq_item::type_id::create("item");
 000600         start_item(item);
        
 000600         item.cycle_id           = cyc;
 000600         item.subtest_id         = (cyc < 80)  ? 0 : (cyc < 200) ? 1 : (cyc < 320) ? 2 :
                                          (cyc < 420) ? 3 : (cyc < 500) ? 4 : 5;
 000600         item.ipu_inst_valid     = 4'b0000;
 000600         item.ipu_inst           = '0;
 000600         item.mpu_cmd_valid      = 1'b0;
 000600         item.mpu_cmd_inst       = 128'd0;
 000600         item.union_task_mask    = 4'b1111;
 000600         item.wram_ping_pong_sel = (cyc >= 240 && cyc < 320);
 000600         item.mfu_idx_offset     = {16'd24, 16'd16, 16'd8, 16'd0};
 000600         item.mfu_decomp_bitmap  = 8'b1010_0101;
 000600         item.vfu_cos_sin_lut    = {4{16'h0080, 16'h00DF}};
 000600         item.noc_allreduce_en   = 1'b1;
 000600         item.ext_sram_valid     = 1'b0;
 000600         item.ext_sram_we        = 1'b0;
 000600         item.ext_sram_addr      = 11'd0;
 000600         item.ext_sram_wdata     = 64'd0;
 000600         item.c2c_err_inject_crc = 1'b0;
 000600         item.c2c_replay_trigger = 1'b0;
 000600         item.c2c_replay_seq     = 5'd0;
 000600         item.err_inject_bank    = 3'd0;
 000600         item.err_inject_mask    = 72'd0;
        
                // Phase 0 (0..79): Preload Shared SRAM & MPU 1-to-4 OP_MPU_BCAST_SRAM
 000016         if (cyc >= 2 && cyc < 18) begin
 000016           int idx = cyc - 2;
 000016           item.ext_sram_valid = 1'b1;
 000016           item.ext_sram_we    = 1'b1;
 000016           item.ext_sram_addr  = 11'(idx);
 000016           item.ext_sram_wdata = 64'((idx + 1) * 100);
%000004         end else if (cyc >= 18 && cyc < 22) begin
%000004           int idx = cyc - 18;
%000004           item.ext_sram_valid = 1'b1;
%000004           item.ext_sram_we    = 1'b1;
%000004           item.ext_sram_addr  = 11'(16 + idx);
%000004           item.ext_sram_wdata = 64'((idx + 5) * 10);
%000001         end else if (cyc == 25) begin
%000001           item.mpu_cmd_valid = 1'b1;
%000001           item.mpu_cmd_inst  = make_bang_inst(
%000001             OP_MPU_BCAST_SRAM, ENG_MPU_COL, PREC_FP16, SPARSE_DENSE,
%000001             MEM_SPACE_SRAM, MEM_SPACE_NRAM, 4'b0000, 8'hA1,
%000001             32'h0000_0000, 32'h0000_0000, 16'h0000, 16'd4
                  );
%000001         end else if (cyc == 40) begin
%000001           item.mpu_cmd_valid = 1'b1;
%000001           item.mpu_cmd_inst  = make_bang_inst(
%000001             OP_MPU_BCAST_SRAM, ENG_MPU_COL, PREC_INT8, SPARSE_DENSE,
%000001             MEM_SPACE_SRAM, MEM_SPACE_WRAM, 4'b0000, 8'hA2,
%000001             32'h0000_0020, 32'h0000_0020, 16'h0000, 16'd8
                  );
                end
        
                // Phase 1 (80..199): Concurrent 4-IPU MFU 1D/2D/Gather/Transpose/Decomp DMA over GDRAM
%000001         else if (cyc == 85) begin
%000001           item.ipu_inst_valid = 4'b1111;
%000001           item.ipu_inst[0] = make_bang_inst(OP_BANG_MEMCPY_1D,  ENG_MFU_DMA, PREC_INT8, SPARSE_DENSE,
%000001                                             MEM_SPACE_GDRAM, MEM_SPACE_NRAM, 4'b0000, 8'h10,
%000001                                             32'h0000_0000, 32'h0000_0000, 16'h0008, 16'h0004);
%000001           item.ipu_inst[1] = make_bang_inst(OP_BANG_MEMCPY_2D,  ENG_MFU_DMA, PREC_INT8, SPARSE_DENSE,
%000001                                             MEM_SPACE_GDRAM, MEM_SPACE_NRAM, 4'b0000, 8'h11,
%000001                                             32'h0000_0000, 32'h0000_0020, 16'h0010, 16'h0202);
%000001           item.ipu_inst[2] = make_bang_inst(OP_BANG_DECOMP_DMA, ENG_MFU_DMA, PREC_INT8, SPARSE_2_OF_4,
%000001                                             MEM_SPACE_GDRAM, MEM_SPACE_WRAM, 4'b0000, 8'h12,
%000001                                             32'h0000_0000, 32'h0000_0040, 16'h0008, 16'h0004);
%000001           item.ipu_inst[3] = make_bang_inst(OP_BANG_GATHER,     ENG_MFU_DMA, PREC_BF16, SPARSE_DENSE,
%000001                                             MEM_SPACE_GDRAM, MEM_SPACE_NRAM, 4'b0000, 8'h13,
%000001                                             32'h0000_0000, 32'h0000_0060, 16'h0008, 16'h0004);
%000001         end else if (cyc == 135) begin
%000001           item.ipu_inst_valid = 4'b1111;
%000001           item.ipu_inst[0] = make_bang_inst(OP_BANG_TRANSPOSE,  ENG_MFU_DMA, PREC_FP16, SPARSE_DENSE,
%000001                                             MEM_SPACE_GDRAM, MEM_SPACE_NRAM, 4'b0000, 8'h14,
%000001                                             32'h0000_0040, 32'h0000_0080, 16'h0008, 16'h0004);
%000001           item.ipu_inst[1] = make_bang_inst(OP_BANG_DECOMP_DMA, ENG_MFU_DMA, PREC_INT4, SPARSE_BLOCK_4X4,
%000001                                             MEM_SPACE_GDRAM, MEM_SPACE_NRAM, 4'b0000, 8'h15,
%000001                                             32'h0000_0040, 32'h0000_00A0, 16'h0008, 16'h0004);
%000001           item.ipu_inst[2] = make_bang_inst(OP_BANG_MEMCPY_2D,  ENG_MFU_DMA, PREC_FP16, SPARSE_DENSE,
%000001                                             MEM_SPACE_GDRAM, MEM_SPACE_NRAM, 4'b0000, 8'h16,
%000001                                             32'h0000_0040, 32'h0000_00C0, 16'h0010, 16'h0202);
%000001           item.ipu_inst[3] = make_bang_inst(OP_BANG_SCATTER,    ENG_MFU_DMA, PREC_FP16, SPARSE_DENSE,
%000001                                             MEM_SPACE_NRAM,  MEM_SPACE_GDRAM, 4'b0000, 8'h17,
%000001                                             32'h0000_0100, 32'h0000_0000, 16'h0008, 16'h0004);
                end
        
                // Phase 2 (200..319): Parallel 4-IPU TFU (MATMUL, SPARSE_MM, QUANT_MM)
%000001         else if (cyc == 205) begin
%000001           item.ipu_inst_valid = 4'b1111;
%000001           item.ipu_inst[0] = make_bang_inst(OP_BANG_MATMUL,    ENG_TFU_MAT, PREC_INT8, SPARSE_DENSE,
%000001                                             MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h20,
%000001                                             32'h0000_0100, 32'h0000_0000, 16'h0000, 16'h0004);
%000001           item.ipu_inst[1] = make_bang_inst(OP_BANG_SPARSE_MM, ENG_TFU_MAT, PREC_INT4, SPARSE_2_OF_4,
%000001                                             MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h21,
%000001                                             32'h0000_0100, 32'h0000_0000, 16'h0000, 16'h0004);
%000001           item.ipu_inst[2] = make_bang_inst(OP_BANG_QUANT_MM,  ENG_TFU_MAT, PREC_INT8, SPARSE_DENSE,
%000001                                             MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h22,
%000001                                             32'h0000_0100, 32'h0000_0000, 16'h0000, 16'h0004);
%000001           item.ipu_inst[3] = make_bang_inst(OP_BANG_MATMUL,    ENG_TFU_MAT, PREC_BF16, SPARSE_DENSE,
%000001                                             MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h23,
%000001                                             32'h0000_0100, 32'h0000_0000, 16'h0000, 16'h0004);
%000001         end else if (cyc == 255) begin
%000001           item.ipu_inst_valid = 4'b1111;
%000001           item.ipu_inst[0] = make_bang_inst(OP_BANG_SPARSE_MM, ENG_TFU_MAT, PREC_INT8, SPARSE_2_OF_4,
%000001                                             MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h24,
%000001                                             32'h0000_0140, 32'h0000_0000, 16'h0000, 16'h0004);
%000001           item.ipu_inst[1] = make_bang_inst(OP_BANG_QUANT_MM,  ENG_TFU_MAT, PREC_INT4, SPARSE_DENSE,
%000001                                             MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h25,
%000001                                             32'h0000_0140, 32'h0000_0000, 16'h0000, 16'h0004);
%000001           item.ipu_inst[2] = make_bang_inst(OP_BANG_MATMUL,    ENG_TFU_MAT, PREC_FP16, SPARSE_DENSE,
%000001                                             MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h26,
%000001                                             32'h0000_0140, 32'h0000_0000, 16'h0000, 16'h0004);
%000001           item.ipu_inst[3] = make_bang_inst(OP_BANG_SPARSE_MM, ENG_TFU_MAT, PREC_BF16, SPARSE_BLOCK_4X4,
%000001                                             MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h27,
%000001                                             32'h0000_0140, 32'h0000_0000, 16'h0000, 16'h0004);
                end
        
                // Phase 3 (320..419): Parallel 4-IPU VFU/SFU (ROPE, RMSNORM, SOFTMAX, SWIGLU)
%000001         else if (cyc == 325) begin
%000001           item.ipu_inst_valid = 4'b1111;
%000001           item.ipu_inst[0] = make_bang_inst(OP_BANG_ROPE,    ENG_VFU_VEC, PREC_FP16, SPARSE_DENSE,
%000001                                             MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h30,
%000001                                             32'h0000_0200, 32'h0000_0100, 16'h0000, 16'h0002);
%000001           item.ipu_inst[1] = make_bang_inst(OP_BANG_RMSNORM, ENG_VFU_VEC, PREC_FP16, SPARSE_DENSE,
%000001                                             MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h31,
%000001                                             32'h0000_0200, 32'h0000_0100, 16'h0000, 16'h0002);
%000001           item.ipu_inst[2] = make_bang_inst(OP_BANG_SOFTMAX, ENG_VFU_VEC, PREC_FP16, SPARSE_DENSE,
%000001                                             MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h32,
%000001                                             32'h0000_0200, 32'h0000_0100, 16'h0000, 16'h0002);
%000001           item.ipu_inst[3] = make_bang_inst(OP_BANG_SWIGLU,  ENG_VFU_VEC, PREC_FP16, SPARSE_DENSE,
%000001                                             MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h33,
%000001                                             32'h0000_0200, 32'h0000_0100, 16'h0000, 16'h0002);
%000001         end else if (cyc == 370) begin
%000001           item.ipu_inst_valid = 4'b1111;
%000001           item.ipu_inst[0] = make_bang_inst(OP_BANG_SWIGLU,  ENG_VFU_VEC, PREC_BF16, SPARSE_DENSE,
%000001                                             MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h34,
%000001                                             32'h0000_0240, 32'h0000_0100, 16'h0000, 16'h0002);
%000001           item.ipu_inst[1] = make_bang_inst(OP_BANG_SOFTMAX, ENG_VFU_VEC, PREC_BF16, SPARSE_DENSE,
%000001                                             MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h35,
%000001                                             32'h0000_0240, 32'h0000_0100, 16'h0000, 16'h0002);
%000001           item.ipu_inst[2] = make_bang_inst(OP_BANG_RMSNORM, ENG_VFU_VEC, PREC_BF16, SPARSE_DENSE,
%000001                                             MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h36,
%000001                                             32'h0000_0240, 32'h0000_0100, 16'h0000, 16'h0002);
%000001           item.ipu_inst[3] = make_bang_inst(OP_BANG_ROPE,    ENG_VFU_VEC, PREC_BF16, SPARSE_DENSE,
%000001                                             MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h37,
%000001                                             32'h0000_0240, 32'h0000_0100, 16'h0000, 16'h0002);
                end
        
                // Phase 4 (420..499): Union-Task Barriers & OP_MPU_ALLREDUCE via NoC + C2C SerDes
%000001         else if (cyc == 425) begin
%000001           item.ipu_inst_valid = 4'b0111; // IPU 0..2 arrive first
%000003           for (int i = 0; i < 3; i++) begin
%000003             item.ipu_inst[i] = make_bang_inst(OP_SYNC_CLUSTER, ENG_ICU_CTRL, PREC_FP16, SPARSE_DENSE,
%000003                                               MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'(8'h40 + i),
%000003                                               32'd0, 32'd0, 16'd0, 16'd0);
                  end
%000001         end else if (cyc == 430) begin
%000001           item.ipu_inst_valid = 4'b1000; // IPU 3 arrives -> barrier #1 completes
%000001           item.ipu_inst[3]    = make_bang_inst(OP_SYNC_CLUSTER, ENG_ICU_CTRL, PREC_FP16, SPARSE_DENSE,
%000001                                                MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h43,
%000001                                                32'd0, 32'd0, 16'd0, 16'd0);
%000001         end else if (cyc == 460) begin
                  // OP_MPU_ALLREDUCE: read src0_addr=0 (words 0..3: 100..400), accumulate into dst_addr=0x80 (words 16..19: 50..80)
%000001           item.mpu_cmd_valid = 1'b1;
%000001           item.mpu_cmd_inst  = make_bang_inst(
%000001             OP_MPU_ALLREDUCE, ENG_MPU_COL, PREC_FP16, SPARSE_DENSE,
%000001             MEM_SPACE_SRAM, MEM_SPACE_MLULK, 4'b0000, 8'hB1,
%000001             32'h0000_0080, 32'h0000_0000, 16'h000C, 16'd4
                  );
%000004         end else if (cyc >= 485 && cyc < 489) begin
                  // Read back Shared SRAM words 16..19 to verify in-SRAM atomic AllReduce result
%000004           item.ext_sram_valid = 1'b1;
%000004           item.ext_sram_we    = 1'b0;
%000004           item.ext_sram_addr  = 11'(16 + (cyc - 485));
                end
        
                // Phase 5 (500..599): C2C CRC-16 Fault Injection + Go-Back-N Replay + SECDED ECC
%000001         else if (cyc == 505) begin
%000001           item.mpu_cmd_valid = 1'b1;
%000001           item.mpu_cmd_inst  = make_bang_inst(
%000001             OP_MPU_ALLREDUCE, ENG_MPU_COL, PREC_FP16, SPARSE_DENSE,
%000001             MEM_SPACE_SRAM, MEM_SPACE_MLULK, 4'b0000, 8'hB2,
%000001             32'h0000_00A0, 32'h0000_0000, 16'h000C, 16'd1
                  );
%000005         end else if (cyc >= 510 && cyc <= 514) begin
%000005           item.c2c_err_inject_crc = 1'b1; // Corrupt incoming seq=4 flit -> NACK
%000001         end else if (cyc == 518) begin
%000001           item.c2c_replay_trigger = 1'b1; // Trigger Go-Back-N replay from seq=4
%000001           item.c2c_replay_seq     = 5'd4;
%000001         end else if (cyc == 530) begin
%000001           item.ipu_inst_valid = 4'b0001;
%000001           item.ipu_inst[0]    = make_bang_inst(OP_BANG_MATMUL, ENG_TFU_MAT, PREC_INT8, SPARSE_DENSE,
%000001                                                MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h50,
%000001                                                32'h0000_0200, 32'h0000_0000, 16'h0000, 16'h0004);
%000002         end else if (cyc == 531 || cyc == 532) begin
%000002           item.err_inject_bank = 3'd0;
%000002           item.err_inject_mask = 72'h00_0000_0000_0000_0001; // 1-bit SEC
%000002         end else if (cyc == 533 || cyc == 534) begin
%000002           item.err_inject_bank = 3'd0;
%000002           item.err_inject_mask = 72'h00_0000_0000_0000_0003; // 2-bit DED
~000552         end else if (cyc == 555) begin
%000001           item.ipu_inst_valid = 4'b1111; // All 4 IPUs simultaneous barrier #2
%000004           for (int i = 0; i < 4; i++) begin
%000004             item.ipu_inst[i] = make_bang_inst(OP_SYNC_CLUSTER, ENG_ICU_CTRL, PREC_FP16, SPARSE_DENSE,
%000004                                               MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'(8'h60 + i),
%000004                                               32'd0, 32'd0, 16'd0, 16'd0);
                  end
                end
        
 000600         finish_item(item);
              end
            endtask
          endclass : mlu_chip_top_sequence
        
          // ---------------------------------------------------------------------------
          // 4. UVM Driver: mlu_chip_top_driver
          // ---------------------------------------------------------------------------
          class mlu_chip_top_driver extends uvm_driver #(mlu_chip_top_seq_item);
%000001     `uvm_component_utils(mlu_chip_top_driver)
        
            virtual mlu_chip_top_if vif;
%000001     int unsigned driven = 0;
        
%000001     function new(string name = "mlu_chip_top_driver", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       if (!uvm_config_db#(virtual mlu_chip_top_if)::get(this, "", "vif", vif)) begin
%000000         `uvm_fatal("NO_VIF", "Virtual interface mlu_chip_top_if missing in mlu_chip_top_driver")
              end
            endfunction
        
%000000     task run_phase(uvm_phase phase);
%000000       mlu_chip_top_seq_item item;
%000000       vif.rst_n              = 1'b0;
%000000       vif.cycle_valid        = 1'b0;
%000000       vif.ipu_inst_valid     = 4'b0000;
%000000       vif.ipu_inst           = '0;
%000000       vif.mpu_cmd_valid      = 1'b0;
%000000       vif.mpu_cmd_inst       = 128'd0;
%000000       vif.union_task_mask    = 4'b1111;
%000000       vif.wram_ping_pong_sel = 1'b0;
%000000       vif.noc_allreduce_en   = 1'b1;
%000000       vif.ext_sram_valid     = 1'b0;
%000000       vif.c2c_err_inject_crc = 1'b0;
%000000       vif.c2c_replay_trigger = 1'b0;
%000000       vif.c2c_replay_seq     = 5'd0;
%000000       vif.err_inject_bank    = 3'd0;
%000000       vif.err_inject_mask    = 72'd0;
        
%000003       repeat (3) @(posedge vif.clk);
%000000       @(negedge vif.clk);
%000000       vif.rst_n = 1'b1;
        
 000600       forever begin
 000600         seq_item_port.get_next_item(item);
 000600         vif.cycle_id           = item.cycle_id;
 000600         vif.subtest_id         = item.subtest_id;
 000600         vif.ipu_inst_valid     = item.ipu_inst_valid;
 000600         vif.ipu_inst           = item.ipu_inst;
 000600         vif.mpu_cmd_valid      = item.mpu_cmd_valid;
 000600         vif.mpu_cmd_inst       = item.mpu_cmd_inst;
 000600         vif.union_task_mask    = item.union_task_mask;
 000600         vif.wram_ping_pong_sel = item.wram_ping_pong_sel;
 000600         vif.mfu_idx_offset     = item.mfu_idx_offset;
 000600         vif.mfu_decomp_bitmap  = item.mfu_decomp_bitmap;
 000600         vif.vfu_cos_sin_lut    = item.vfu_cos_sin_lut;
 000600         vif.noc_allreduce_en   = item.noc_allreduce_en;
 000600         vif.ext_sram_valid     = item.ext_sram_valid;
 000600         vif.ext_sram_we        = item.ext_sram_we;
 000600         vif.ext_sram_addr      = item.ext_sram_addr;
 000600         vif.ext_sram_wdata     = item.ext_sram_wdata;
 000600         vif.c2c_err_inject_crc = item.c2c_err_inject_crc;
 000600         vif.c2c_replay_trigger = item.c2c_replay_trigger;
 000600         vif.c2c_replay_seq     = item.c2c_replay_seq;
 000600         vif.err_inject_bank    = item.err_inject_bank;
 000600         vif.err_inject_mask    = item.err_inject_mask;
        
 000600         vif.cycle_valid = 1'b1;
 000600         @(posedge vif.clk);
 000600         #1ns;
 000600         vif.cycle_valid = 1'b0;
 000600         driven++;
 000600         @(negedge vif.clk);
 000600         seq_item_port.item_done();
              end
            endtask
          endclass : mlu_chip_top_driver
        
          // ---------------------------------------------------------------------------
          // 5. UVM Monitor: mlu_chip_top_monitor (with Functional Covergroup)
          // ---------------------------------------------------------------------------
          class mlu_chip_top_monitor extends uvm_monitor;
%000001     `uvm_component_utils(mlu_chip_top_monitor)
        
            virtual mlu_chip_top_if vif;
            uvm_analysis_port #(mlu_chip_top_seq_item) ap;
%000001     int unsigned seen = 0;
        
            covergroup mlu_chip_top_cg with function sample(
              int unsigned subtest,
              bit          mpu_done,
              bit          gdram_req,
              bit          c2c_tx,
              bit          c2c_ack,
              bit          c2c_nack,
              bit          sec_err,
              bit          ded_err,
              bit          barrier_hit
            );
              option.per_instance = 1;
              cp_subtest: coverpoint subtest {
 000080         bins st_bcast     = {0};
 000120         bins st_mfu_gdram = {1};
 000120         bins st_tfu_4ipu  = {2};
 000100         bins st_vfu_4ipu  = {3};
 000080         bins st_sync_allr = {4};
 000100         bins st_c2c_ecc   = {5};
              }
~000596       cp_mpu_done: coverpoint mpu_done    { bins b0 = {0}; bins b1 = {1}; }
 000588       cp_gdram:    coverpoint gdram_req   { bins b0 = {0}; bins b1 = {1}; }
~000594       cp_c2c_tx:   coverpoint c2c_tx      { bins b0 = {0}; bins b1 = {1}; }
~000595       cp_c2c_ack:  coverpoint c2c_ack     { bins b0 = {0}; bins b1 = {1}; }
~000599       cp_c2c_nack: coverpoint c2c_nack    { bins b0 = {0}; bins b1 = {1}; }
~000599       cp_sec:      coverpoint sec_err     { bins b0 = {0}; bins b1 = {1}; }
~000598       cp_ded:      coverpoint ded_err     { bins b0 = {0}; bins b1 = {1}; }
 000556       cp_barrier:  coverpoint barrier_hit { bins b0 = {0}; bins b1 = {1}; }
            endgroup
        
%000001     function new(string name = "mlu_chip_top_monitor", uvm_component parent = null);
%000001       super.new(name, parent);
%000001       ap = new("ap", this);
%000001       mlu_chip_top_cg = new();
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       if (!uvm_config_db#(virtual mlu_chip_top_if)::get(this, "", "vif", vif)) begin
%000000         `uvm_fatal("NO_VIF", "Virtual interface mlu_chip_top_if missing in mlu_chip_top_monitor")
              end
            endfunction
        
%000000     task run_phase(uvm_phase phase);
 000602       forever begin
 000602         @(negedge vif.clk);
 000602         #1ns;
~000600         if (vif.rst_n && vif.cycle_valid) begin
 000600           mlu_chip_top_seq_item item = mlu_chip_top_seq_item::type_id::create("obs_item");
 000600           item.cycle_id                     = vif.cycle_id;
 000600           item.subtest_id                   = vif.subtest_id;
 000600           item.ipu_inst_valid               = vif.ipu_inst_valid;
 000600           item.ipu_inst                     = vif.ipu_inst;
 000600           item.mpu_cmd_valid                = vif.mpu_cmd_valid;
 000600           item.mpu_cmd_inst                 = vif.mpu_cmd_inst;
 000600           item.union_task_mask              = vif.union_task_mask;
 000600           item.wram_ping_pong_sel           = vif.wram_ping_pong_sel;
 000600           item.ext_sram_valid               = vif.ext_sram_valid;
 000600           item.ext_sram_we                  = vif.ext_sram_we;
 000600           item.ext_sram_addr                = vif.ext_sram_addr;
 000600           item.ext_sram_wdata               = vif.ext_sram_wdata;
 000600           item.c2c_err_inject_crc           = vif.c2c_err_inject_crc;
 000600           item.c2c_replay_trigger           = vif.c2c_replay_trigger;
 000600           item.c2c_replay_seq               = vif.c2c_replay_seq;
 000600           item.err_inject_bank              = vif.err_inject_bank;
 000600           item.err_inject_mask              = vif.err_inject_mask;
        
 000600           item.act_ipu_inst_ready           = vif.ipu_inst_ready;
 000600           item.act_mpu_cmd_ready            = vif.mpu_cmd_ready;
 000600           item.act_mpu_done_valid           = vif.mpu_done_valid;
 000600           item.act_mpu_done_tag             = vif.mpu_done_tag;
 000600           item.act_ext_sram_grant           = vif.ext_sram_grant;
 000600           item.act_ext_sram_rdata           = vif.ext_sram_rdata;
 000600           item.act_ext_sram_rvalid          = vif.ext_sram_rvalid;
 000600           item.act_gdram_req_valid          = vif.gdram_req_valid;
 000600           item.act_gdram_req_we             = vif.gdram_req_we;
 000600           item.act_gdram_req_addr           = vif.gdram_req_addr;
 000600           item.act_gdram_resp_valid         = vif.gdram_resp_valid;
 000600           item.act_gdram_resp_rdata         = vif.gdram_resp_rdata;
 000600           item.act_c2c_tx_valid             = vif.c2c_tx_valid;
 000600           item.act_c2c_tx_flit              = vif.c2c_tx_flit;
 000600           item.act_c2c_rx_valid             = vif.c2c_rx_valid;
 000600           item.act_c2c_ack_valid            = vif.c2c_ack_valid;
 000600           item.act_c2c_ack_seq              = vif.c2c_ack_seq;
 000600           item.act_c2c_nack_valid           = vif.c2c_nack_valid;
 000600           item.act_c2c_nack_seq             = vif.c2c_nack_seq;
 000600           item.act_chip_sec_err             = vif.chip_sec_err;
 000600           item.act_chip_ded_err             = vif.chip_ded_err;
 000600           item.act_chip_busy                = vif.chip_busy;
 000600           item.act_total_retired_insts      = vif.total_retired_insts;
 000600           item.act_total_active_mac_cycles  = vif.total_active_mac_cycles;
 000600           item.act_total_gated_saved_cycles = vif.total_gated_saved_cycles;
 000600           item.act_total_mac_ops            = vif.total_mac_ops;
 000600           item.act_union_barrier_cnt        = vif.union_barrier_cnt;
 000600           item.act_routed_flit_cnt          = vif.routed_flit_cnt;
 000600           item.act_c2c_crc_err_cnt          = vif.c2c_crc_err_cnt;
 000600           item.act_c2c_retransmit_cnt       = vif.c2c_retransmit_cnt;
        
 000600           mlu_chip_top_cg.sample(
 000600             vif.subtest_id,
 000600             vif.mpu_done_valid,
 000600             vif.gdram_req_valid,
 000600             vif.c2c_tx_valid,
 000600             vif.c2c_ack_valid,
 000600             vif.c2c_nack_valid,
 000600             vif.chip_sec_err,
 000600             vif.chip_ded_err,
 000600             (vif.union_barrier_cnt > 0)
                  );
        
 000600           seen++;
 000600           ap.write(item);
                end
              end
            endtask
          endclass : mlu_chip_top_monitor
        
          // ---------------------------------------------------------------------------
          // 6. UVM Agent: mlu_chip_top_agent
          // ---------------------------------------------------------------------------
          class mlu_chip_top_agent extends uvm_agent;
%000001     `uvm_component_utils(mlu_chip_top_agent)
            mlu_chip_top_sequencer sequencer;
            mlu_chip_top_driver    driver;
            mlu_chip_top_monitor   monitor;
        
%000001     function new(string name = "mlu_chip_top_agent", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       sequencer = mlu_chip_top_sequencer::type_id::create("sequencer", this);
%000001       driver    = mlu_chip_top_driver::type_id::create("driver", this);
%000001       monitor   = mlu_chip_top_monitor::type_id::create("monitor", this);
            endfunction
        
%000001     function void connect_phase(uvm_phase phase);
%000001       super.connect_phase(phase);
%000001       driver.seq_item_port.connect(sequencer.seq_item_export);
            endfunction
          endclass : mlu_chip_top_agent
        
          // ---------------------------------------------------------------------------
          // 7. UVM Scoreboard: mlu_chip_top_scoreboard (with DPI-C Golden Checks)
          // ---------------------------------------------------------------------------
          class mlu_chip_top_scoreboard extends uvm_scoreboard;
%000001     `uvm_component_utils(mlu_chip_top_scoreboard)
        
            uvm_analysis_imp #(mlu_chip_top_seq_item, mlu_chip_top_scoreboard) analysis_export;
        
%000001     int unsigned checked_cycles       = 0;
%000001     int unsigned mismatches           = 0;
%000001     int unsigned mpu_bcast_done_cnt   = 0;
%000001     int unsigned mpu_allred_done_cnt  = 0;
%000001     int unsigned gdram_arb_reqs       = 0;
%000001     int unsigned gdram_resp_beats     = 0;
%000001     int unsigned c2c_tx_flits         = 0;
%000001     int unsigned c2c_crc_checks       = 0;
%000001     int unsigned c2c_ack_hits         = 0;
%000001     int unsigned c2c_nack_hits        = 0;
%000001     int unsigned allred_sram_checks   = 0;
%000001     int unsigned sec_err_hits         = 0;
%000001     int unsigned ded_err_hits         = 0;
%000001     int unsigned max_barriers         = 0;
%000001     int unsigned max_retired_insts    = 0;
%000001     int unsigned max_active_mac_cycs  = 0;
%000001     int unsigned max_gated_saved_cycs = 0;
%000001     int unsigned max_total_mac_ops    = 0;
%000001     int unsigned max_routed_flits     = 0;
%000001     int unsigned max_c2c_crc_errs     = 0;
%000001     int unsigned max_c2c_retransmits  = 0;
        
%000001     function new(string name = "mlu_chip_top_scoreboard", uvm_component parent = null);
%000001       super.new(name, parent);
%000001       analysis_export = new("analysis_export", this);
            endfunction
        
 000600     function void write(mlu_chip_top_seq_item item);
 000600       checked_cycles++;
        
~000596       if (item.act_mpu_done_valid) begin
%000002         if (item.act_mpu_done_tag == 8'hA1 || item.act_mpu_done_tag == 8'hA2)
%000002           mpu_bcast_done_cnt++;
%000002         else if (item.act_mpu_done_tag == 8'hB1 || item.act_mpu_done_tag == 8'hB2)
%000002           mpu_allred_done_cnt++;
              end
        
 000588       if (item.act_gdram_req_valid)  gdram_arb_reqs++;
~000592       if (item.act_gdram_resp_valid) gdram_resp_beats++;
~000595       if (item.act_c2c_ack_valid)    c2c_ack_hits++;
~000599       if (item.act_c2c_nack_valid)   c2c_nack_hits++;
~000599       if (item.act_chip_sec_err)     sec_err_hits++;
~000598       if (item.act_chip_ded_err)     ded_err_hits++;
        
~000599       if (item.act_union_barrier_cnt > max_barriers)
%000001         max_barriers = item.act_union_barrier_cnt;
~000593       if (item.act_total_retired_insts > max_retired_insts)
%000007         max_retired_insts = item.act_total_retired_insts;
 000585       if (item.act_total_active_mac_cycles > max_active_mac_cycs)
 000015         max_active_mac_cycs = item.act_total_active_mac_cycles;
~000591       if (item.act_total_gated_saved_cycles > max_gated_saved_cycs)
 000591         max_gated_saved_cycs = item.act_total_gated_saved_cycles;
 000588       if (item.act_total_mac_ops > max_total_mac_ops)
 000012         max_total_mac_ops = item.act_total_mac_ops;
 000590       if (item.act_routed_flit_cnt > max_routed_flits)
 000010         max_routed_flits = item.act_routed_flit_cnt;
~000599       if (item.act_c2c_crc_err_cnt > max_c2c_crc_errs)
%000001         max_c2c_crc_errs = item.act_c2c_crc_err_cnt;
~000599       if (item.act_c2c_retransmit_cnt > max_c2c_retransmits)
%000001         max_c2c_retransmits = item.act_c2c_retransmit_cnt;
        
              // Verify C2C SerDes Outgoing Flit CRC-16-CCITT against C++17 DPI-C Reference Model
~000594       if (item.act_c2c_tx_valid) begin
%000006         int unsigned exp_crc = dpi_chip_top_ref_crc16(
%000006           item.act_c2c_tx_flit[127:64],
%000006           item.act_c2c_tx_flit[63:0]
                );
%000006         c2c_tx_flits++;
%000006         if (item.act_c2c_tx_flit[111:96] !== exp_crc[15:0]) begin
                  `uvm_error("CHIP_TOP_CRC16_MISMATCH", $sformatf(
%000000             "Cyc %0d: act_crc=0x%04x exp_crc=0x%04x", item.cycle_id, item.act_c2c_tx_flit[111:96], exp_crc[15:0]))
%000000           mismatches++;
%000006         end else begin
%000006           c2c_crc_checks++;
                end
              end
        
              // Verify In-SRAM Atomic AllReduce against C++17 DPI-C Reference Model
~000596       if (item.cycle_id >= 486 && item.cycle_id < 490 && item.act_ext_sram_rvalid) begin
%000004         int idx = item.cycle_id - 486;
%000004         longint unsigned exp_val = dpi_chip_top_ref_allreduce(
%000004           64'((idx + 5) * 10),
%000004           64'((idx + 1) * 100)
                );
%000004         if (item.act_ext_sram_rdata !== exp_val) begin
                  `uvm_error("CHIP_TOP_ALLRED_MISMATCH", $sformatf(
%000000             "Cyc %0d idx=%0d: act=%0d exp=%0d", item.cycle_id, idx, item.act_ext_sram_rdata, exp_val))
%000000           mismatches++;
%000004         end else begin
%000004           allred_sram_checks++;
                end
              end
            endfunction
          endclass : mlu_chip_top_scoreboard
        
          // ---------------------------------------------------------------------------
          // 8. UVM Environment & Test
          // ---------------------------------------------------------------------------
          class mlu_chip_top_env extends uvm_env;
%000001     `uvm_component_utils(mlu_chip_top_env)
            mlu_chip_top_agent      agent;
            mlu_chip_top_scoreboard scoreboard;
        
%000001     function new(string name = "mlu_chip_top_env", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       agent      = mlu_chip_top_agent::type_id::create("agent", this);
%000001       scoreboard = mlu_chip_top_scoreboard::type_id::create("scoreboard", this);
            endfunction
        
%000001     function void connect_phase(uvm_phase phase);
%000001       super.connect_phase(phase);
%000001       agent.monitor.ap.connect(scoreboard.analysis_export);
            endfunction
          endclass : mlu_chip_top_env
        
          class mlu_chip_top_test extends uvm_test;
%000002     `uvm_component_utils(mlu_chip_top_test)
            mlu_chip_top_env env;
        
%000001     function new(string name = "mlu_chip_top_test", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       env = mlu_chip_top_env::type_id::create("env", this);
            endfunction
        
%000001     task run_phase(uvm_phase phase);
%000001       mlu_chip_top_sequence seq = mlu_chip_top_sequence::type_id::create("seq");
%000001       phase.raise_objection(this);
%000001       seq.start(env.agent.sequencer);
%000001       phase.drop_objection(this);
            endtask
        
%000001     function void report_phase(uvm_phase phase);
%000001       real func_cov = env.agent.monitor.mlu_chip_top_cg.get_inst_coverage();
              bit pass_gate = (env.agent.driver.driven == 600) &&
                              (env.scoreboard.checked_cycles == 600) &&
                              (env.scoreboard.mismatches == 0) &&
                              (env.scoreboard.mpu_bcast_done_cnt >= 2) &&
                              (env.scoreboard.mpu_allred_done_cnt >= 2) &&
                              (env.scoreboard.gdram_arb_reqs >= 10) &&
                              (env.scoreboard.gdram_resp_beats >= 6) &&
                              (env.scoreboard.c2c_crc_checks >= 5) &&
                              (env.scoreboard.allred_sram_checks == 4) &&
                              (env.scoreboard.c2c_ack_hits >= 5) &&
                              (env.scoreboard.c2c_nack_hits >= 1) &&
                              (env.scoreboard.max_routed_flits >= 8) &&
                              (env.scoreboard.max_c2c_crc_errs >= 1) &&
                              (env.scoreboard.max_c2c_retransmits >= 1) &&
                              (env.scoreboard.max_barriers >= 1) &&
                              (env.scoreboard.max_retired_insts >= 25) &&
                              (env.scoreboard.max_active_mac_cycs >= 20) &&
                              (env.scoreboard.max_gated_saved_cycs >= 100) &&
                              (env.scoreboard.max_total_mac_ops >= 1000) &&
%000001                       (env.scoreboard.sec_err_hits > 0) &&
                              (env.scoreboard.ded_err_hits > 0);
%000001       super.report_phase(phase);
%000001       dpi_chip_top_set_status(pass_gate ? 0 : 1);
%000001       if (!pass_gate) begin
                `uvm_fatal("UVM_CHIP_TOP_FAIL", $sformatf(
                  "Suite 8 gate failed: mismatches=%0d bcast=%0d allred=%0d gdram=%0d sram_chk=%0d crc_chk=%0d ack=%0d nack=%0d routed=%0d crc_err=%0d retx=%0d bar=%0d ret=%0d mac_ops=%0d sec=%0d ded=%0d cov=%0.2f%%",
                  env.scoreboard.mismatches, env.scoreboard.mpu_bcast_done_cnt,
                  env.scoreboard.mpu_allred_done_cnt, env.scoreboard.gdram_arb_reqs,
                  env.scoreboard.allred_sram_checks, env.scoreboard.c2c_crc_checks,
                  env.scoreboard.c2c_ack_hits, env.scoreboard.c2c_nack_hits,
                  env.scoreboard.max_routed_flits, env.scoreboard.max_c2c_crc_errs,
                  env.scoreboard.max_c2c_retransmits, env.scoreboard.max_barriers,
                  env.scoreboard.max_retired_insts, env.scoreboard.max_total_mac_ops,
%000000           env.scoreboard.sec_err_hits, env.scoreboard.ded_err_hits, func_cov))
%000001       end else begin
                `uvm_info("UVM_CHIP_TOP_PASS", $sformatf(
                  "SUITE 8 PASS: cycles=%0d dpi_calls=%0d bcast=%0d allred=%0d sram_chk=%0d crc_chk=%0d routed=%0d crc_err=%0d retx=%0d barriers=%0d retired=%0d mac_ops=%0d gated_cycs=%0d sec=%0d ded=%0d cov=%0.2f%%",
                  env.scoreboard.checked_cycles, dpi_chip_top_get_calls(),
                  env.scoreboard.mpu_bcast_done_cnt, env.scoreboard.mpu_allred_done_cnt,
                  env.scoreboard.allred_sram_checks, env.scoreboard.c2c_crc_checks,
                  env.scoreboard.max_routed_flits, env.scoreboard.max_c2c_crc_errs,
                  env.scoreboard.max_c2c_retransmits, env.scoreboard.max_barriers,
                  env.scoreboard.max_retired_insts, env.scoreboard.max_total_mac_ops,
                  env.scoreboard.max_gated_saved_cycs, env.scoreboard.sec_err_hits,
%000001           env.scoreboard.ded_err_hits, func_cov), UVM_LOW)
              end
            endfunction
          endclass : mlu_chip_top_test
        
        endpackage : mlu_chip_top_uvm_pkg
        
        `endif // MLU_CHIP_TOP_UVM_PKG_SV
        
