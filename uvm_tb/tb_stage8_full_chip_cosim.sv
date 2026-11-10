// =============================================================================
// File: uvm_tb/tb_stage8_full_chip_cosim.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Stage 8 Full-Chip End-to-End BANG C Union-Task Co-Simulation
//              Testbench exercising mlu_chip_top (4x IPU + 1x MPU + NoC Router
//              + C2C SerDes PCS):
//              1. Host Shared SRAM Preload + OP_MPU_BCAST_SRAM (1-to-4 Broadcast)
//                 + 4-IPU MFU 2D Strided & Zero-Bitmap Decompression DMA
//              2. 4-IPU Cooperative TFU Multi-Precision (INT8/INT4/BF16),
//                 Cambricon-S 2:4 Sparse MatMul, & Cambricon-Q Quantized MatMul
//              3. 4-IPU VFU/SFU Pipeline (RoPE, RMSNorm, Online Softmax, SwiGLU)
//              4. Hardware Union-Task Sync Barrier (OP_SYNC_CLUSTER),
//                 In-SRAM AllReduce + MLU-Link C2C SerDes CRC-16 & Replay + ECC
// =============================================================================
`include "mlu_pkg.sv"

module tb_stage8_full_chip_cosim (
  input  logic clk,
  input  logic rst_n
);
  import mlu_pkg::*;

  localparam int unsigned NUM_IPUS = 4;

  // DUT Top-Level Signals
  logic [NUM_IPUS-1:0]        ipu_inst_valid;
  logic [NUM_IPUS-1:0]        ipu_inst_ready;
  logic [NUM_IPUS-1:0][127:0] ipu_inst;

  logic                       mpu_cmd_valid;
  logic                       mpu_cmd_ready;
  logic [127:0]               mpu_cmd_inst;
  logic                       mpu_done_valid;
  logic [7:0]                 mpu_done_tag;

  logic [NUM_IPUS-1:0]        union_task_mask;
  logic                       wram_ping_pong_sel;
  logic [63:0]                mfu_idx_offset;
  logic [7:0]                 mfu_decomp_bitmap;
  logic [127:0]               vfu_cos_sin_lut;
  logic                       noc_allreduce_en;

  logic                       ext_sram_valid;
  logic                       ext_sram_we;
  logic [10:0]                ext_sram_addr;
  logic [63:0]                ext_sram_wdata;
  logic                       ext_sram_grant;
  logic [63:0]                ext_sram_rdata;
  logic                       ext_sram_rvalid;

  logic                       gdram_req_valid;
  logic                       gdram_req_we;
  logic [31:0]                gdram_req_addr;
  logic [63:0]                gdram_req_wdata;
  logic                       gdram_resp_valid;
  logic [63:0]                gdram_resp_rdata;

  logic                       c2c_tx_valid;
  logic [127:0]               c2c_tx_flit;
  logic                       c2c_rx_valid;
  logic [127:0]               c2c_rx_flit;
  logic                       c2c_err_inject_crc;
  logic                       c2c_ack_valid;
  logic [4:0]                 c2c_ack_seq;
  logic                       c2c_nack_valid;
  logic [4:0]                 c2c_nack_seq;
  logic                       c2c_replay_trigger;
  logic [4:0]                 c2c_replay_seq;

  logic [2:0]                 err_inject_bank;
  logic [71:0]                err_inject_mask;
  logic                       chip_sec_err;
  logic                       chip_ded_err;
  logic                       chip_busy;

  logic [31:0]                total_retired_insts;
  logic [31:0]                total_active_mac_cycles;
  logic [31:0]                total_gated_saved_cycles;
  logic [31:0]                total_mac_ops;
  logic [31:0]                union_barrier_cnt;
  logic [31:0]                routed_flit_cnt;
  logic [31:0]                c2c_crc_err_cnt;
  logic [31:0]                c2c_retransmit_cnt;
  // ---------------------------------------------------------------------------
  // 1. Instantiate Full-Chip Top-Level DUT (mlu_chip_top)
  // ---------------------------------------------------------------------------
  mlu_chip_top #(
    .CHIP_CLUSTER_ID (4'd0),
    .NUM_IPUS        (NUM_IPUS)
  ) u_dut (
    .clk_i                     (clk),
    .rst_ni                    (rst_n),
    .ipu_inst_valid_i          (ipu_inst_valid),
    .ipu_inst_ready_o          (ipu_inst_ready),
    .ipu_inst_i                (ipu_inst),
    .mpu_cmd_valid_i           (mpu_cmd_valid),
    .mpu_cmd_ready_o           (mpu_cmd_ready),
    .mpu_cmd_inst_i            (mpu_cmd_inst),
    .mpu_done_valid_o          (mpu_done_valid),
    .mpu_done_tag_o            (mpu_done_tag),
    .union_task_mask_i         (union_task_mask),
    .wram_ping_pong_sel_i      (wram_ping_pong_sel),
    .mfu_idx_offset_i          (mfu_idx_offset),
    .mfu_decomp_bitmap_i       (mfu_decomp_bitmap),
    .vfu_cos_sin_lut_i         (vfu_cos_sin_lut),
    .noc_allreduce_en_i        (noc_allreduce_en),
    .ext_sram_valid_i          (ext_sram_valid),
    .ext_sram_we_i             (ext_sram_we),
    .ext_sram_addr_i           (ext_sram_addr),
    .ext_sram_wdata_i          (ext_sram_wdata),
    .ext_sram_grant_o          (ext_sram_grant),
    .ext_sram_rdata_o          (ext_sram_rdata),
    .ext_sram_rvalid_o         (ext_sram_rvalid),
    .gdram_req_valid_o         (gdram_req_valid),
    .gdram_req_we_o            (gdram_req_we),
    .gdram_req_addr_o          (gdram_req_addr),
    .gdram_req_wdata_o         (gdram_req_wdata),
    .gdram_resp_valid_i        (gdram_resp_valid),
    .gdram_resp_rdata_i        (gdram_resp_rdata),
    .c2c_tx_valid_o            (c2c_tx_valid),
    .c2c_tx_flit_o             (c2c_tx_flit),
    .c2c_rx_valid_i            (c2c_rx_valid),
    .c2c_rx_flit_i             (c2c_rx_flit),
    .c2c_err_inject_crc_i      (c2c_err_inject_crc),
    .c2c_ack_valid_o           (c2c_ack_valid),
    .c2c_ack_seq_o             (c2c_ack_seq),
    .c2c_nack_valid_o          (c2c_nack_valid),
    .c2c_nack_seq_o            (c2c_nack_seq),
    .c2c_replay_trigger_i      (c2c_replay_trigger),
    .c2c_replay_seq_i          (c2c_replay_seq),
    .err_inject_bank_i         (err_inject_bank),
    .err_inject_mask_i         (err_inject_mask),
    .chip_sec_err_o            (chip_sec_err),
    .chip_ded_err_o            (chip_ded_err),
    .chip_busy_o               (chip_busy),
    .total_retired_insts_o     (total_retired_insts),
    .total_active_mac_cycles_o (total_active_mac_cycles),
    .total_gated_saved_cycles_o(total_gated_saved_cycles),
    .total_mac_ops_o           (total_mac_ops),
    .union_barrier_cnt_o       (union_barrier_cnt),
    .routed_flit_cnt_o         (routed_flit_cnt),
    .c2c_crc_err_cnt_o         (c2c_crc_err_cnt),
    .c2c_retransmit_cnt_o      (c2c_retransmit_cnt)
  );

  // ---------------------------------------------------------------------------
  // 2. Behavioral HBM2e/HBM3e GDRAM Memory & C2C Loopback Channel
  // ---------------------------------------------------------------------------
  logic [63:0] gdram_mem [0:255];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      gdram_resp_valid <= 1'b0;
      gdram_resp_rdata <= 64'd0;
      for (int i = 0; i < 256; i++) begin
        gdram_mem[i] <= {16'(i + 1), 16'(i + 2), 16'(i + 3), 16'(i + 4)};
      end
    end else begin
      gdram_resp_valid <= gdram_req_valid && !gdram_req_we;
      if (gdram_req_valid) begin
        if (gdram_req_we) begin
          gdram_mem[gdram_req_addr[10:3]] <= gdram_req_wdata;
        end else begin
          gdram_resp_rdata <= gdram_mem[gdram_req_addr[10:3]];
        end
      end
    end
  end

  // C2C SerDes High-Speed Loopback (rewrite dst_id to 4'd0 on RX so router delivers locally)
  assign c2c_rx_valid = c2c_tx_valid;
  assign c2c_rx_flit  = c2c_tx_flit;

  // ---------------------------------------------------------------------------
  // 3. Helper Function to Construct 128-bit BANG ISA Instructions
  // ---------------------------------------------------------------------------
  function automatic logic [127:0] make_inst(
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
  // 4. Cycle-Driven End-to-End BANG C Union-Task Stimulus & Self-Check
  // ---------------------------------------------------------------------------
  int unsigned cyc_cnt;
  int unsigned err_cnt;
  logic        seen_mpu_bcast_done;
  logic        seen_c2c_ack;
  logic        seen_c2c_nack;
  logic        seen_sec_err;
  logic        seen_ded_err;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cyc_cnt              <= 0;
      err_cnt              <= 0;
      ipu_inst_valid       <= 4'b0000;
      ipu_inst             <= '0;
      mpu_cmd_valid        <= 1'b0;
      mpu_cmd_inst         <= 128'd0;
      union_task_mask      <= 4'b1111;
      wram_ping_pong_sel   <= 1'b0;
      mfu_idx_offset       <= {16'd24, 16'd16, 16'd8, 16'd0};
      mfu_decomp_bitmap    <= 8'b1010_0101;
      vfu_cos_sin_lut      <= {4{16'h0080, 16'h00DF}};
      noc_allreduce_en     <= 1'b1;
      ext_sram_valid       <= 1'b0;
      ext_sram_we          <= 1'b0;
      ext_sram_addr        <= 11'd0;
      ext_sram_wdata       <= 64'd0;
      c2c_err_inject_crc   <= 1'b0;
      c2c_replay_trigger   <= 1'b0;
      c2c_replay_seq       <= 5'd0;
      err_inject_bank      <= 3'd0;
      err_inject_mask      <= 72'd0;
      seen_mpu_bcast_done  <= 1'b0;
      seen_c2c_ack         <= 1'b0;
      seen_c2c_nack        <= 1'b0;
      seen_sec_err         <= 1'b0;
      seen_ded_err         <= 1'b0;
    end else begin
      cyc_cnt            <= cyc_cnt + 1;
      ipu_inst_valid     <= ipu_inst_valid & ~ipu_inst_ready;
      mpu_cmd_valid      <= 1'b0;
      ext_sram_valid     <= 1'b0;
      ext_sram_we        <= 1'b0;
      c2c_err_inject_crc <= 1'b0;
      c2c_replay_trigger <= 1'b0;
      err_inject_mask    <= 72'd0;

      if (mpu_done_valid) seen_mpu_bcast_done <= 1'b1;
      if (c2c_ack_valid)  seen_c2c_ack        <= 1'b1;
      if (c2c_nack_valid) seen_c2c_nack       <= 1'b1;
      if (chip_sec_err)   seen_sec_err        <= 1'b1;
      if (chip_ded_err)   seen_ded_err        <= 1'b1;

      // Step 1A (Cycles 2..9): Preload MPU Cluster Shared SRAM Banks 0..7
      if (cyc_cnt >= 2 && cyc_cnt <= 9) begin
        ext_sram_valid <= 1'b1;
        ext_sram_we    <= 1'b1;
        ext_sram_addr  <= 11'(cyc_cnt - 2);
        ext_sram_wdata <= {4{16'h0100 + 16'(cyc_cnt)}};
      end

      // Step 1B (Cycle 12): Issue OP_MPU_BCAST_SRAM (1-to-4 Multi-Cast Broadcast)
      if (cyc_cnt == 12) begin
        mpu_cmd_valid <= 1'b1;
        mpu_cmd_inst  <= make_inst(
          OP_MPU_BCAST_SRAM, ENG_MPU_COL, PREC_FP16, SPARSE_DENSE,
          MEM_SPACE_SRAM, MEM_SPACE_NRAM, 4'b0000, 8'hA1,
          32'h0000_0000, 32'h0000_0000, 16'h0000, 16'd4
        );
      end

      // Step 1C (Cycle 20): 4-IPU MFU 2D Strided & Decompression DMA (GDRAM -> NRAM/WRAM)
      if (cyc_cnt == 20) begin
        ipu_inst_valid <= 4'b1111;
        ipu_inst[0] <= make_inst(OP_BANG_MEMCPY_2D,  ENG_MFU_DMA, PREC_INT8, SPARSE_DENSE,
                                 MEM_SPACE_GDRAM, MEM_SPACE_NRAM, 4'b0000, 8'h10,
                                 32'h0000_0000, 32'h0000_0000, 16'h0010, 16'h0202);
        ipu_inst[1] <= make_inst(OP_BANG_DECOMP_DMA, ENG_MFU_DMA, PREC_INT8, SPARSE_2_OF_4,
                                 MEM_SPACE_GDRAM, MEM_SPACE_WRAM, 4'b0000, 8'h11,
                                 32'h0000_0000, 32'h0000_0020, 16'h0008, 16'h0004);
        ipu_inst[2] <= make_inst(OP_BANG_GATHER,     ENG_MFU_DMA, PREC_BF16, SPARSE_DENSE,
                                 MEM_SPACE_GDRAM, MEM_SPACE_NRAM, 4'b0000, 8'h12,
                                 32'h0000_0000, 32'h0000_0040, 16'h0008, 16'h0004);
        ipu_inst[3] <= make_inst(OP_BANG_TRANSPOSE,  ENG_MFU_DMA, PREC_FP16, SPARSE_DENSE,
                                 MEM_SPACE_GDRAM, MEM_SPACE_NRAM, 4'b0000, 8'h13,
                                 32'h0000_0000, 32'h0000_0060, 16'h0008, 16'h0004);
      end
      // Step 2A (Cycle 50): Flip Ping-Pong WRAM & Run 4-IPU Cooperative TFU MatMul
      if (cyc_cnt == 50) begin
        wram_ping_pong_sel <= 1'b1;
        ipu_inst_valid     <= 4'b1111;
        ipu_inst[0] <= make_inst(OP_BANG_MATMUL,    ENG_TFU_MAT, PREC_INT8, SPARSE_DENSE,
                                 MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h20,
                                 32'h0000_0100, 32'h0000_0000, 16'h0000, 16'h0004);
        ipu_inst[1] <= make_inst(OP_BANG_SPARSE_MM, ENG_TFU_MAT, PREC_INT4, SPARSE_2_OF_4,
                                 MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h21,
                                 32'h0000_0100, 32'h0000_0000, 16'h0000, 16'h0004);
        ipu_inst[2] <= make_inst(OP_BANG_QUANT_MM,  ENG_TFU_MAT, PREC_INT8, SPARSE_DENSE,
                                 MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h22,
                                 32'h0000_0100, 32'h0000_0000, 16'h0000, 16'h0004);
        ipu_inst[3] <= make_inst(OP_BANG_MATMUL,    ENG_TFU_MAT, PREC_BF16, SPARSE_DENSE,
                                 MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h23,
                                 32'h0000_0100, 32'h0000_0000, 16'h0000, 16'h0004);
      end

      // Step 3 (Cycle 75): 4-IPU VFU/SFU Pipeline (RoPE, RMSNorm, Softmax, SwiGLU)
      if (cyc_cnt == 75) begin
        ipu_inst_valid <= 4'b1111;
        ipu_inst[0] <= make_inst(OP_BANG_ROPE,    ENG_VFU_VEC, PREC_FP16, SPARSE_DENSE,
                                 MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h30,
                                 32'h0000_0200, 32'h0000_0100, 16'h0000, 16'h0002);
        ipu_inst[1] <= make_inst(OP_BANG_RMSNORM, ENG_VFU_VEC, PREC_FP16, SPARSE_DENSE,
                                 MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h31,
                                 32'h0000_0200, 32'h0000_0100, 16'h0000, 16'h0002);
        ipu_inst[2] <= make_inst(OP_BANG_SOFTMAX, ENG_VFU_VEC, PREC_FP16, SPARSE_DENSE,
                                 MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h32,
                                 32'h0000_0200, 32'h0000_0100, 16'h0000, 16'h0002);
        ipu_inst[3] <= make_inst(OP_BANG_SWIGLU,  ENG_VFU_VEC, PREC_FP16, SPARSE_DENSE,
                                 MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h33,
                                 32'h0000_0200, 32'h0000_0100, 16'h0000, 16'h0002);
      end

      // Step 4A (Cycles 95 & 98): Staggered OP_SYNC_CLUSTER Hardware Union-Task Barrier
      if (cyc_cnt == 95) begin
        ipu_inst_valid <= 4'b0111; // IPU 0, 1, 2 arrive first
        for (int i = 0; i < 3; i++) begin
          ipu_inst[i] <= make_inst(OP_SYNC_CLUSTER, ENG_ICU_CTRL, PREC_FP16, SPARSE_DENSE,
                                   MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h40 + 8'(i),
                                   32'd0, 32'd0, 16'd0, 16'd0);
        end
      end
      if (cyc_cnt == 98) begin
        ipu_inst_valid <= 4'b1111; // IPU 3 arrives -> all 4 IPUs ready at barrier
        ipu_inst[3] <= make_inst(OP_SYNC_CLUSTER, ENG_ICU_CTRL, PREC_FP16, SPARSE_DENSE,
                                 MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h43,
                                 32'd0, 32'd0, 16'd0, 16'd0);
      end

      // Step 4B (Cycle 105): OP_MPU_ALLREDUCE via NoC Router Port 4 -> C2C SerDes PCS
      if (cyc_cnt == 105) begin
        mpu_cmd_valid <= 1'b1;
        mpu_cmd_inst  <= make_inst(
          OP_MPU_ALLREDUCE, ENG_MPU_COL, PREC_FP16, SPARSE_DENSE,
          MEM_SPACE_SRAM, MEM_SPACE_MLULK, 4'b0000, 8'hB2,
          32'h0000_0010, 32'h0000_0000, 16'h000C, 16'd4
        );
      end

      // Inject 1-cycle C2C CRC fault during AllReduce & trigger Go-Back-N replay
      if (cyc_cnt >= 106 && cyc_cnt <= 112 && c2c_tx_valid && !seen_c2c_nack) begin
        c2c_err_inject_crc <= 1'b1;
      end
      if (cyc_cnt == 116) begin
        c2c_replay_trigger <= 1'b1;
        c2c_replay_seq     <= 5'd0;
      end

      // Step 4C (Cycles 120..126): SECDED 1-Bit SEC & 2-Bit DED Fault Injection on IPU0 NRAM
      if (cyc_cnt == 120) begin
        ipu_inst_valid <= 4'b0001;
        ipu_inst[0]    <= make_inst(OP_BANG_MATMUL, ENG_TFU_MAT, PREC_INT8, SPARSE_DENSE,
                                    MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h50,
                                    32'h0000_0200, 32'h0000_0000, 16'h0000, 16'h0004);
      end
      if (cyc_cnt == 121 || cyc_cnt == 122) begin
        err_inject_bank <= 3'd0;
        err_inject_mask <= 72'h00_0000_0000_0000_0001; // 1-bit SEC during NRAM read
      end
      if (cyc_cnt == 123 || cyc_cnt == 124) begin
        err_inject_bank <= 3'd0;
        err_inject_mask <= 72'h00_0000_0000_0000_0003; // 2-bit DED during NRAM read
      end

      // Final End-to-End Verification Summary at Cycle 145
      if (cyc_cnt == 145) begin
        if (!seen_mpu_bcast_done) err_cnt = err_cnt + 1;
        if (total_retired_insts < 32'd16) err_cnt = err_cnt + 1;
        if (total_mac_ops == 32'd0) err_cnt = err_cnt + 1;
        if (total_active_mac_cycles == 32'd0) err_cnt = err_cnt + 1;
        if (total_gated_saved_cycles == 32'd0) err_cnt = err_cnt + 1;
        if (union_barrier_cnt != 32'd1) err_cnt = err_cnt + 1;
        if (routed_flit_cnt == 32'd0) err_cnt = err_cnt + 1;
        if (!seen_c2c_ack || !seen_c2c_nack) err_cnt = err_cnt + 1;
        if (c2c_crc_err_cnt == 32'd0 || c2c_retransmit_cnt == 32'd0) err_cnt = err_cnt + 1;
        if (!seen_sec_err || !seen_ded_err) err_cnt = err_cnt + 1;

        $display("======================================================================");
        $display("[STAGE-8 FULL-CHIP CO-SIM] Cambricon Siyuan 590/690 mlu_chip_top Summary:");
        $display("  Total Retired BANG Insts : %0d", total_retired_insts);
        $display("  Total Active MAC Cycles  : %0d", total_active_mac_cycles);
        $display("  Total Gated Saved Cycles : %0d", total_gated_saved_cycles);
        $display("  Total Tensor MAC Ops     : %0d", total_mac_ops);
        $display("  Union-Task Sync Barriers : %0d", union_barrier_cnt);
        $display("  NoC Routed Flits         : %0d", routed_flit_cnt);
        $display("  C2C CRC Errors / Replays : %0d / %0d", c2c_crc_err_cnt, c2c_retransmit_cnt);
        $display("  SECDED ECC SEC / DED     : %0b / %0b", seen_sec_err, seen_ded_err);
        $display("  Error Count              : %0d", err_cnt);
        $display("======================================================================");
        if (err_cnt == 0) begin
          $display("STAGE8_FULL_CHIP_COSIM_PASS");
        end else begin
          $display("STAGE8_FULL_CHIP_COSIM_FAIL (err_cnt=%0d)", err_cnt);
        end
        $finish;
      end
    end
  end

endmodule : tb_stage8_full_chip_cosim
