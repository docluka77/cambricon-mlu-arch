// =============================================================================
// File: uvm_tb/tb_stage3_4_icu_tfu.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Cycle-Accurate Verification Testbench for Stage 3 & Stage 4:
//              - mlu_bang_icu (Scoreboard RAW/WAW/WAR, dep_mask, SYNC_IPU/CLUSTER)
//              - mlu_pmu_clock_gate (Clock gating, SRAM sleep, 0-cycle wakeup)
//              - mlu_tfu_fractal_mac (INT8/INT4/FP8/BF16 dense, 2:4 & 4x4 sparse,
//                and Cambricon-Q statistical quantized matrix multiplication)
// =============================================================================
`include "mlu_pkg.sv"

module tb_stage3_4_icu_tfu (
  input  logic        clk_i,
  input  logic        rst_ni,
  output logic        test_done_o,
  output logic        test_pass_o,
  output logic [31:0] err_cnt_o
);

  // ---------------------------------------------------------------------------
  // 1. Interconnect Signals Between ICU, PMU, and TFU
  // ---------------------------------------------------------------------------
  logic             inst_valid;
  logic             inst_ready;
  logic [127:0]     inst_word;

  logic [4:0]       eng_cmd_valid;
  logic [4:0]       eng_cmd_ready;
  logic [127:0]     eng_cmd_inst;
  logic [4:0]       icu_dispatch_mask;

  logic             pwr_gate_cfg_valid;
  logic [7:0]       idle_threshold;
  logic             cluster_sync_req;
  logic             cluster_sync_ack;

  logic [4:0]       eng_done_valid;
  logic [4:0][7:0]  eng_done_tag;
  logic [4:0]       queue_busy;
  logic             hazard_stall;
  logic [31:0]      inst_retired_cnt;
  logic [31:0]      hazard_stall_cnt;

  logic [4:0]       eng_clk_en;
  logic [2:0]       sram_slp;
  logic [2:0]       sram_dslp;
  logic [2:0]       sram_wake_ready;
  logic [31:0]      active_mac_cycles;
  logic [31:0]      gated_saved_cycles;
  logic [31:0]      sram_sleep_cycles;

  logic             tfu_cmd_ready;
  logic             stream_valid;
  logic             stream_ready;
  logic [255:0]     nram_act;
  logic [255:0]     wram_wt;
  logic [31:0]      wram_sparse_meta;
  logic [15:0]      quant_scale;
  logic [7:0]       quant_zp;
  logic             tfu_busy;
  logic [255:0]     tfu_result_data;
  logic             tfu_result_valid;
  logic             tfu_done_valid;
  logic [7:0]       tfu_done_tag;
  logic [31:0]      zero_skip_cnt;
  logic [31:0]      total_mac_ops;

  // Mock external engines [4:1] completion & readiness
  logic [4:1]       ext_eng_done_valid_q;
  logic [4:1][7:0]  ext_eng_done_tag_q;

  assign eng_cmd_ready  = {4'b1111, tfu_cmd_ready};
  assign eng_done_valid = {ext_eng_done_valid_q, tfu_done_valid};
  assign eng_done_tag   = {ext_eng_done_tag_q,   tfu_done_tag};

  // ---------------------------------------------------------------------------
  // 2. DUT Instantiations
  // ---------------------------------------------------------------------------
  mlu_bang_icu u_icu (
    .clk_i                (clk_i),
    .rst_ni               (rst_ni),
    .inst_valid_i         (inst_valid),
    .inst_ready_o         (inst_ready),
    .inst_i               (inst_word),
    .eng_cmd_valid_o      (eng_cmd_valid),
    .eng_cmd_ready_i      (eng_cmd_ready),
    .eng_cmd_inst_o       (eng_cmd_inst),
    .icu_dispatch_mask_o  (icu_dispatch_mask),
    .pwr_gate_cfg_valid_o (pwr_gate_cfg_valid),
    .idle_threshold_o     (idle_threshold),
    .cluster_sync_req_o   (cluster_sync_req),
    .cluster_sync_ack_i   (cluster_sync_ack),
    .eng_done_valid_i     (eng_done_valid),
    .eng_done_tag_i       (eng_done_tag),
    .queue_busy_o         (queue_busy),
    .hazard_stall_o       (hazard_stall),
    .inst_retired_cnt_o   (inst_retired_cnt),
    .hazard_stall_cnt_o   (hazard_stall_cnt)
  );

  mlu_pmu_clock_gate #(
    .DEFAULT_IDLE_THRESH (8'd4)
  ) u_pmu (
    .clk_i                (clk_i),
    .rst_ni               (rst_ni),
    .eng_busy_i           ({queue_busy[4:1], tfu_busy}),
    .icu_dispatch_mask_i  (icu_dispatch_mask),
    .mem_active_i         ({queue_busy[3], tfu_busy, tfu_busy | queue_busy[2]}),
    .pwr_gate_cfg_valid_i (pwr_gate_cfg_valid),
    .idle_threshold_i     (idle_threshold),
    .eng_clk_en_o         (eng_clk_en),
    .sram_slp_o           (sram_slp),
    .sram_dslp_o          (sram_dslp),
    .sram_wake_ready_o    (sram_wake_ready),
    .active_mac_cycles_o  (active_mac_cycles),
    .gated_saved_cycles_o (gated_saved_cycles),
    .sram_sleep_cycles_o  (sram_sleep_cycles)
  );

  mlu_tfu_fractal_mac u_tfu (
    .clk_i              (clk_i),
    .rst_ni             (rst_ni),
    .cmd_valid_i        (eng_cmd_valid[0]),
    .cmd_ready_o        (tfu_cmd_ready),
    .cmd_inst_i         (eng_cmd_inst),
    .stream_valid_i     (stream_valid),
    .stream_ready_o     (stream_ready),
    .nram_act_i         (nram_act),
    .wram_wt_i          (wram_wt),
    .wram_sparse_meta_i (wram_sparse_meta),
    .quant_scale_i      (quant_scale),
    .quant_zp_i         (quant_zp),
    .tfu_busy_o         (tfu_busy),
    .result_data_o      (tfu_result_data),
    .result_valid_o     (tfu_result_valid),
    .done_valid_o       (tfu_done_valid),
    .done_tag_o         (tfu_done_tag),
    .zero_skip_cnt_o    (zero_skip_cnt),
    .total_mac_ops_o    (total_mac_ops)
  );

  // Helper function to pack a 128-bit BANG instruction word
  function automatic logic [127:0] make_inst(
    input mlu_pkg::mlu_opcode_e      op,
    input mlu_pkg::mlu_engine_e      eng,
    input mlu_pkg::mlu_prec_e        prec,
    input mlu_pkg::mlu_sparse_mode_e sp_mode,
    input mlu_pkg::mlu_mem_space_e   src_sp,
    input mlu_pkg::mlu_mem_space_e   dst_sp,
    input logic [3:0]                dep,
    input logic [7:0]                tag,
    input logic [31:0]               dst_a,
    input logic [31:0]               src0_a,
    input logic [15:0]               src1_s,
    input logic [15:0]               len_d
  );
    make_inst = {op, eng, prec, sp_mode, src_sp, dst_sp, dep, tag, dst_a, src0_a, src1_s, len_d};
  endfunction

  //Latched last TFU result for verification
  logic [255:0] last_tfu_res_q;
  logic [31:0]  cyc_q;
  logic [31:0]  err_q;

  assign test_done_o = (cyc_q >= 32'd70);
  assign test_pass_o = test_done_o && (err_q == 32'd0);
  assign err_cnt_o   = err_q;

  // ---------------------------------------------------------------------------
  // 3. Cycle-Driven Directed Verification Stimulus & Self-Checking Assertions
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cyc_q                <= 32'd0;
      err_q                <= 32'd0;
      inst_valid           <= 1'b0;
      inst_word            <= 128'd0;
      cluster_sync_ack     <= 1'b0;
      ext_eng_done_valid_q <= 4'b0000;
      ext_eng_done_tag_q   <= '0;
      stream_valid         <= 1'b1;
      nram_act             <= 256'd0;
      wram_wt              <= 256'd0;
      wram_sparse_meta     <= 32'hFFFF_FFFF;
      quant_scale          <= 16'h0080; // 0.5 in Q8.8
      quant_zp             <= 8'd10;
      last_tfu_res_q       <= 256'd0;
    end else begin
      cyc_q                <= cyc_q + 32'd1;
      inst_valid           <= 1'b0;
      cluster_sync_ack     <= 1'b0;
      ext_eng_done_valid_q <= 4'b0000;

      if (tfu_result_valid) begin
        last_tfu_res_q <= tfu_result_data;
      end

      unique case (cyc_q)
        // Cycle 1: Configure PMU idle threshold = 3 via OP_PWR_GATE_CFG
        32'd1: begin
          inst_valid <= 1'b1;
          inst_word  <= make_inst(mlu_pkg::OP_PWR_GATE_CFG, mlu_pkg::ENG_ICU_CTRL,
                                  mlu_pkg::PREC_INT8, mlu_pkg::SPARSE_DENSE,
                                  mlu_pkg::MEM_SPACE_NRAM, mlu_pkg::MEM_SPACE_NRAM,
                                  4'b0000, 8'h01, 32'd0, 32'd0, 16'd0, 16'd3);
        end

        // Cycle 12: Verify PMU entered clock gating & deep sleep during idle window
        // and issue INT8 Dense MatMul (32 lanes of 3 * 4 = 384)
        32'd12: begin
          if (eng_clk_en != 5'b00000 || sram_dslp != 3'b111 || gated_saved_cycles == 32'd0) begin
            $display("[FAIL] Cyc 12 PMU sleep check: clk_en=%b dslp=%b saved=%0d",
                     eng_clk_en, sram_dslp, gated_saved_cycles);
            err_q <= err_q + 32'd1;
          end
          inst_valid <= 1'b1;
          inst_word  <= make_inst(mlu_pkg::OP_BANG_MATMUL, mlu_pkg::ENG_TFU_MAT,
                                  mlu_pkg::PREC_INT8, mlu_pkg::SPARSE_DENSE,
                                  mlu_pkg::MEM_SPACE_NRAM, mlu_pkg::MEM_SPACE_NRAM,
                                  4'b0000, 8'h10, 32'h0000_1000, 32'h0000_0000, 16'd0, 16'd1);
          nram_act   <= {32{8'd3}};
          wram_wt    <= {32{8'd4}};
        end

        // Cycle 13: Verify 0-cycle clock wakeup when inst_valid was asserted
        32'd13: begin
          if (eng_clk_en[0] != 1'b1) begin
            $display("[FAIL] Cyc 13 PMU 0-cycle wakeup failed");
            err_q <= err_q + 32'd1;
          end
        end

        // Cycle 17: Check INT8 Dense result (384) & issue INT4 Dense MatMul (64 lanes of 2 * 3 = 384)
        32'd17: begin
          if ($signed(last_tfu_res_q[31:0]) != 32'sd384) begin
            $display("[FAIL] Cyc 17 INT8 Dense got %0d exp 384", $signed(last_tfu_res_q[31:0]));
            err_q <= err_q + 32'd1;
          end
          inst_valid <= 1'b1;
          inst_word  <= make_inst(mlu_pkg::OP_BANG_MATMUL, mlu_pkg::ENG_TFU_MAT,
                                  mlu_pkg::PREC_INT4, mlu_pkg::SPARSE_DENSE,
                                  mlu_pkg::MEM_SPACE_NRAM, mlu_pkg::MEM_SPACE_NRAM,
                                  4'b0000, 8'h11, 32'h0000_2000, 32'h0000_0000, 16'd0, 16'd1);
          nram_act   <= {64{4'd2}};
          wram_wt    <= {64{4'd3}};
        end

        // Cycle 22: Check INT4 Dense result (384) & issue FP8 E4M3 MatMul (32 lanes of 2.0 * 1.5 = 6144)
        32'd22: begin
          if ($signed(last_tfu_res_q[31:0]) != 32'sd384) begin
            $display("[FAIL] Cyc 22 INT4 Dense got %0d exp 384", $signed(last_tfu_res_q[31:0]));
            err_q <= err_q + 32'd1;
          end
          inst_valid <= 1'b1;
          inst_word  <= make_inst(mlu_pkg::OP_BANG_MATMUL, mlu_pkg::ENG_TFU_MAT,
                                  mlu_pkg::PREC_FP8_E4M3, mlu_pkg::SPARSE_DENSE,
                                  mlu_pkg::MEM_SPACE_NRAM, mlu_pkg::MEM_SPACE_NRAM,
                                  4'b0000, 8'h12, 32'h0000_3000, 32'h0000_0000, 16'd0, 16'd1);
          nram_act   <= {32{8'h40}}; // FP8 E4M3 2.0
          wram_wt    <= {32{8'h3C}}; // FP8 E4M3 1.5
        end

        // Cycle 27: Check FP8 E4M3 result (6144) & issue BF16 MatMul (16 lanes of 2.0 * 2.0)
        32'd27: begin
          if ($signed(last_tfu_res_q[31:0]) != 32'sd6144) begin
            $display("[FAIL] Cyc 27 FP8_E4M3 got %0d exp 6144", $signed(last_tfu_res_q[31:0]));
            err_q <= err_q + 32'd1;
          end
          inst_valid <= 1'b1;
          inst_word  <= make_inst(mlu_pkg::OP_BANG_MATMUL, mlu_pkg::ENG_TFU_MAT,
                                  mlu_pkg::PREC_BF16, mlu_pkg::SPARSE_DENSE,
                                  mlu_pkg::MEM_SPACE_NRAM, mlu_pkg::MEM_SPACE_NRAM,
                                  4'b0000, 8'h13, 32'h0000_4000, 32'h0000_0000, 16'd0, 16'd1);
          nram_act   <= {16{16'h4000}}; // BF16 2.0
          wram_wt    <= {16{16'h4000}}; // BF16 2.0
        end
        // Cycle 32: Check BF16 result (>0) & issue Cambricon-S 2:4 Sparse MatMul
        32'd32: begin
          if ($signed(last_tfu_res_q[31:0]) <= 32'sd0) begin
            $display("[FAIL] Cyc 32 BF16 got %0d", $signed(last_tfu_res_q[31:0]));
            err_q <= err_q + 32'd1;
          end
          inst_valid       <= 1'b1;
          inst_word        <= make_inst(mlu_pkg::OP_BANG_SPARSE_MM, mlu_pkg::ENG_TFU_MAT,
                                        mlu_pkg::PREC_INT8, mlu_pkg::SPARSE_2_OF_4,
                                        mlu_pkg::MEM_SPACE_NRAM, mlu_pkg::MEM_SPACE_NRAM,
                                        4'b0000, 8'h14, 32'h0000_5000, 32'h0000_0000, 16'd0, 16'd1);
          // Each 4-byte group has [0]=0, [1]=5, [2]=0, [3]=7; meta selects idx0=1, idx1=3 (4'b11_01 = 4'hD)
          nram_act         <= {8{8'd7, 8'd0, 8'd5, 8'd0}};
          wram_wt          <= {32{8'd2}};
          wram_sparse_meta <= 32'hDDDD_DDDD;
        end

        // Cycle 37: Check 2:4 Sparse result (16*(5*2) + 16*(7*2) = 160 + 224 = 384)
        // & issue 4x4 Block-Sparse MatMul (4 beats, bitmap=4'b0101 -> skips 2 zero blocks)
        32'd37: begin
          if ($signed(last_tfu_res_q[31:0]) != 32'sd384) begin
            $display("[FAIL] Cyc 37 2:4 Sparse got %0d exp 384", $signed(last_tfu_res_q[31:0]));
            err_q <= err_q + 32'd1;
          end
          inst_valid       <= 1'b1;
          inst_word        <= make_inst(mlu_pkg::OP_BANG_SPARSE_MM, mlu_pkg::ENG_TFU_MAT,
                                        mlu_pkg::PREC_INT8, mlu_pkg::SPARSE_BLOCK_4X4,
                                        mlu_pkg::MEM_SPACE_NRAM, mlu_pkg::MEM_SPACE_NRAM,
                                        4'b0000, 8'h15, 32'h0000_6000, 32'h0000_0000, 16'd0, 16'd4);
          nram_act         <= {32{8'd2}};
          wram_wt          <= {32{8'd3}};
          wram_sparse_meta <= 32'h0000_0005; // Beat 0 & Beat 2 active, Beat 1 & Beat 3 skipped
        end

        // Cycle 45: Check 4x4 Block-Sparse result (2 active beats * 32 * 6 = 384, zero_skip_cnt=2)
        // & issue Cambricon-Q Quantized MatMul (raw=192, scale=0.5, zp=10 -> 106)
        32'd45: begin
          if ($signed(last_tfu_res_q[31:0]) != 32'sd384 || zero_skip_cnt != 32'd2) begin
            $display("[FAIL] Cyc 45 Block-Sparse got %0d skip=%0d", $signed(last_tfu_res_q[31:0]), zero_skip_cnt);
            err_q <= err_q + 32'd1;
          end
          inst_valid       <= 1'b1;
          inst_word        <= make_inst(mlu_pkg::OP_BANG_QUANT_MM, mlu_pkg::ENG_TFU_MAT,
                                        mlu_pkg::PREC_INT8, mlu_pkg::SPARSE_DENSE,
                                        mlu_pkg::MEM_SPACE_NRAM, mlu_pkg::MEM_SPACE_NRAM,
                                        4'b0000, 8'h16, 32'h0000_7000, 32'h0000_0000, 16'd0, 16'd1);
          nram_act         <= {32{8'd2}};
          wram_wt          <= {32{8'd3}}; // 32 * 2 * 3 = 192 -> 192 * 0.5 + 10 = 106
        end

        // Cycle 50: Check Cambricon-Q Quantized result (106) & issue MFU DMA write to NRAM 0x1000
        32'd50: begin
          if ($signed(last_tfu_res_q[7:0]) != 8'sd106) begin
            $display("[FAIL] Cyc 50 Cambricon-Q got %0d exp 106", $signed(last_tfu_res_q[7:0]));
            err_q <= err_q + 32'd1;
          end
          inst_valid <= 1'b1;
          inst_word  <= make_inst(mlu_pkg::OP_BANG_MEMCPY_1D, mlu_pkg::ENG_MFU_DMA,
                                  mlu_pkg::PREC_INT8, mlu_pkg::SPARSE_DENSE,
                                  mlu_pkg::MEM_SPACE_GDRAM, mlu_pkg::MEM_SPACE_NRAM,
                                  4'b0000, 8'h20, 32'h0000_1000, 32'h8000_0000, 16'd0, 16'd64);
        end

        // Cycles 51..53: Present TFU instruction reading NRAM 0x1000 -> MUST stall on RAW hazard!
        32'd51, 32'd52, 32'd53: begin
          inst_valid <= 1'b1;
          inst_word  <= make_inst(mlu_pkg::OP_BANG_MATMUL, mlu_pkg::ENG_TFU_MAT,
                                  mlu_pkg::PREC_INT8, mlu_pkg::SPARSE_DENSE,
                                  mlu_pkg::MEM_SPACE_NRAM, mlu_pkg::MEM_SPACE_NRAM,
                                  4'b0000, 8'h21, 32'h0000_2000, 32'h0000_1000, 16'd0, 16'd1);
          if (cyc_q == 32'd52 && (!hazard_stall || inst_ready)) begin
            $display("[FAIL] Cyc 52 Expected RAW hazard stall");
            err_q <= err_q + 32'd1;
          end
          if (cyc_q == 32'd53) begin
            // Complete MFU DMA tag 0x20
            ext_eng_done_valid_q[2] <= 1'b1;
            ext_eng_done_tag_q[2]   <= 8'h20;
          end
        end

        // Cycle 55: Now RAW hazard is cleared, dispatch TFU instruction!
        32'd55: begin
          inst_valid <= 1'b1;
          inst_word  <= make_inst(mlu_pkg::OP_BANG_MATMUL, mlu_pkg::ENG_TFU_MAT,
                                  mlu_pkg::PREC_INT8, mlu_pkg::SPARSE_DENSE,
                                  mlu_pkg::MEM_SPACE_NRAM, mlu_pkg::MEM_SPACE_NRAM,
                                  4'b0000, 8'h21, 32'h0000_2000, 32'h0000_1000, 16'd0, 16'd1);
        end

        // Cycle 60: Issue OP_SYNC_IPU (queues are now drained)
        32'd60: begin
          inst_valid <= 1'b1;
          inst_word  <= make_inst(mlu_pkg::OP_SYNC_IPU, mlu_pkg::ENG_ICU_CTRL,
                                  mlu_pkg::PREC_INT8, mlu_pkg::SPARSE_DENSE,
                                  mlu_pkg::MEM_SPACE_NRAM, mlu_pkg::MEM_SPACE_NRAM,
                                  4'b0000, 8'h30, 32'd0, 32'd0, 16'd0, 16'd0);
        end

        // Cycles 62..64: Issue OP_SYNC_CLUSTER, verify cluster_sync_req_o, then assert ack
        32'd62, 32'd63, 32'd64: begin
          inst_valid <= 1'b1;
          inst_word  <= make_inst(mlu_pkg::OP_SYNC_CLUSTER, mlu_pkg::ENG_ICU_CTRL,
                                  mlu_pkg::PREC_INT8, mlu_pkg::SPARSE_DENSE,
                                  mlu_pkg::MEM_SPACE_NRAM, mlu_pkg::MEM_SPACE_NRAM,
                                  4'b0000, 8'h31, 32'd0, 32'd0, 16'd0, 16'd0);
          if (cyc_q == 32'd63 && (!cluster_sync_req || inst_ready)) begin
            $display("[FAIL] Cyc 63 Expected cluster_sync_req stall");
            err_q <= err_q + 32'd1;
          end
          if (cyc_q == 32'd64) begin
            cluster_sync_ack <= 1'b1;
          end
        end

        // Cycle 68: Final telemetry sanity check
        32'd68: begin
          if (inst_retired_cnt < 32'd10 || hazard_stall_cnt < 32'd3 || total_mac_ops < 32'd240) begin
            $display("[FAIL] Cyc 68 Telemetry mismatch: retired=%0d stalls=%0d macs=%0d",
                     inst_retired_cnt, hazard_stall_cnt, total_mac_ops);
            err_q <= err_q + 32'd1;
          end else begin
            $display("[PASS] Stage 3 & 4 ICU+PMU+TFU All Checks Passed! retired=%0d stalls=%0d mac_ops=%0d zero_skips=%0d gated_saved=%0d sram_sleep=%0d",
                     inst_retired_cnt, hazard_stall_cnt, total_mac_ops, zero_skip_cnt, gated_saved_cycles, sram_sleep_cycles);
          end
        end

        default: ;
      endcase
    end
  end

endmodule : tb_stage3_4_icu_tfu

