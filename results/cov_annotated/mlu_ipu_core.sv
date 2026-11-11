//      // verilator_coverage annotation
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
 000603   input  logic         clk_i,
%000001   input  logic         rst_ni,
        
          // Upstream BANG ISA Instruction Dispatch Stream
~000010   input  logic         inst_valid_i,
%000009   output logic         inst_ready_o,
~000011   input  logic [127:0] inst_i,
        
          // Ping-Pong WRAM Buffer Select & Decompression/Gather Config Inputs
%000001   input  logic         wram_ping_pong_sel_i,
%000001   input  logic [63:0]  mfu_idx_offset_i,
%000001   input  logic [7:0]   mfu_decomp_bitmap_i,
%000004   input  logic [127:0] vfu_cos_sin_lut_i,
        
          // Cluster Shared SRAM Port (to/from MPU Core)
%000000   output logic         sram_req_valid_o,
%000000   output logic         sram_req_we_o,
%000004   output logic [10:0]  sram_req_addr_o,
%000004   output logic [63:0]  sram_req_wdata_o,
%000000   input  logic         sram_req_grant_i,
%000000   input  logic         sram_resp_valid_i,
~000012   input  logic [63:0]  sram_resp_rdata_i,
        
          // MPU 1-to-4 Single-Cycle Multi-Cast Broadcast Input
%000002   input  logic         mpu_bcast_valid_i,
%000006   input  logic [10:0]  mpu_bcast_addr_i,
~000012   input  logic [255:0] mpu_bcast_data_i,
        
          // External HBM2e/HBM3e GDRAM Memory Interface
%000008   output logic         gdram_req_valid_o,
%000004   output logic         gdram_req_we_o,
%000004   output logic [31:0]  gdram_req_addr_o,
%000004   output logic [63:0]  gdram_req_wdata_o,
%000008   input  logic         gdram_resp_valid_i,
%000004   input  logic [63:0]  gdram_resp_rdata_i,
        
          // Cluster Hardware Union-Task Sync Barrier Handshake (OP_SYNC_CLUSTER)
%000003   output logic         cluster_sync_req_o,
%000002   input  logic         cluster_sync_ack_i,
        
          // ECC Fault Injection & Aggregated Core RAS Telemetry
%000000   input  logic [2:0]   err_inject_bank_i,
%000001   input  logic [71:0]  err_inject_mask_i,
%000001   output logic         core_sec_err_o,
%000001   output logic         core_ded_err_o,
        
          // Hardware Performance & Energy Counters
~000010   output logic         core_busy_o,
%000004   output logic [31:0]  inst_retired_cnt_o,
%000008   output logic [31:0]  active_mac_cycles_o,
~000250   output logic [31:0]  gated_saved_cycles_o,
%000006   output logic [31:0]  total_mac_ops_o,
%000002   output logic [31:0]  zero_skip_cnt_o
        );
        
          // ---------------------------------------------------------------------------
          // 1. Internal Interconnect Wires & Engine Control Signals
          // ---------------------------------------------------------------------------
%000003   logic [4:0]       eng_cmd_valid;
%000004   logic [4:0]       eng_cmd_ready;
~000011   logic [127:0]     eng_cmd_inst;
%000003   logic [4:0]       icu_dispatch_mask;
%000000   logic             pwr_gate_cfg_valid;
%000001   logic [7:0]       idle_threshold;
%000003   logic [4:0]       eng_done_valid;
%000001   logic [4:0][7:0]  eng_done_tag;
%000003   logic [4:0]       icu_queue_busy;
~000010   logic             icu_hazard_stall;
%000002   logic [31:0]      icu_hazard_stall_cnt;
          // PMU Clock Gate & Energy Wires
%000003   logic [4:0]       eng_busy_vec;
~000015   logic [2:0]       mem_active_vec;
%000004   logic [4:0]       eng_clk_en;
~000010   logic [2:0]       sram_slp;
%000009   logic [2:0]       sram_dslp;
~000010   logic [2:0]       sram_wake_ready;
~000253   logic [31:0]      sram_sleep_cycles;
        
          // TFU Wires
%000003   logic             tfu_busy;
%000003   logic             tfu_stream_valid;
%000003   logic             tfu_stream_ready;
~000023   logic [255:0]     tfu_nram_act;
%000004   logic [255:0]     tfu_wram_wt;
%000003   logic [31:0]      tfu_wram_sparse_meta;
%000001   logic [15:0]      tfu_quant_scale;
%000000   logic [7:0]       tfu_quant_zp;
%000006   logic [255:0]     tfu_result_data;
%000003   logic             tfu_result_valid;
        
          // VFU Wires
%000002   logic             vfu_busy;
~000017   logic [127:0]     vfu_vec_a;
~000012   logic [127:0]     vfu_vec_b;
%000004   logic [127:0]     vfu_vec_out;
%000002   logic             vfu_vec_out_valid;
%000001   logic [31:0]      vfu_softmax_sum;
%000001   logic [15:0]      vfu_softmax_max;
%000001   logic [15:0]      vfu_absmax;
%000001   logic [15:0]      vfu_min_val;
%000001   logic [15:0]      vfu_max_val;
%000001   logic [15:0]      vfu_dyn_scale;
        
          // MFU Wires
%000002   logic             mfu_busy;
%000008   logic             mfu_rd_req_valid;
%000001   logic [2:0]       mfu_rd_req_space;
%000004   logic [31:0]      mfu_rd_req_addr;
%000008   logic             mfu_rd_resp_valid;
%000004   logic [63:0]      mfu_rd_resp_data;
%000008   logic             mfu_wr_req_valid;
%000001   logic [2:0]       mfu_wr_req_space;
%000004   logic [31:0]      mfu_wr_req_addr;
%000004   logic [63:0]      mfu_wr_req_data;
%000001   logic             mfu_transpose_mode;
%000002   logic [31:0]      mfu_comp_bytes_rd;
%000002   logic [31:0]      mfu_uncomp_bytes_wr;
        
          // Cambricon-LLM Flash-KV & Speculative Decoding Engine Wires
%000000   logic [127:0]     llm_kv_dequant_out;
%000000   logic [63:0]      llm_kv_packed_out;
%000000   logic             llm_flash_req_valid;
%000000   logic [31:0]      llm_flash_page_addr;
%000000   logic [7:0]       llm_accepted_bitmap;
%000000   logic [3:0]       llm_accepted_len;
%000000   logic [2:0]       llm_bonus_token_idx;
%000000   logic [31:0]      llm_total_accepted_tokens;
%000000   logic [31:0]      llm_total_kv_bytes_saved;
%000000   logic [31:0]      llm_flash_ecc_err_cnt;
        
          // NRAM & WRAM Wires
~000012   logic [7:0]       nram_req_valid;
~000012   logic [7:0]       nram_req_we;
~000016   logic [7:0][9:0]  nram_req_addr;
          logic [7:0][63:0] nram_req_wdata;
~000012   logic [7:0]       nram_req_grant;
          logic [7:0][63:0] nram_resp_rdata;
%000005   logic [7:0]       nram_resp_valid;
%000000   logic             nram_conflict_stall;
%000000   logic [31:0]      nram_conflict_cnt;
%000001   logic             nram_sec_err;
%000001   logic             nram_ded_err;
        
%000006   logic             wram_dma_we;
~000010   logic [8:0]       wram_dma_addr;
%000007   logic [63:0]      wram_dma_wdata;
%000006   logic             wram_sparse_meta_we;
%000007   logic [31:0]      wram_sparse_meta_wdata;
%000003   logic             wram_tfu_rd_en;
%000006   logic [6:0]       wram_tfu_rd_addr;
%000004   logic [255:0]     wram_tfu_weight_vec;
%000003   logic [31:0]      wram_tfu_sparse_meta;
%000003   logic             wram_tfu_weight_valid;
%000001   logic             wram_sec_err;
%000001   logic             wram_ded_err;
        
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
%000000   logic col_busy_q, llm_busy_q;
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
%000000   logic [7:0] col_tag_q;
        
          assign eng_cmd_ready[3]  = ~col_busy_q;
          assign eng_done_valid[3] = col_busy_q;
          assign eng_done_tag[3]   = col_tag_q;
          assign llm_busy_q        = eng_done_valid[4];
        
 000603   always_ff @(posedge clk_i or negedge rst_ni) begin
~000600     if (!rst_ni) begin
%000003       col_busy_q <= 1'b0;
%000003       col_tag_q  <= 8'd0;
 000600     end else begin
 000600       col_busy_q <= eng_cmd_valid[3] & eng_cmd_ready[3];
~000600       if (eng_cmd_valid[3] && eng_cmd_ready[3]) begin
%000000         col_tag_q <= eng_cmd_inst[103:96];
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
%000006   logic [6:0] tfu_row_cnt_q;
%000004   logic [2:0] mfu_nram_rd_bank_q;
%000004   logic       mfu_nram_rd_pend_q;
        
 000603   always_ff @(posedge clk_i or negedge rst_ni) begin
~000600     if (!rst_ni) begin
%000003       tfu_row_cnt_q      <= 7'd0;
%000003       mfu_nram_rd_bank_q <= 3'd0;
%000003       mfu_nram_rd_pend_q <= 1'b0;
 000600     end else begin
%000003       if (eng_cmd_valid[0] && eng_cmd_ready[0]) begin
%000003         tfu_row_cnt_q <= eng_cmd_inst[38:32];
~000590       end else if (tfu_busy && tfu_stream_ready) begin
~000012         tfu_row_cnt_q <= tfu_row_cnt_q + 7'd1;
              end
 000600       mfu_nram_rd_pend_q <= mfu_rd_req_valid &&
                                    (mfu_rd_req_space == mlu_pkg::MEM_SPACE_NRAM);
~000592       if (mfu_rd_req_valid) begin
%000008         mfu_nram_rd_bank_q <= mfu_rd_req_addr[5:3];
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
 000604   always_comb begin
 004832     for (int b = 0; b < 8; b++) begin
 004832       nram_req_valid[b] = 1'b0;
 004832       nram_req_we[b]    = 1'b0;
 004832       nram_req_addr[b]  = {tfu_row_cnt_q, b[2:0]};
 004832       nram_req_wdata[b] = 64'd0;
            end
        
 000012     if (mpu_bcast_valid_i) begin
 000048       for (int b = 0; b < 4; b++) begin
 000048         nram_req_valid[b] = 1'b1;
 000048         nram_req_we[b]    = 1'b1;
 000048         nram_req_addr[b]  = {mpu_bcast_addr_i[6:0], b[2:0]};
 000048         nram_req_wdata[b] = mpu_bcast_data_i[b*64 +: 64];
              end
%000003     end else if (tfu_result_valid) begin
~000012       for (int b = 0; b < 4; b++) begin
~000012         nram_req_valid[b] = 1'b1;
~000012         nram_req_we[b]    = 1'b1;
~000012         nram_req_addr[b]  = {tfu_row_cnt_q, b[2:0]};
~000012         nram_req_wdata[b] = tfu_result_data[b*64 +: 64];
              end
%000002     end else if (vfu_vec_out_valid) begin
%000002       nram_req_valid[0] = 1'b1;
%000002       nram_req_we[0]    = 1'b1;
%000002       nram_req_wdata[0] = vfu_vec_out[63:0];
%000002       nram_req_valid[1] = 1'b1;
%000002       nram_req_we[1]    = 1'b1;
%000002       nram_req_wdata[1] = vfu_vec_out[127:64];
%000000     end else if (eng_done_valid[4]) begin
%000000       nram_req_valid[2] = 1'b1;
%000000       nram_req_we[2]    = 1'b1;
%000000       nram_req_wdata[2] = llm_kv_packed_out;
%000000       nram_req_valid[3] = 1'b1;
%000000       nram_req_we[3]    = 1'b1;
%000000       nram_req_wdata[3] = {llm_total_accepted_tokens[31:0], 17'd0,
%000000                            llm_bonus_token_idx, llm_accepted_len, llm_accepted_bitmap};
%000008     end else if (mfu_wr_req_valid && (mfu_wr_req_space == mlu_pkg::MEM_SPACE_NRAM)) begin
%000008       nram_req_valid[mfu_wr_req_addr[5:3]] = 1'b1;
%000008       nram_req_we[mfu_wr_req_addr[5:3]]    = 1'b1;
%000008       nram_req_addr[mfu_wr_req_addr[5:3]]  = mfu_wr_req_addr[12:3];
%000008       nram_req_wdata[mfu_wr_req_addr[5:3]] = mfu_wr_req_data;
%000004     end else if (mfu_rd_req_valid && (mfu_rd_req_space == mlu_pkg::MEM_SPACE_NRAM)) begin
%000004       nram_req_valid[mfu_rd_req_addr[5:3]] = 1'b1;
%000004       nram_req_we[mfu_rd_req_addr[5:3]]    = 1'b0;
%000004       nram_req_addr[mfu_rd_req_addr[5:3]]  = mfu_rd_req_addr[12:3];
 000572     end else if (tfu_busy || vfu_busy) begin
 000064       for (int b = 0; b < 4; b++) begin
 000064         nram_req_valid[b] = 1'b1;
 000064         nram_req_we[b]    = 1'b0;
 000064         nram_req_addr[b]  = {tfu_row_cnt_q, b[2:0]};
              end
            end
          end
        
          // External Cluster Shared SRAM & GDRAM Routing
%000000   wire mfu_sram_rd = mfu_rd_req_valid && (mfu_rd_req_space == mlu_pkg::MEM_SPACE_SRAM);
%000000   wire mfu_sram_wr = mfu_wr_req_valid && (mfu_wr_req_space == mlu_pkg::MEM_SPACE_SRAM);
          assign sram_req_valid_o = mfu_sram_rd | mfu_sram_wr;
          assign sram_req_we_o    = mfu_sram_wr;
          assign sram_req_addr_o  = mfu_sram_wr ? mfu_wr_req_addr[13:3] : mfu_rd_req_addr[13:3];
          assign sram_req_wdata_o = mfu_wr_req_data;
        
%000008   wire mfu_gdram_rd = mfu_rd_req_valid && (mfu_rd_req_space == mlu_pkg::MEM_SPACE_GDRAM);
%000004   wire mfu_gdram_wr = mfu_wr_req_valid && (mfu_wr_req_space == mlu_pkg::MEM_SPACE_GDRAM);
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
        
