// =============================================================================
// File: uvm_tb/tb_stage5_6_vfu_mfu.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Cycle-Accurate Verification Top Wrapper for Stage 5 (VFU/SFU)
//              and Stage 6 (MFU Asynchronous DMA + Hardware Decompressor).
// =============================================================================
`include "mlu_pkg.sv"

module tb_stage5_6_vfu_mfu (
  input  logic         clk_i,
  input  logic         rst_ni,

  // Stage 5: VFU/SFU Pipeline Interface
  input  logic         vfu_cmd_valid_i,
  output logic         vfu_cmd_ready_o,
  input  logic [127:0] vfu_cmd_inst_i,
  input  logic [127:0] vfu_vec_a_i,
  input  logic [127:0] vfu_vec_b_i,
  input  logic [127:0] vfu_cos_sin_lut_i,
  output logic [127:0] vfu_vec_out_o,
  output logic         vfu_vec_out_valid_o,
  output logic [31:0]  vfu_softmax_sum_o,
  output logic [15:0]  vfu_softmax_max_o,
  output logic [15:0]  vfu_absmax_o,
  output logic [15:0]  vfu_min_val_o,
  output logic [15:0]  vfu_max_val_o,
  output logic [15:0]  vfu_dyn_scale_o,
  output logic         vfu_busy_o,
  output logic         vfu_done_valid_o,
  output logic [7:0]   vfu_done_tag_o,

  // Stage 6: MFU DMA Engine Interface
  input  logic         mfu_cmd_valid_i,
  output logic         mfu_cmd_ready_o,
  input  logic [127:0] mfu_cmd_inst_i,
  input  logic [63:0]  mfu_idx_offset_i,
  input  logic [7:0]   mfu_decomp_bitmap_i,
  output logic         mfu_rd_req_valid_o,
  output logic [2:0]   mfu_rd_req_space_o,
  output logic [31:0]  mfu_rd_req_addr_o,
  input  logic         mfu_rd_resp_valid_i,
  input  logic [63:0]  mfu_rd_resp_data_i,
  output logic         mfu_wr_req_valid_o,
  output logic [2:0]   mfu_wr_req_space_o,
  output logic [31:0]  mfu_wr_req_addr_o,
  output logic [63:0]  mfu_wr_req_data_o,
  output logic         mfu_nram_transpose_mode_o,
  output logic         mfu_busy_o,
  output logic [31:0]  mfu_compressed_bytes_rd_o,
  output logic [31:0]  mfu_uncompressed_bytes_wr_o,
  output logic         mfu_done_valid_o,
  output logic [7:0]   mfu_done_tag_o
);

  mlu_vfu_sfu_pipe u_vfu_sfu_pipe (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .cmd_valid_i     (vfu_cmd_valid_i),
    .cmd_ready_o     (vfu_cmd_ready_o),
    .cmd_inst_i      (vfu_cmd_inst_i),
    .vec_a_i         (vfu_vec_a_i),
    .vec_b_i         (vfu_vec_b_i),
    .cos_sin_lut_i   (vfu_cos_sin_lut_i),
    .vec_out_o       (vfu_vec_out_o),
    .vec_out_valid_o (vfu_vec_out_valid_o),
    .softmax_sum_o   (vfu_softmax_sum_o),
    .softmax_max_o   (vfu_softmax_max_o),
    .absmax_o        (vfu_absmax_o),
    .min_val_o       (vfu_min_val_o),
    .max_val_o       (vfu_max_val_o),
    .dyn_scale_o     (vfu_dyn_scale_o),
    .vfu_busy_o      (vfu_busy_o),
    .done_valid_o    (vfu_done_valid_o),
    .done_tag_o      (vfu_done_tag_o)
  );

  mlu_mfu_dma_engine u_mfu_dma_engine (
    .clk_i                   (clk_i),
    .rst_ni                  (rst_ni),
    .cmd_valid_i             (mfu_cmd_valid_i),
    .cmd_ready_o             (mfu_cmd_ready_o),
    .cmd_inst_i              (mfu_cmd_inst_i),
    .idx_offset_i            (mfu_idx_offset_i),
    .decomp_bitmap_i         (mfu_decomp_bitmap_i),
    .rd_req_valid_o          (mfu_rd_req_valid_o),
    .rd_req_space_o          (mfu_rd_req_space_o),
    .rd_req_addr_o           (mfu_rd_req_addr_o),
    .rd_resp_valid_i         (mfu_rd_resp_valid_i),
    .rd_resp_data_i          (mfu_rd_resp_data_i),
    .wr_req_valid_o          (mfu_wr_req_valid_o),
    .wr_req_space_o          (mfu_wr_req_space_o),
    .wr_req_addr_o           (mfu_wr_req_addr_o),
    .wr_req_data_o           (mfu_wr_req_data_o),
    .nram_transpose_mode_o   (mfu_nram_transpose_mode_o),
    .mfu_busy_o              (mfu_busy_o),
    .compressed_bytes_rd_o   (mfu_compressed_bytes_rd_o),
    .uncompressed_bytes_wr_o (mfu_uncompressed_bytes_wr_o),
    .done_valid_o            (mfu_done_valid_o),
    .done_tag_o              (mfu_done_tag_o)
  );

endmodule : tb_stage5_6_vfu_mfu
