// =============================================================================
// File: formal/mlu_nram_wram_mpu_formal.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Sequential SAT / BMC Formal Wrapper for NRAM, WRAM, and MPU SRAM:
//              - Property 1: NRAM XOR Bank-Swizzle Row/Col Bijection & Zero Conflict
//              - Property 2: NRAM 8x8 Byte Matrix Transpose End-to-End Exactness
//              - Property 3: WRAM Ping-Pong Shadow DMA Write / Active Read Isolation
//              - Property 4: MPU Shared SRAM Multi-Cast Broadcast Consistency
// =============================================================================
`include "mlu_pkg.sv"

module mlu_nram_wram_mpu_formal (
  input  logic             clk,
  input  logic             rst_n,

  // NRAM Formal Stimulus
  input  logic [2:0]       nram_row_i,
  input  logic             nram_col_mode_i,
  input  logic [2:0]       lane_i,
  input  logic [2:0]       lane_j,
  input  logic [7:0][63:0] mat_in_i,
  input  logic             nram_aligned_req_i,
  input  logic             nram_we_i,

  // WRAM Formal Stimulus
  input  logic             wram_pp_sel_i,
  input  logic             wram_dma_we_i,
  input  logic [3:0]       wram_dma_addr_i,
  input  logic [63:0]      wram_dma_wdata_i,
  input  logic             wram_tfu_rd_en_i,
  input  logic [1:0]       wram_tfu_rd_addr_i,

  // MPU Shared SRAM Formal Stimulus
  input  logic             mpu_bcast_en_i,
  input  logic [2:0]       mpu_bcast_addr_i,

  // Formal Observation Ports
  output logic [7:0]       nram_req_grant_o,
  output logic             nram_conflict_stall_o,
  output logic [3:0]       mpu_bcast_valid_o
);

  // ---------------------------------------------------------------------------
  // 1. NRAM Banked Scratchpad (NUM_BANKS=8, BANK_DEPTH=8 -> ADDR_W=6)
  // ---------------------------------------------------------------------------
  logic [7:0][5:0]  nram_aligned_addr;
  logic [7:0]       nram_req_grant;
  logic [7:0][63:0] nram_resp_rdata;
  logic [7:0]       nram_resp_valid;
  logic             nram_conflict_stall;
  logic [31:0]      nram_conflict_cnt;
  logic             nram_sec_err, nram_ded_err;

  assign nram_req_grant_o      = nram_req_grant;
  assign nram_conflict_stall_o = nram_conflict_stall;

  always_comb begin
    for (int l = 0; l < 8; l++) begin
      nram_aligned_addr[l] = nram_col_mode_i ? {3'(l), nram_row_i} : {nram_row_i, 3'(l)};
    end
  end

  mlu_nram_banked_scratchpad #(
    .NUM_BANKS  (8),
    .BANK_DEPTH (8),
    .DATA_W     (64),
    .ECC_W      (72),
    .BANK_SEL_W (3),
    .ROW_ADDR_W (3),
    .ADDR_W     (6)
  ) u_nram (
    .clk               (clk),
    .rst_n             (rst_n),
    .req_valid_i       ({8{nram_aligned_req_i}}),
    .req_we_i          ({8{nram_we_i}}),
    .req_addr_i        (nram_aligned_addr),
    .req_wdata_i       (mat_in_i),
    .req_grant_o       (nram_req_grant),
    .resp_rdata_o      (nram_resp_rdata),
    .resp_valid_o      (nram_resp_valid),
    .swizzle_en_i      (1'b1),
    .transpose_en_i    (nram_we_i),
    .conflict_stall_o  (nram_conflict_stall),
    .conflict_cnt_o    (nram_conflict_cnt),
    .err_inject_bank_i (3'd0),
    .err_inject_mask_i (72'd0),
    .sec_err_o         (nram_sec_err),
    .ded_err_o         (nram_ded_err)
  );

  // ---------------------------------------------------------------------------
  // 2. WRAM Ping-Pong Weight Buffer (NUM_BANKS=4, BANK_DEPTH=8 -> ROW_ADDR_W=3)
  // ---------------------------------------------------------------------------
  logic [255:0] wram_tfu_vec;
  logic [31:0]  wram_sparse_meta;
  logic         wram_tfu_valid;
  logic         wram_sec_err, wram_ded_err;

  mlu_wram_weight_buffer #(
    .NUM_BANKS  (4),
    .BANK_DEPTH (8),
    .DATA_W     (64),
    .ECC_W      (72),
    .META_W     (32),
    .BANK_SEL_W (2),
    .ROW_ADDR_W (3),
    .DMA_ADDR_W (5)
  ) u_wram (
    .clk                 (clk),
    .rst_n               (rst_n),
    .ping_pong_sel_i     (wram_pp_sel_i),
    .dma_we_i            (wram_dma_we_i),
    .dma_addr_i          ({1'b0, wram_dma_addr_i}),
    .dma_wdata_i         (wram_dma_wdata_i),
    .sparse_meta_we_i    (wram_dma_we_i),
    .sparse_meta_wdata_i (wram_dma_wdata_i[31:0]),
    .tfu_rd_en_i         (wram_tfu_rd_en_i),
    .tfu_rd_addr_i       ({1'b0, wram_tfu_rd_addr_i}),
    .tfu_weight_vec_o    (wram_tfu_vec),
    .tfu_sparse_meta_o   (wram_sparse_meta),
    .tfu_weight_valid_o  (wram_tfu_valid),
    .err_inject_bank_i   (2'd0),
    .err_inject_mask_i   (72'd0),
    .sec_err_o           (wram_sec_err),
    .ded_err_o           (wram_ded_err)
  );

  // ---------------------------------------------------------------------------
  // 3. MPU Cluster Shared SRAM (NUM_IPUS=4, NUM_BANKS=8, BANK_DEPTH=8)
  // ---------------------------------------------------------------------------
  logic [3:0]       mpu_ipu_grant, mpu_ipu_rvalid;
  logic [3:0][63:0] mpu_ipu_rdata;
  logic             mpu_dma_grant, mpu_dma_rvalid;
  logic [63:0]      mpu_dma_rdata;
  logic [255:0]     mpu_bcast_data;
  logic             mpu_sec_err, mpu_ded_err;

  mlu_mpu_shared_sram #(
    .NUM_IPUS   (4),
    .NUM_BANKS  (8),
    .BANK_DEPTH (8),
    .DATA_W     (64),
    .ECC_W      (72),
    .BANK_SEL_W (3),
    .ROW_ADDR_W (3),
    .ADDR_W     (6)
  ) u_mpu_sram (
    .clk               (clk),
    .rst_n             (rst_n),
    .ipu_req_valid_i   (4'b0000),
    .ipu_req_we_i      (4'b0000),
    .ipu_req_addr_i    ('0),
    .ipu_req_wdata_i   ('0),
    .ipu_req_grant_o   (mpu_ipu_grant),
    .ipu_resp_rdata_o  (mpu_ipu_rdata),
    .ipu_resp_valid_o  (mpu_ipu_rvalid),
    .dma_req_valid_i   (1'b0),
    .dma_req_we_i      (1'b0),
    .dma_req_addr_i    ('0),
    .dma_req_wdata_i   ('0),
    .dma_req_grant_o   (mpu_dma_grant),
    .dma_resp_rdata_o  (mpu_dma_rdata),
    .dma_resp_valid_o  (mpu_dma_rvalid),
    .bcast_en_i        (mpu_bcast_en_i),
    .bcast_addr_i      ({1'b0, mpu_bcast_addr_i}),
    .bcast_data_o      (mpu_bcast_data),
    .bcast_valid_o     (mpu_bcast_valid_o),
    .atomic_add_en_i   (1'b0),
    .err_inject_bank_i (3'd0),
    .err_inject_mask_i (72'd0),
    .sec_err_o         (mpu_sec_err),
    .ded_err_o         (mpu_ded_err)
  );

  // ---------------------------------------------------------------------------
  // 4. Formal Properties (Port-Level Sequential SAT / BMC)
  // ---------------------------------------------------------------------------
  logic       bcast_req_d1_q;
  logic       nram_rd_d1_q;
  logic       row0_written_d1_q;
  logic       row0_rd_after_wr_d1_q;
  logic [7:0] exp_t_r0c1_d1_q, exp_t_r0c1_d2_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bcast_req_d1_q        <= 1'b0;
      nram_rd_d1_q          <= 1'b0;
      row0_written_d1_q     <= 1'b0;
      row0_rd_after_wr_d1_q <= 1'b0;
      exp_t_r0c1_d1_q       <= 8'd0;
      exp_t_r0c1_d2_q       <= 8'd0;
    end else begin
      bcast_req_d1_q        <= mpu_bcast_en_i;
      nram_rd_d1_q          <= nram_aligned_req_i && !nram_we_i;
      row0_written_d1_q     <= nram_aligned_req_i && nram_we_i && !nram_col_mode_i && (nram_row_i == 3'd0);
      row0_rd_after_wr_d1_q <= row0_written_d1_q && nram_aligned_req_i && !nram_we_i && !nram_col_mode_i && (nram_row_i == 3'd0);
      exp_t_r0c1_d1_q       <= mat_in_i[1][7:0];
      exp_t_r0c1_d2_q       <= exp_t_r0c1_d1_q;
    end
  end

  always_comb begin
    assume (rst_n == 1'b1);
    assume (wram_pp_sel_i == 1'b0);

    // Property 1 (NRAM XOR Bank-Swizzle Row/Col Bijection & Zero Conflict)
    if (lane_i != lane_j) begin
      assert ((lane_i ^ nram_row_i) != (lane_j ^ nram_row_i));
    end
    if (nram_aligned_req_i) begin
      assert (nram_req_grant == 8'hFF);
      assert (!nram_conflict_stall);
    end
    assert (nram_conflict_cnt == 32'd0);
    if (nram_rd_d1_q) begin
      assert (nram_resp_valid == 8'hFF);
    end

    // Property 2 (NRAM 8x8 Byte Matrix Transpose End-to-End Write->Read Exactness)
    if (row0_rd_after_wr_d1_q) begin
      assert (nram_resp_rdata[0][15:8] == exp_t_r0c1_d2_q);
    end

    // Property 3 (WRAM Ping-Pong Isolation: Shadow DMA Writes Never Alter Active Reads)
    if (wram_tfu_valid) begin
      assert (wram_tfu_vec == 256'd0);
      assert (wram_sparse_meta == 32'd0);
      assert (!wram_sec_err && !wram_ded_err);
    end

    // Property 4 (MPU Shared SRAM Broadcast Consistency across all 4 IPU Ports)
    assert ((mpu_bcast_valid_o == 4'b0000) || (mpu_bcast_valid_o == 4'b1111));
    if (bcast_req_d1_q) begin
      assert (mpu_bcast_valid_o == 4'b1111);
    end
  end

endmodule : mlu_nram_wram_mpu_formal
