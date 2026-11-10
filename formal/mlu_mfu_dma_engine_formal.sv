// =============================================================================
// File: formal/mlu_mfu_dma_engine_formal.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Stage 10 Sequential SAT / BMC Formal Wrapper for mlu_mfu_dma_engine:
//              - Property 1: Cambricon-S/LLM Zero-Bitmap Decompression Exactness
//              - Property 2: Transpose Mode Isolation (OP_BANG_TRANSPOSE iff active)
//              - Property 3: 1D/2D Address Progression & Read-Before-Write Ordering
// =============================================================================
`include "mlu_pkg.sv"

module mlu_mfu_dma_engine_formal (
  input  logic         clk_i,
  input  logic         rst_ni,
  input  logic         cmd_valid_i,
  input  logic [127:0] cmd_inst_i,
  input  logic [63:0]  idx_offset_i,
  input  logic [7:0]   decomp_bitmap_i,
  input  logic         rd_resp_valid_i,
  input  logic [63:0]  rd_resp_data_i,
  output logic         cmd_ready_o,
  output logic         rd_req_valid_o,
  output logic [2:0]   rd_req_space_o,
  output logic [31:0]  rd_req_addr_o,
  output logic         wr_req_valid_o,
  output logic [2:0]   wr_req_space_o,
  output logic [31:0]  wr_req_addr_o,
  output logic [63:0]  wr_req_data_o,
  output logic         nram_transpose_mode_o,
  output logic         mfu_busy_o,
  output logic [31:0]  compressed_bytes_rd_o,
  output logic [31:0]  uncompressed_bytes_wr_o,
  output logic         done_valid_o,
  output logic [7:0]   done_tag_o
);

  logic init_done_q;
  always_ff @(posedge clk_i) begin
    init_done_q <= 1'b1;
  end
  always_comb begin
    if (!init_done_q) assume (!rst_ni);
    else              assume (rst_ni);
  end

  mlu_mfu_dma_engine u_dut (
    .clk_i                   (clk_i),
    .rst_ni                  (rst_ni),
    .cmd_valid_i             (cmd_valid_i),
    .cmd_ready_o             (cmd_ready_o),
    .cmd_inst_i              (cmd_inst_i),
    .idx_offset_i            (idx_offset_i),
    .decomp_bitmap_i         (decomp_bitmap_i),
    .rd_req_valid_o          (rd_req_valid_o),
    .rd_req_space_o          (rd_req_space_o),
    .rd_req_addr_o           (rd_req_addr_o),
    .rd_resp_valid_i         (rd_resp_valid_i),
    .rd_resp_data_i          (rd_resp_data_i),
    .wr_req_valid_o          (wr_req_valid_o),
    .wr_req_space_o          (wr_req_space_o),
    .wr_req_addr_o           (wr_req_addr_o),
    .wr_req_data_o           (wr_req_data_o),
    .nram_transpose_mode_o   (nram_transpose_mode_o),
    .mfu_busy_o              (mfu_busy_o),
    .compressed_bytes_rd_o   (compressed_bytes_rd_o),
    .uncompressed_bytes_wr_o (uncompressed_bytes_wr_o),
    .done_valid_o            (done_valid_o),
    .done_tag_o              (done_tag_o)
  );

  mlu_pkg::mlu_inst_t dec_cmd;
  assign dec_cmd = cmd_inst_i;

  // Shadow architectural tracking registers (zero hierarchical references)
  logic                 resp_received_for_beat_q;
  logic [7:0]           latched_bmp_q;
  logic [7:0]           expected_tag_q;
  mlu_pkg::mlu_opcode_e active_op_q;
  logic [31:0]          active_src_base_q;
  logic [31:0]          active_dst_base_q;
  logic [15:0]          active_beat_cnt_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      resp_received_for_beat_q <= 1'b0;
      latched_bmp_q            <= 8'd0;
      expected_tag_q           <= 8'd0;
      active_op_q              <= mlu_pkg::OP_NOP;
      active_src_base_q        <= 32'd0;
      active_dst_base_q        <= 32'd0;
      active_beat_cnt_q        <= 16'd0;
    end else begin
      if (cmd_valid_i && cmd_ready_o) begin
        resp_received_for_beat_q <= 1'b0;
        expected_tag_q           <= dec_cmd.tag_id;
        active_op_q              <= dec_cmd.opcode;
        active_src_base_q        <= dec_cmd.src0_addr;
        active_dst_base_q        <= dec_cmd.dst_addr;
        active_beat_cnt_q        <= 16'd0;
      end else if (mfu_busy_o && !wr_req_valid_o && rd_resp_valid_i) begin
        resp_received_for_beat_q <= 1'b1;
        latched_bmp_q            <= decomp_bitmap_i;
      end else if (wr_req_valid_o) begin
        resp_received_for_beat_q <= 1'b0;
        active_beat_cnt_q        <= active_beat_cnt_q + 16'd1;
      end
    end
  end

  always_comb begin
    if (rst_ni) begin
      if (wr_req_valid_o) begin
        assume (decomp_bitmap_i == latched_bmp_q);
      end

      // Property 1: Cambricon-S/LLM Zero-Bitmap Decompression Exactness
      if (wr_req_valid_o && (active_op_q == mlu_pkg::OP_BANG_DECOMP_DMA)) begin
        for (int b = 0; b < 8; b++) begin
          if (decomp_bitmap_i[b] == 1'b0) begin
            assert (wr_req_data_o[b*8 +: 8] == 8'h00);
          end
        end
      end
      assert (compressed_bytes_rd_o <= uncompressed_bytes_wr_o);

      // Property 2: Transpose Mode Isolation
      assert (nram_transpose_mode_o == (mfu_busy_o && (active_op_q == mlu_pkg::OP_BANG_TRANSPOSE)));
      if (!mfu_busy_o) begin
        assert (!nram_transpose_mode_o);
      end

      // Property 3: 1D/2D Address Progression & Request/Write Ordering
      assert (cmd_ready_o == !mfu_busy_o);
      assert (!(rd_req_valid_o && wr_req_valid_o));
      if (wr_req_valid_o) begin
        assert (resp_received_for_beat_q == 1'b1);
      end
      if (mfu_busy_o &&
          ((active_op_q == mlu_pkg::OP_BANG_MEMCPY_1D) ||
           (active_op_q == mlu_pkg::OP_BANG_DECOMP_DMA))) begin
        assert (rd_req_addr_o == (active_src_base_q + ({16'd0, active_beat_cnt_q} << 3)));
        assert (wr_req_addr_o == (active_dst_base_q + ({16'd0, active_beat_cnt_q} << 3)));
      end
      if (done_valid_o) begin
        assert (done_tag_o == expected_tag_q);
      end
    end
  end

endmodule : mlu_mfu_dma_engine_formal
