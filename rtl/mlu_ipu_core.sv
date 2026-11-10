// =============================================================================
// File: rtl/mlu_ipu_core.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Stage 7B — Cambricon IPU (Intelligent Processing Unit) Tensor
//              Processor Core integrating:
//              - mlu_bang_icu (128-bit BANG ISA Decoder & Multi-Queue Scoreboard)
//              - mlu_pmu_clock_gate (Dynamic Clock/Power Gating & Energy Telemetry)
//              - mlu_nram_banked_scratchpad (8-Bank 64b Private NRAM w/ Transpose)
//              - mlu_wram_weight_buffer (Ping-Pong 4-Bank Private WRAM w/ Sparsity)
//              - mlu_tfu_fractal_mac (Multi-Precision Sparse & Quantized Tensor MAC)
//              - mlu_vfu_sfu_pipe (8-Lane Vector & Special Function Unit Pipeline)
//              - mlu_mfu_dma_engine (1D/2D Strided, Gather/Scatter & Decomp DMA)
// =============================================================================
`include "mlu_pkg.sv"

module mlu_ipu_core #(
  parameter logic [1:0] CORE_ID    = 2'd0,
  parameter logic [3:0] CLUSTER_ID = 4'd0
) (
  input  logic         clk_i,
  input  logic         rst_ni,

  // Upstream BANG ISA Instruction Dispatch Stream
  input  logic         inst_valid_i,
  output logic         inst_ready_o,
  input  logic [127:0] inst_i,

  // Ping-Pong WRAM Buffer Select & Decompression/Gather Config Inputs
  input  logic         wram_ping_pong_sel_i,
  input  logic [63:0]  mfu_idx_offset_i,
  input  logic [7:0]   mfu_decomp_bitmap_i,
  input  logic [127:0] vfu_cos_sin_lut_i,

  // Cluster Shared SRAM Port (to/from MPU Core)
  output logic         sram_req_valid_o,
  output logic         sram_req_we_o,
  output logic [10:0]  sram_req_addr_o,
  output logic [63:0]  sram_req_wdata_o,
  input  logic         sram_req_grant_i,
  input  logic         sram_resp_valid_i,
  input  logic [63:0]  sram_resp_rdata_i,

  // MPU 1-to-4 Single-Cycle Multi-Cast Broadcast Input
  input  logic         mpu_bcast_valid_i,
  input  logic [10:0]  mpu_bcast_addr_i,
  input  logic [255:0] mpu_bcast_data_i,

  // External HBM2e/HBM3e GDRAM Memory Interface
  output logic         gdram_req_valid_o,
  output logic         gdram_req_we_o,
  output logic [31:0]  gdram_req_addr_o,
  output logic [63:0]  gdram_req_wdata_o,
  input  logic         gdram_resp_valid_i,
  input  logic [63:0]  gdram_resp_rdata_i,

  // Cluster Hardware Union-Task Sync Barrier Handshake (OP_SYNC_CLUSTER)
  output logic         cluster_sync_req_o,
  input  logic         cluster_sync_ack_i,

  // ECC Fault Injection & Aggregated Core RAS Telemetry
  input  logic [2:0]   err_inject_bank_i,
  input  logic [71:0]  err_inject_mask_i,
  output logic         core_sec_err_o,
  output logic         core_ded_err_o,

  // Hardware Performance & Energy Counters
  output logic         core_busy_o,
  output logic [31:0]  inst_retired_cnt_o,
  output logic [31:0]  active_mac_cycles_o,
  output logic [31:0]  gated_saved_cycles_o,
  output logic [31:0]  total_mac_ops_o,
  output logic [31:0]  zero_skip_cnt_o
);

  // ---------------------------------------------------------------------------
  // 1. Internal Interconnect Wires & Engine Control Signals
  // ---------------------------------------------------------------------------
  logic [4:0]       eng_cmd_valid;
  logic [4:0]       eng_cmd_ready;
  logic [127:0]     eng_cmd_inst;
  logic [4:0]       icu_dispatch_mask;
  logic             pwr_gate_cfg_valid;
  logic [7:0]       idle_threshold;
  logic [4:0]       eng_done_valid;
  logic [4:0][7:0]  eng_done_tag;
  logic [4:0]       icu_queue_busy;
  logic             icu_hazard_stall;
  logic [31:0]      icu_hazard_stall_cnt;
  // PMU Clock Gate & Energy Wires
  logic [4:0]       eng_busy_vec;
  logic [2:0]       mem_active_vec;
  logic [4:0]       eng_clk_en;
  logic [2:0]       sram_slp;
  logic [2:0]       sram_dslp;
  logic [2:0]       sram_wake_ready;
  logic [31:0]      sram_sleep_cycles;

  // TFU Wires
  logic             tfu_busy;
  logic             tfu_stream_valid;
  logic             tfu_stream_ready;
  logic [255:0]     tfu_nram_act;
  logic [255:0]     tfu_wram_wt;
  logic [31:0]      tfu_wram_sparse_meta;
  logic [15:0]      tfu_quant_scale;
  logic [7:0]       tfu_quant_zp;
  logic [255:0]     tfu_result_data;
  logic             tfu_result_valid;

  // VFU Wires
  logic             vfu_busy;
  logic [127:0]     vfu_vec_a;
  logic [127:0]     vfu_vec_b;
  logic [127:0]     vfu_vec_out;
  logic             vfu_vec_out_valid;
  logic [31:0]      vfu_softmax_sum;
  logic [15:0]      vfu_softmax_max;
  logic [15:0]      vfu_absmax;
  logic [15:0]      vfu_min_val;
  logic [15:0]      vfu_max_val;
  logic [15:0]      vfu_dyn_scale;

  // MFU Wires
  logic             mfu_busy;
  logic             mfu_rd_req_valid;
  logic [2:0]       mfu_rd_req_space;
  logic [31:0]      mfu_rd_req_addr;
  logic             mfu_rd_resp_valid;
  logic [63:0]      mfu_rd_resp_data;
  logic             mfu_wr_req_valid;
  logic [2:0]       mfu_wr_req_space;
  logic [31:0]      mfu_wr_req_addr;
  logic [63:0]      mfu_wr_req_data;
  logic             mfu_transpose_mode;
  logic [31:0]      mfu_comp_bytes_rd;
  logic [31:0]      mfu_uncomp_bytes_wr;

  // Cambricon-LLM Flash-KV & Speculative Decoding Engine Wires
  logic [127:0]     llm_kv_dequant_out;
  logic [63:0]      llm_kv_packed_out;
  logic             llm_flash_req_valid;
  logic [31:0]      llm_flash_page_addr;
  logic [7:0]       llm_accepted_bitmap;
  logic [3:0]       llm_accepted_len;
  logic [2:0]       llm_bonus_token_idx;
  logic [31:0]      llm_total_accepted_tokens;
  logic [31:0]      llm_total_kv_bytes_saved;
  logic [31:0]      llm_flash_ecc_err_cnt;

  // NRAM & WRAM Wires
  logic [7:0]       nram_req_valid;
  logic [7:0]       nram_req_we;
  logic [7:0][9:0]  nram_req_addr;
  logic [7:0][63:0] nram_req_wdata;
  logic [7:0]       nram_req_grant;
  logic [7:0][63:0] nram_resp_rdata;
  logic [7:0]       nram_resp_valid;
  logic             nram_conflict_stall;
  logic [31:0]      nram_conflict_cnt;
  logic             nram_sec_err;
  logic             nram_ded_err;

  logic             wram_dma_we;
  logic [8:0]       wram_dma_addr;
  logic [63:0]      wram_dma_wdata;
  logic             wram_sparse_meta_we;
  logic [31:0]      wram_sparse_meta_wdata;
  logic             wram_tfu_rd_en;
  logic [6:0]       wram_tfu_rd_addr;
  logic [255:0]     wram_tfu_weight_vec;
  logic [31:0]      wram_tfu_sparse_meta;
  logic             wram_tfu_weight_valid;
  logic             wram_sec_err;
  logic             wram_ded_err;

  // ---------------------------------------------------------------------------
  // 2. BANG ISA Instruction Control Unit (ICU) & Scoreboard
  // ---------------------------------------------------------------------------
  mlu_bang_icu #(
    .SCOREBOARD_SLOTS (8)
  ) u_bang_icu (
    .clk_i                (clk_i),
    .rst_ni               (rst_ni),
    .inst_valid_i         (inst_valid_i),
    .inst_ready_o         (inst_ready_o),
    .inst_i               (inst_i),
    .eng_cmd_valid_o      (eng_cmd_valid),
    .eng_cmd_ready_i      (eng_cmd_ready),
    .eng_cmd_inst_o       (eng_cmd_inst),
    .icu_dispatch_mask_o  (icu_dispatch_mask),
    .pwr_gate_cfg_valid_o (pwr_gate_cfg_valid),
    .idle_threshold_o     (idle_threshold),
    .cluster_sync_req_o   (cluster_sync_req_o),
    .cluster_sync_ack_i   (cluster_sync_ack_i),
    .eng_done_valid_i     (eng_done_valid),
    .eng_done_tag_i       (eng_done_tag),
    .queue_busy_o         (icu_queue_busy),
    .hazard_stall_o       (icu_hazard_stall),
    .inst_retired_cnt_o   (inst_retired_cnt_o),
    .hazard_stall_cnt_o   (icu_hazard_stall_cnt)
  );
  // ---------------------------------------------------------------------------
  // 3. Dynamic Clock/Power Gating & Energy Telemetry Controller (PMU)
  // ---------------------------------------------------------------------------
  logic col_busy_q, llm_busy_q;
  assign eng_busy_vec   = {llm_busy_q, col_busy_q, mfu_busy, vfu_busy, tfu_busy};
  assign mem_active_vec = {sram_req_valid_o | mpu_bcast_valid_i,
                           wram_dma_we | wram_tfu_rd_en,
                           |nram_req_valid};

  mlu_pmu_clock_gate #(
    .DEFAULT_IDLE_THRESH (8'd8)
  ) u_pmu_clock_gate (
    .clk_i                (clk_i),
    .rst_ni               (rst_ni),
    .eng_busy_i           (eng_busy_vec),
    .icu_dispatch_mask_i  (icu_dispatch_mask),
    .mem_active_i         (mem_active_vec),
    .pwr_gate_cfg_valid_i (pwr_gate_cfg_valid),
    .idle_threshold_i     (idle_threshold),
    .eng_clk_en_o         (eng_clk_en),
    .sram_slp_o           (sram_slp),
    .sram_dslp_o          (sram_dslp),
    .sram_wake_ready_o    (sram_wake_ready),
    .active_mac_cycles_o  (active_mac_cycles_o),
    .gated_saved_cycles_o (gated_saved_cycles_o),
    .sram_sleep_cycles_o  (sram_sleep_cycles)
  );

  // ---------------------------------------------------------------------------
  // 4. Tensor Function Unit (TFU) — Fractal Multi-Precision Sparse/Quant MAC
  // ---------------------------------------------------------------------------
  assign tfu_quant_scale = (vfu_dyn_scale != 16'd0) ? vfu_dyn_scale : 16'h0100;
  assign tfu_quant_zp    = 8'h00;

  mlu_tfu_fractal_mac u_tfu_fractal_mac (
    .clk_i              (clk_i),
    .rst_ni             (rst_ni),
    .cmd_valid_i        (eng_cmd_valid[0]),
    .cmd_ready_o        (eng_cmd_ready[0]),
    .cmd_inst_i         (eng_cmd_inst),
    .stream_valid_i     (tfu_stream_valid),
    .stream_ready_o     (tfu_stream_ready),
    .nram_act_i         (tfu_nram_act),
    .wram_wt_i          (tfu_wram_wt),
    .wram_sparse_meta_i (tfu_wram_sparse_meta),
    .quant_scale_i      (tfu_quant_scale),
    .quant_zp_i         (tfu_quant_zp),
    .tfu_busy_o         (tfu_busy),
    .result_data_o      (tfu_result_data),
    .result_valid_o     (tfu_result_valid),
    .done_valid_o       (eng_done_valid[0]),
    .done_tag_o         (eng_done_tag[0]),
    .zero_skip_cnt_o    (zero_skip_cnt_o),
    .total_mac_ops_o    (total_mac_ops_o)
  );

  // ---------------------------------------------------------------------------
  // 5. Vector & Special Function Unit (VFU/SFU) — 8-Lane Pipeline
  // ---------------------------------------------------------------------------
  mlu_vfu_sfu_pipe u_vfu_sfu_pipe (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .cmd_valid_i     (eng_cmd_valid[1]),
    .cmd_ready_o     (eng_cmd_ready[1]),
    .cmd_inst_i      (eng_cmd_inst),
    .vec_a_i         (vfu_vec_a),
    .vec_b_i         (vfu_vec_b),
    .cos_sin_lut_i   (vfu_cos_sin_lut_i),
    .vec_out_o       (vfu_vec_out),
    .vec_out_valid_o (vfu_vec_out_valid),
    .softmax_sum_o   (vfu_softmax_sum),
    .softmax_max_o   (vfu_softmax_max),
    .absmax_o        (vfu_absmax),
    .min_val_o       (vfu_min_val),
    .max_val_o       (vfu_max_val),
    .dyn_scale_o     (vfu_dyn_scale),
    .vfu_busy_o      (vfu_busy),
    .done_valid_o    (eng_done_valid[1]),
    .done_tag_o      (eng_done_tag[1])
  );

  // ---------------------------------------------------------------------------
  // 6. Memory Function Unit (MFU) — Strided, Gather/Scatter & Decomp DMA
  // ---------------------------------------------------------------------------
  mlu_mfu_dma_engine u_mfu_dma_engine (
    .clk_i                   (clk_i),
    .rst_ni                  (rst_ni),
    .cmd_valid_i             (eng_cmd_valid[2]),
    .cmd_ready_o             (eng_cmd_ready[2]),
    .cmd_inst_i              (eng_cmd_inst),
    .idx_offset_i            (mfu_idx_offset_i),
    .decomp_bitmap_i         (mfu_decomp_bitmap_i),
    .rd_req_valid_o          (mfu_rd_req_valid),
    .rd_req_space_o          (mfu_rd_req_space),
    .rd_req_addr_o           (mfu_rd_req_addr),
    .rd_resp_valid_i         (mfu_rd_resp_valid),
    .rd_resp_data_i          (mfu_rd_resp_data),
    .wr_req_valid_o          (mfu_wr_req_valid),
    .wr_req_space_o          (mfu_wr_req_space),
    .wr_req_addr_o           (mfu_wr_req_addr),
    .wr_req_data_o           (mfu_wr_req_data),
    .nram_transpose_mode_o   (mfu_transpose_mode),
    .mfu_busy_o              (mfu_busy),
    .compressed_bytes_rd_o   (mfu_comp_bytes_rd),
    .uncompressed_bytes_wr_o (mfu_uncomp_bytes_wr),
    .done_valid_o            (eng_done_valid[2]),
    .done_tag_o              (eng_done_tag[2])
  );
  // ---------------------------------------------------------------------------
  // 7. Private 8-Bank NRAM Scratchpad & 4-Bank Ping-Pong WRAM Weight Buffer
  // ---------------------------------------------------------------------------
  mlu_nram_banked_scratchpad #(
    .NUM_BANKS  (8),
    .BANK_DEPTH (128),
    .DATA_W     (64),
    .ECC_W      (72)
  ) u_nram_scratchpad (
    .clk               (clk_i),
    .rst_n             (rst_ni),
    .req_valid_i       (nram_req_valid),
    .req_we_i          (nram_req_we),
    .req_addr_i        (nram_req_addr),
    .req_wdata_i       (nram_req_wdata),
    .req_grant_o       (nram_req_grant),
    .resp_rdata_o      (nram_resp_rdata),
    .resp_valid_o      (nram_resp_valid),
    .swizzle_en_i      (1'b1),
    .transpose_en_i    (mfu_transpose_mode),
    .conflict_stall_o  (nram_conflict_stall),
    .conflict_cnt_o    (nram_conflict_cnt),
    .err_inject_bank_i (err_inject_bank_i),
    .err_inject_mask_i (err_inject_mask_i),
    .sec_err_o         (nram_sec_err),
    .ded_err_o         (nram_ded_err)
  );

  mlu_wram_weight_buffer #(
    .NUM_BANKS  (4),
    .BANK_DEPTH (128),
    .DATA_W     (64),
    .ECC_W      (72),
    .META_W     (32)
  ) u_wram_weight_buffer (
    .clk                 (clk_i),
    .rst_n               (rst_ni),
    .ping_pong_sel_i     (wram_ping_pong_sel_i),
    .dma_we_i            (wram_dma_we),
    .dma_addr_i          (wram_dma_addr),
    .dma_wdata_i         (wram_dma_wdata),
    .sparse_meta_we_i    (wram_sparse_meta_we),
    .sparse_meta_wdata_i (wram_sparse_meta_wdata),
    .tfu_rd_en_i         (wram_tfu_rd_en),
    .tfu_rd_addr_i       (wram_tfu_rd_addr),
    .tfu_weight_vec_o    (wram_tfu_weight_vec),
    .tfu_sparse_meta_o   (wram_tfu_sparse_meta),
    .tfu_weight_valid_o  (wram_tfu_weight_valid),
    .err_inject_bank_i   (err_inject_bank_i[1:0]),
    .err_inject_mask_i   (err_inject_mask_i),
    .sec_err_o           (wram_sec_err),
    .ded_err_o           (wram_ded_err)
  );

  // ---------------------------------------------------------------------------
  // 8. Local ENG_MPU_COL ([3]) Responder & Cambricon-LLM Flash-KV Engine ([4])
  // ---------------------------------------------------------------------------
  logic [7:0] col_tag_q;

  assign eng_cmd_ready[3]  = ~col_busy_q;
  assign eng_done_valid[3] = col_busy_q;
  assign eng_done_tag[3]   = col_tag_q;
  assign llm_busy_q        = eng_done_valid[4];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      col_busy_q <= 1'b0;
      col_tag_q  <= 8'd0;
    end else begin
      col_busy_q <= eng_cmd_valid[3] & eng_cmd_ready[3];
      if (eng_cmd_valid[3] && eng_cmd_ready[3]) begin
        col_tag_q <= eng_cmd_inst[103:96];
      end
    end
  end

  mlu_cambricon_llm_flash_kv #(
    .KV_RING_DEPTH (16)
  ) u_cambricon_llm_flash_kv (
    .clk_i                   (clk_i),
    .rst_ni                  (rst_ni),
    .cmd_valid_i             (eng_cmd_valid[4]),
    .cmd_ready_o             (eng_cmd_ready[4]),
    .opcode_i                (eng_cmd_inst[127:122]),
    .prec_i                  (eng_cmd_inst[118:116]),
    .cmd_tag_i               (eng_cmd_inst[103:96]),
    .kv_wr_slot_i            (eng_cmd_inst[67:64]),
    .flash_base_page_i       (eng_cmd_inst[95:64]),
    .kv_fp16_in_i            (vfu_vec_a),
    .kv_rd_en_i              (1'b0),
    .kv_rd_addr_i            (4'd0),
    .kv_dequant_out_o        (llm_kv_dequant_out),
    .kv_packed_out_o         (llm_kv_packed_out),
    .flash_req_valid_o       (llm_flash_req_valid),
    .flash_page_addr_o       (llm_flash_page_addr),
    .flash_ecc_clean_i       (1'b1),
    .draft_prob_i            (vfu_vec_a),
    .target_prob_i           (vfu_vec_b),
    .tree_mask_i             ((eng_cmd_inst[23:16] != 8'd0) ? eng_cmd_inst[23:16] : 8'hFF),
    .accept_thresh_i         (eng_cmd_inst[15:0]),
    .done_valid_o            (eng_done_valid[4]),
    .done_tag_o              (eng_done_tag[4]),
    .accepted_bitmap_o       (llm_accepted_bitmap),
    .accepted_len_o          (llm_accepted_len),
    .bonus_token_idx_o       (llm_bonus_token_idx),
    .total_accepted_tokens_o (llm_total_accepted_tokens),
    .total_kv_bytes_saved_o  (llm_total_kv_bytes_saved),
    .flash_ecc_err_cnt_o     (llm_flash_ecc_err_cnt)
  );
  // ---------------------------------------------------------------------------
  // 9. NRAM, WRAM, Cluster Shared SRAM, & GDRAM Data-Path Routing
  // ---------------------------------------------------------------------------
  logic [6:0] tfu_row_cnt_q;
  logic [2:0] mfu_nram_rd_bank_q;
  logic       mfu_nram_rd_pend_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tfu_row_cnt_q      <= 7'd0;
      mfu_nram_rd_bank_q <= 3'd0;
      mfu_nram_rd_pend_q <= 1'b0;
    end else begin
      if (eng_cmd_valid[0] && eng_cmd_ready[0]) begin
        tfu_row_cnt_q <= eng_cmd_inst[38:32];
      end else if (tfu_busy && tfu_stream_ready) begin
        tfu_row_cnt_q <= tfu_row_cnt_q + 7'd1;
      end
      mfu_nram_rd_pend_q <= mfu_rd_req_valid &&
                            (mfu_rd_req_space == mlu_pkg::MEM_SPACE_NRAM);
      if (mfu_rd_req_valid) begin
        mfu_nram_rd_bank_q <= mfu_rd_req_addr[5:3];
      end
    end
  end

  assign wram_tfu_rd_en       = tfu_busy;
  assign wram_tfu_rd_addr     = tfu_row_cnt_q;
  assign tfu_stream_valid     = tfu_busy;
  assign tfu_nram_act         = {nram_resp_rdata[3], nram_resp_rdata[2],
                                 nram_resp_rdata[1], nram_resp_rdata[0]};
  assign tfu_wram_wt          = wram_tfu_weight_vec;
  assign tfu_wram_sparse_meta = wram_tfu_sparse_meta;

  assign vfu_vec_a = {nram_resp_rdata[1], nram_resp_rdata[0]};
  assign vfu_vec_b = {nram_resp_rdata[3], nram_resp_rdata[2]};

  // WRAM Shadow Write from MFU DMA or MPU Broadcast
  assign wram_dma_we = (mfu_wr_req_valid && (mfu_wr_req_space == mlu_pkg::MEM_SPACE_WRAM)) ||
                       mpu_bcast_valid_i;
  assign wram_dma_addr = mpu_bcast_valid_i ? mpu_bcast_addr_i[8:0] : mfu_wr_req_addr[11:3];
  assign wram_dma_wdata = mpu_bcast_valid_i ? mpu_bcast_data_i[63:0] : mfu_wr_req_data;
  assign wram_sparse_meta_we = wram_dma_we;
  assign wram_sparse_meta_wdata = wram_dma_wdata[31:0];

  // NRAM 8-Bank Request Multiplexer (TFU / VFU / MFU / MPU Broadcast)
  always_comb begin
    for (int b = 0; b < 8; b++) begin
      nram_req_valid[b] = 1'b0;
      nram_req_we[b]    = 1'b0;
      nram_req_addr[b]  = {tfu_row_cnt_q, b[2:0]};
      nram_req_wdata[b] = 64'd0;
    end

    if (mpu_bcast_valid_i) begin
      for (int b = 0; b < 4; b++) begin
        nram_req_valid[b] = 1'b1;
        nram_req_we[b]    = 1'b1;
        nram_req_addr[b]  = {mpu_bcast_addr_i[6:0], b[2:0]};
        nram_req_wdata[b] = mpu_bcast_data_i[b*64 +: 64];
      end
    end else if (tfu_result_valid) begin
      for (int b = 0; b < 4; b++) begin
        nram_req_valid[b] = 1'b1;
        nram_req_we[b]    = 1'b1;
        nram_req_addr[b]  = {tfu_row_cnt_q, b[2:0]};
        nram_req_wdata[b] = tfu_result_data[b*64 +: 64];
      end
    end else if (vfu_vec_out_valid) begin
      nram_req_valid[0] = 1'b1;
      nram_req_we[0]    = 1'b1;
      nram_req_wdata[0] = vfu_vec_out[63:0];
      nram_req_valid[1] = 1'b1;
      nram_req_we[1]    = 1'b1;
      nram_req_wdata[1] = vfu_vec_out[127:64];
    end else if (eng_done_valid[4]) begin
      nram_req_valid[2] = 1'b1;
      nram_req_we[2]    = 1'b1;
      nram_req_wdata[2] = llm_kv_packed_out;
      nram_req_valid[3] = 1'b1;
      nram_req_we[3]    = 1'b1;
      nram_req_wdata[3] = {llm_total_accepted_tokens[31:0], 17'd0,
                           llm_bonus_token_idx, llm_accepted_len, llm_accepted_bitmap};
    end else if (mfu_wr_req_valid && (mfu_wr_req_space == mlu_pkg::MEM_SPACE_NRAM)) begin
      nram_req_valid[mfu_wr_req_addr[5:3]] = 1'b1;
      nram_req_we[mfu_wr_req_addr[5:3]]    = 1'b1;
      nram_req_addr[mfu_wr_req_addr[5:3]]  = mfu_wr_req_addr[12:3];
      nram_req_wdata[mfu_wr_req_addr[5:3]] = mfu_wr_req_data;
    end else if (mfu_rd_req_valid && (mfu_rd_req_space == mlu_pkg::MEM_SPACE_NRAM)) begin
      nram_req_valid[mfu_rd_req_addr[5:3]] = 1'b1;
      nram_req_we[mfu_rd_req_addr[5:3]]    = 1'b0;
      nram_req_addr[mfu_rd_req_addr[5:3]]  = mfu_rd_req_addr[12:3];
    end else if (tfu_busy || vfu_busy) begin
      for (int b = 0; b < 4; b++) begin
        nram_req_valid[b] = 1'b1;
        nram_req_we[b]    = 1'b0;
        nram_req_addr[b]  = {tfu_row_cnt_q, b[2:0]};
      end
    end
  end

  // External Cluster Shared SRAM & GDRAM Routing
  wire mfu_sram_rd = mfu_rd_req_valid && (mfu_rd_req_space == mlu_pkg::MEM_SPACE_SRAM);
  wire mfu_sram_wr = mfu_wr_req_valid && (mfu_wr_req_space == mlu_pkg::MEM_SPACE_SRAM);
  assign sram_req_valid_o = mfu_sram_rd | mfu_sram_wr;
  assign sram_req_we_o    = mfu_sram_wr;
  assign sram_req_addr_o  = mfu_sram_wr ? mfu_wr_req_addr[13:3] : mfu_rd_req_addr[13:3];
  assign sram_req_wdata_o = mfu_wr_req_data;

  wire mfu_gdram_rd = mfu_rd_req_valid && (mfu_rd_req_space == mlu_pkg::MEM_SPACE_GDRAM);
  wire mfu_gdram_wr = mfu_wr_req_valid && (mfu_wr_req_space == mlu_pkg::MEM_SPACE_GDRAM);
  assign gdram_req_valid_o = mfu_gdram_rd | mfu_gdram_wr;
  assign gdram_req_we_o    = mfu_gdram_wr;
  assign gdram_req_addr_o  = mfu_gdram_wr ? mfu_wr_req_addr : mfu_rd_req_addr;
  assign gdram_req_wdata_o = mfu_wr_req_data;

  assign mfu_rd_resp_valid = mfu_nram_rd_pend_q | sram_resp_valid_i | gdram_resp_valid_i;
  assign mfu_rd_resp_data  = mfu_nram_rd_pend_q ? nram_resp_rdata[mfu_nram_rd_bank_q] :
                             (sram_resp_valid_i ? sram_resp_rdata_i : gdram_resp_rdata_i);

  assign core_sec_err_o = nram_sec_err | wram_sec_err;
  assign core_ded_err_o = nram_ded_err | wram_ded_err;
  assign core_busy_o    = (|icu_queue_busy) | (|eng_busy_vec) | icu_hazard_stall;

  wire _unused_ok = &{1'b0, CORE_ID, CLUSTER_ID, sram_req_grant_i, mpu_bcast_addr_i[10:9],
                      icu_hazard_stall_cnt, eng_clk_en, sram_slp, sram_dslp, sram_wake_ready,
                      sram_sleep_cycles, vfu_softmax_sum, vfu_softmax_max, vfu_absmax,
                      vfu_min_val, vfu_max_val, mfu_comp_bytes_rd, mfu_uncomp_bytes_wr,
                      nram_req_grant, nram_resp_valid, nram_conflict_stall, nram_conflict_cnt,
                      wram_tfu_weight_valid, llm_kv_dequant_out, llm_flash_req_valid,
                      llm_flash_page_addr, llm_total_kv_bytes_saved, llm_flash_ecc_err_cnt};

endmodule : mlu_ipu_core
