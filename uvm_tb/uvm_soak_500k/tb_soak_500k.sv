// =============================================================================
// File: uvm_tb/uvm_soak_500k/tb_soak_500k.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Stage 17 — 500,000-Cycle Full-Chip Randomized Soak Stress Test
//              on mlu_chip_top driving back-to-back randomized BANG ISA streams
//              across all 4 IPU cores, MPU Shared SRAM core, 5-port MLU-Link NoC
//              Router, and C2C SerDes PCS with continuous fault injection &
//              online scoreboard verification (0 hangs, 0 deadlocks, 0 errors).
// =============================================================================
`include "mlu_pkg.sv"

module tb_soak_500k (
  input  logic clk,
  input  logic rst_n
);
  import mlu_pkg::*;

  localparam int unsigned NUM_IPUS     = 4;
  localparam int unsigned TOTAL_CYCLES = 500000;

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
  logic                       c2c_err_inject_crc;
  logic [127:0]               c2c_rx_flit;
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

  assign c2c_rx_valid = c2c_tx_valid;
  assign c2c_rx_flit  = c2c_tx_flit;

  // ---------------------------------------------------------------------------
  // 3. Helper Functions for Randomized BANG ISA Instruction Generation
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

  function automatic mlu_opcode_e pick_dma_op(input logic [2:0] sel);
    unique case (sel)
      3'd0: return OP_BANG_MEMCPY_1D;
      3'd1: return OP_BANG_MEMCPY_2D;
      3'd2: return OP_BANG_GATHER;
      3'd3: return OP_BANG_SCATTER;
      3'd4: return OP_BANG_DECOMP_DMA;
      default: return OP_BANG_TRANSPOSE;
    endcase
  endfunction

  function automatic mlu_opcode_e pick_tfu_op(input logic [1:0] sel);
    unique case (sel)
      2'd0: return OP_BANG_MATMUL;
      2'd1: return OP_BANG_SPARSE_MM;
      default: return OP_BANG_QUANT_MM;
    endcase
  endfunction

  function automatic mlu_prec_e pick_prec(input logic [2:0] sel);
    unique case (sel)
      3'd0: return PREC_INT4;
      3'd1: return PREC_INT8;
      3'd2: return PREC_FP8_E4M3;
      3'd3: return PREC_FP8_E5M2;
      3'd4: return PREC_FP16;
      3'd5: return PREC_BF16;
      3'd6: return PREC_TF32;
      default: return PREC_FP32;
    endcase
  endfunction

  function automatic mlu_sparse_mode_e pick_sparse(input logic [1:0] sel);
    unique case (sel)
      2'd0: return SPARSE_DENSE;
      2'd1: return SPARSE_2_OF_4;
      default: return SPARSE_BLOCK_4X4;
    endcase
  endfunction

  function automatic mlu_opcode_e pick_vfu_op(input logic [2:0] sel);
    unique case (sel)
      3'd0: return OP_BANG_VADD;
      3'd1: return OP_BANG_VMUL;
      3'd2: return OP_BANG_SOFTMAX;
      3'd3: return OP_BANG_ROPE;
      3'd4: return OP_BANG_RMSNORM;
      3'd5: return OP_BANG_SWIGLU;
      default: return OP_BANG_QUANT_STAT;
    endcase
  endfunction

  // ---------------------------------------------------------------------------
  // 4. 500,000-Cycle Randomized Stress Driver, Watchdog & Online Scoreboard
  // ---------------------------------------------------------------------------
  int unsigned cyc_cnt;
  int unsigned epoch_id;
  int unsigned epoch_phase;
  logic [63:0] lfsr_q;

  int unsigned hang_watchdog_cnt;
  int unsigned hang_err_cnt;
  int unsigned deadlock_err_cnt;
  int unsigned sb_mismatch_cnt;

  logic [31:0] prev_retired_q;
  int unsigned mpu_bcast_cnt;
  int unsigned mpu_allreduce_cnt;
  int unsigned dma_batches_cnt;
  int unsigned tfu_batches_cnt;
  int unsigned vfu_batches_cnt;
  int unsigned sync_ipu_batches_cnt;
  int unsigned pmu_cfg_batches_cnt;
  int unsigned sec_fault_cnt;
  int unsigned ded_fault_cnt;
  int unsigned c2c_ack_cnt;
  int unsigned c2c_nack_cnt;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cyc_cnt              <= 0;
      epoch_id             <= 0;
      epoch_phase          <= 0;
      lfsr_q               <= 64'hCAFE_BABE_1357_9BDF;
      hang_watchdog_cnt    <= 0;
      hang_err_cnt         <= 0;
      deadlock_err_cnt     <= 0;
      sb_mismatch_cnt      <= 0;
      prev_retired_q       <= 32'd0;
      mpu_bcast_cnt        <= 0;
      mpu_allreduce_cnt    <= 0;
      dma_batches_cnt      <= 0;
      tfu_batches_cnt      <= 0;
      vfu_batches_cnt      <= 0;
      sync_ipu_batches_cnt <= 0;
      pmu_cfg_batches_cnt  <= 0;
      sec_fault_cnt        <= 0;
      ded_fault_cnt        <= 0;
      c2c_ack_cnt          <= 0;
      c2c_nack_cnt         <= 0;

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
    end else begin
      cyc_cnt            <= cyc_cnt + 1;
      lfsr_q             <= {lfsr_q[62:0], lfsr_q[63] ^ lfsr_q[61] ^ lfsr_q[60] ^ lfsr_q[58]};
      ipu_inst_valid     <= ipu_inst_valid & ~ipu_inst_ready;
      mpu_cmd_valid      <= 1'b0;
      ext_sram_valid     <= 1'b0;
      ext_sram_we        <= 1'b0;
      c2c_err_inject_crc <= 1'b0;
      c2c_replay_trigger <= 1'b0;
      err_inject_mask    <= 72'd0;

      if (c2c_ack_valid)  c2c_ack_cnt  <= c2c_ack_cnt + 1;
      if (c2c_nack_valid) c2c_nack_cnt <= c2c_nack_cnt + 1;
      if (chip_sec_err)   sec_fault_cnt <= sec_fault_cnt + 1;
      if (chip_ded_err)   ded_fault_cnt <= ded_fault_cnt + 1;

      // Online Anti-Hang / Anti-Deadlock Watchdog
      if (total_retired_insts < prev_retired_q) begin
        sb_mismatch_cnt <= sb_mismatch_cnt + 1;
      end
      if (total_retired_insts != prev_retired_q) begin
        prev_retired_q    <= total_retired_insts;
        hang_watchdog_cnt <= 0;
      end else if (|ipu_inst_valid || chip_busy) begin
        hang_watchdog_cnt <= hang_watchdog_cnt + 1;
        if (hang_watchdog_cnt > 250) begin
          hang_err_cnt     <= hang_err_cnt + 1;
          deadlock_err_cnt <= deadlock_err_cnt + 1;
        end
      end else begin
        hang_watchdog_cnt <= 0;
      end

      // Initial Preload of MPU Cluster Shared SRAM Banks 0..15 (Cycles 2..17)
      if (cyc_cnt >= 2 && cyc_cnt <= 17) begin
        ext_sram_valid <= 1'b1;
        ext_sram_we    <= 1'b1;
        ext_sram_addr  <= 11'(cyc_cnt - 2);
        ext_sram_wdata <= lfsr_q ^ {4{16'(cyc_cnt)}};
      end

      // 4,998 Randomized 100-Cycle Super-Epochs (Cycles 20 .. 499,819)
      if (cyc_cnt >= 20 && cyc_cnt < 499820) begin
        epoch_id    = (cyc_cnt - 20) / 100;
        epoch_phase = (cyc_cnt - 20) % 100;

        if (epoch_phase == 0 && mpu_cmd_ready) begin
          mpu_cmd_valid <= 1'b1;
          if (lfsr_q[0]) begin
            mpu_bcast_cnt <= mpu_bcast_cnt + 1;
            mpu_cmd_inst  <= make_inst(OP_MPU_BCAST_SRAM, ENG_MPU_COL, PREC_FP16, SPARSE_DENSE,
                                       MEM_SPACE_SRAM, MEM_SPACE_NRAM, 4'b0000, lfsr_q[7:0],
                                       32'h0000_0000, 32'h0000_0000, 16'h0000, 16'd4);
          end else begin
            mpu_allreduce_cnt <= mpu_allreduce_cnt + 1;
            mpu_cmd_inst      <= make_inst(OP_MPU_ALLREDUCE, ENG_MPU_COL, PREC_FP16, SPARSE_DENSE,
                                           MEM_SPACE_SRAM, MEM_SPACE_MLULK, 4'b0000, lfsr_q[7:0],
                                           32'h0000_0010, 32'h0000_0000, 16'h000C, 16'd4);
          end
        end

        // Inject C2C SerDes CRC-16 fault & Go-Back-N Replay every 5th epoch
        if ((epoch_id % 5 == 2) && epoch_phase >= 1 && epoch_phase <= 4 && c2c_tx_valid) begin
          c2c_err_inject_crc <= 1'b1;
        end
        if ((epoch_id % 5 == 2) && epoch_phase == 7) begin
          c2c_replay_trigger <= 1'b1;
          c2c_replay_seq     <= 5'd0;
        end

        // Phase 12: 4-IPU Randomized MFU DMA Batch (1D/2D/Gather/Scatter/Decomp/Transpose)
        if (epoch_phase == 12) begin
          dma_batches_cnt   <= dma_batches_cnt + 1;
          mfu_decomp_bitmap <= lfsr_q[15:8] | 8'h05;
          ipu_inst_valid    <= 4'b1111;
          for (int i = 0; i < 4; i++) begin
            ipu_inst[i] <= make_inst(
              pick_dma_op(lfsr_q[(i*3) +: 3]), ENG_MFU_DMA, pick_prec(lfsr_q[(i*3+12) +: 3]),
              SPARSE_DENSE, MEM_SPACE_GDRAM, (i == 1) ? MEM_SPACE_WRAM : MEM_SPACE_NRAM,
              4'b0000, 8'h10 + 8'(i), {20'd0, lfsr_q[19:18], 10'd0},
              {24'd0, lfsr_q[25:20], 2'b00}, 16'h0008, 16'h0002
            );
          end
        end

        // Phase 35: Flip Ping-Pong WRAM & 4-IPU Randomized TFU Multi-Precision/Sparse MatMul
        if (epoch_phase == 35) begin
          tfu_batches_cnt    <= tfu_batches_cnt + 1;
          wram_ping_pong_sel <= ~wram_ping_pong_sel;
          ipu_inst_valid     <= 4'b1111;
          for (int i = 0; i < 4; i++) begin
            ipu_inst[i] <= make_inst(
              pick_tfu_op(lfsr_q[(i*2) +: 2]), ENG_TFU_MAT, pick_prec(lfsr_q[(i*3+8) +: 3]),
              pick_sparse(lfsr_q[(i*2+20) +: 2]), MEM_SPACE_NRAM, MEM_SPACE_NRAM,
              4'b0000, 8'h20 + 8'(i), 32'h0000_0400, 32'h0000_0000, 16'h0000, 16'h0002
            );
          end
        end

        // Inject 1-Bit SEC and 2-Bit DED SECDED ECC faults during TFU NRAM read responses
        if (epoch_phase == 37 && (epoch_id % 4 == 1)) begin
          err_inject_bank <= 3'd0;
          err_inject_mask <= (72'd1 << lfsr_q[5:0]);
        end
        if (epoch_phase == 37 && (epoch_id % 4 == 3)) begin
          err_inject_bank <= 3'd0;
          err_inject_mask <= (72'd3 << lfsr_q[5:0]);
        end

        // Phase 55: 4-IPU Randomized VFU/SFU LLM Vector/Activation Ops
        if (epoch_phase == 55) begin
          vfu_batches_cnt <= vfu_batches_cnt + 1;
          ipu_inst_valid  <= 4'b1111;
          for (int i = 0; i < 4; i++) begin
            ipu_inst[i] <= make_inst(
              pick_vfu_op(lfsr_q[(i*3) +: 3]), ENG_VFU_VEC, pick_prec(lfsr_q[(i*3+12) +: 3]),
              SPARSE_DENSE, MEM_SPACE_NRAM, MEM_SPACE_NRAM,
              4'b0000, 8'h30 + 8'(i), 32'h0000_0800, 32'h0000_0400, 16'h0000, 16'h0002
            );
          end
        end

        // Phase 70: Local IPU Sync Barrier (OP_SYNC_IPU) or Dynamic PMU Clock Gate Config
        if (epoch_phase == 70) begin
          ipu_inst_valid <= 4'b1111;
          if (epoch_id[0]) begin
            sync_ipu_batches_cnt <= sync_ipu_batches_cnt + 1;
            for (int i = 0; i < 4; i++)
              ipu_inst[i] <= make_inst(OP_SYNC_IPU, ENG_ICU_CTRL, PREC_FP16, SPARSE_DENSE,
                                       MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h40 + 8'(i),
                                       32'd0, 32'd0, 16'd0, 16'd0);
          end else begin
            pmu_cfg_batches_cnt <= pmu_cfg_batches_cnt + 1;
            for (int i = 0; i < 4; i++)
              ipu_inst[i] <= make_inst(OP_PWR_GATE_CFG, ENG_ICU_CTRL, PREC_FP16, SPARSE_DENSE,
                                       MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h48 + 8'(i),
                                       32'd0, 32'd0, 16'd0, {13'd0, lfsr_q[2:0] | 3'd2});
          end
        end

        // Phase 82 & 84: Staggered 4-IPU Hardware Union-Task Sync Barrier (OP_SYNC_CLUSTER)
        if (epoch_phase == 82) begin
          ipu_inst_valid <= 4'b0111;
          for (int i = 0; i < 3; i++)
            ipu_inst[i] <= make_inst(OP_SYNC_CLUSTER, ENG_ICU_CTRL, PREC_FP16, SPARSE_DENSE,
                                     MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h50 + 8'(i),
                                     32'd0, 32'd0, 16'd0, 16'd0);
        end
        if (epoch_phase == 84) begin
          ipu_inst_valid <= 4'b1111;
          ipu_inst[3]    <= make_inst(OP_SYNC_CLUSTER, ENG_ICU_CTRL, PREC_FP16, SPARSE_DENSE,
                                      MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h53,
                                      32'd0, 32'd0, 16'd0, 16'd0);
        end
      end

      // Periodic 100k-Cycle Telemetry Heartbeat
      if ((cyc_cnt % 100000 == 0) && (cyc_cnt > 0)) begin
        $display("[SOAK-500K] Cycle %0d / %0d | Retired=%0d | MACs=%0d | Barriers=%0d | Flits=%0d | Hangs=%0d | Mismatches=%0d",
                 cyc_cnt, TOTAL_CYCLES, total_retired_insts, total_mac_ops,
                 union_barrier_cnt, routed_flit_cnt, hang_err_cnt, sb_mismatch_cnt);
      end

      // Final 500,000-Cycle Soak Verification Sign-Off
      if (cyc_cnt == TOTAL_CYCLES) begin
        if (total_retired_insts != 32'(4998 * 20)) sb_mismatch_cnt = sb_mismatch_cnt + 1;
        if (union_barrier_cnt != 32'd4998)         sb_mismatch_cnt = sb_mismatch_cnt + 1;
        if (total_mac_ops == 32'd0)                sb_mismatch_cnt = sb_mismatch_cnt + 1;
        if (total_gated_saved_cycles == 32'd0)     sb_mismatch_cnt = sb_mismatch_cnt + 1;
        if (routed_flit_cnt == 32'd0)              sb_mismatch_cnt = sb_mismatch_cnt + 1;
        if (c2c_crc_err_cnt == 32'd0 || c2c_retransmit_cnt == 32'd0) sb_mismatch_cnt = sb_mismatch_cnt + 1;
        if (sec_fault_cnt == 0 || ded_fault_cnt == 0) sb_mismatch_cnt = sb_mismatch_cnt + 1;

        $display("==============================================================================");
        $display(" STAGE 17: 500,000-CYCLE FULL-CHIP RANDOMIZED SOAK STRESS SUMMARY");
        $display("==============================================================================");
        $display("  Total Clock Cycles Simulated   : %0d", cyc_cnt);
        $display("  Total Randomized Epochs        : %0d", 4998);
        $display("  Total Retired BANG ISA Insts   : %0d (Expected: %0d)", total_retired_insts, 4998 * 20);
        $display("  Total Tensor MAC Operations    : %0d", total_mac_ops);
        $display("  Total Active MAC Cycles        : %0d", total_active_mac_cycles);
        $display("  Total PMU Clock-Gated Cycles   : %0d", total_gated_saved_cycles);
        $display("  Union-Task Cluster Barriers    : %0d (Expected: 4998)", union_barrier_cnt);
        $display("  MPU Broadcast / AllReduce Ops  : %0d / %0d", mpu_bcast_cnt, mpu_allreduce_cnt);
        $display("  MLU-Link NoC Routed Flits      : %0d", routed_flit_cnt);
        $display("  C2C SerDes ACKs / NACKs        : %0d / %0d", c2c_ack_cnt, c2c_nack_cnt);
        $display("  C2C CRC Faults / GBN Replays   : %0d / %0d", c2c_crc_err_cnt, c2c_retransmit_cnt);
        $display("  SECDED 1b SEC / 2b DED Events  : %0d / %0d", sec_fault_cnt, ded_fault_cnt);
        $display("  Hangs / Deadlocks / Mismatches : %0d / %0d / %0d", hang_err_cnt, deadlock_err_cnt, sb_mismatch_cnt);
        $display("==============================================================================");
        if (hang_err_cnt == 0 && deadlock_err_cnt == 0 && sb_mismatch_cnt == 0) begin
          $display("SOAK_500K_STRESS_TEST_PASS");
        end else begin
          $display("SOAK_500K_STRESS_TEST_FAIL");
        end
        $finish;
      end
    end
  end

endmodule : tb_soak_500k
