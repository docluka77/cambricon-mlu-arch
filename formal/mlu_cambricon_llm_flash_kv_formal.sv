// =============================================================================
// File: formal/mlu_cambricon_llm_flash_kv_formal.sv
// Description: Yosys 0.60 Sequential SAT Formal Verification Harness for
//              mlu_cambricon_llm_flash_kv (Cambricon-LLM MICRO 2024).
// =============================================================================
`include "mlu_pkg.sv"

module mlu_cambricon_llm_flash_kv_formal (
  input  logic         clk_i,
  input  logic         cmd_valid_i,
  input  logic         mode_spec_i,
  input  logic         prec_fp8_i,
  input  logic [7:0]   cmd_tag_i,
  input  logic [3:0]   kv_wr_slot_i,
  input  logic [31:0]  flash_base_page_i,
  input  logic [127:0] kv_fp16_in_i,
  input  logic         kv_rd_en_i,
  input  logic [3:0]   kv_rd_addr_i,
  input  logic         flash_ecc_clean_i,
  input  logic [127:0] draft_prob_i,
  input  logic [127:0] target_prob_i,
  input  logic [7:0]   tree_mask_i,
  input  logic [15:0]  accept_thresh_i
);

  function automatic logic signed [16:0] sext17(input logic [15:0] v);
    sext17 = $signed({v[15], v});
  endfunction

  logic [1:0] init_cnt = 2'd0;
  logic       rst_ni;
  assign rst_ni = (init_cnt >= 2'd1);

  always_ff @(posedge clk_i) begin
    if (init_cnt < 2'd3) init_cnt <= init_cnt + 2'd1;
  end

  logic [5:0] opcode_w;
  logic [2:0] prec_w;
  assign opcode_w = mode_spec_i ? mlu_pkg::OP_LLM_SPEC_VERIFY : mlu_pkg::OP_LLM_KV_PACK;
  assign prec_w   = prec_fp8_i  ? mlu_pkg::PREC_FP8_E4M3      : mlu_pkg::PREC_INT4;

  logic         cmd_ready_o;
  logic [127:0] kv_dequant_out_o;
  logic [63:0]  kv_packed_out_o;
  logic         flash_req_valid_o;
  logic [31:0]  flash_page_addr_o;
  logic         done_valid_o;
  logic [7:0]   done_tag_o;
  logic [7:0]   accepted_bitmap_o;
  logic [3:0]   accepted_len_o;
  logic [2:0]   bonus_token_idx_o;
  logic [31:0]  total_accepted_tokens_o;
  logic [31:0]  total_kv_bytes_saved_o;
  logic [31:0]  flash_ecc_err_cnt_o;

  mlu_cambricon_llm_flash_kv #(
    .KV_RING_DEPTH(4)
  ) u_dut (
    .clk_i                   (clk_i),
    .rst_ni                  (rst_ni),
    .cmd_valid_i             (cmd_valid_i),
    .cmd_ready_o             (cmd_ready_o),
    .opcode_i                (opcode_w),
    .prec_i                  (prec_w),
    .cmd_tag_i               (cmd_tag_i),
    .kv_wr_slot_i            ({2'b00, kv_wr_slot_i[1:0]}),
    .flash_base_page_i       (flash_base_page_i),
    .kv_fp16_in_i            (kv_fp16_in_i),
    .kv_rd_en_i              (kv_rd_en_i),
    .kv_rd_addr_i            ({2'b00, kv_rd_addr_i[1:0]}),
    .kv_dequant_out_o        (kv_dequant_out_o),
    .kv_packed_out_o         (kv_packed_out_o),
    .flash_req_valid_o       (flash_req_valid_o),
    .flash_page_addr_o       (flash_page_addr_o),
    .flash_ecc_clean_i       (flash_ecc_clean_i),
    .draft_prob_i            (draft_prob_i),
    .target_prob_i           (target_prob_i),
    .tree_mask_i             (tree_mask_i),
    .accept_thresh_i         (accept_thresh_i),
    .done_valid_o            (done_valid_o),
    .done_tag_o              (done_tag_o),
    .accepted_bitmap_o       (accepted_bitmap_o),
    .accepted_len_o          (accepted_len_o),
    .bonus_token_idx_o       (bonus_token_idx_o),
    .total_accepted_tokens_o (total_accepted_tokens_o),
    .total_kv_bytes_saved_o  (total_kv_bytes_saved_o),
    .flash_ecc_err_cnt_o     (flash_ecc_err_cnt_o)
  );

  logic        q_cmd_valid  = 1'b0;
  logic        q_mode_spec  = 1'b0;
  logic        q_prec_fp8   = 1'b0;
  logic [7:0]  q_cmd_tag    = 8'd0;
  logic        q_tok0_rej   = 1'b0;
  logic        q_all8_acc   = 1'b0;
  logic [31:0] q_saved_prev = 32'd0;

  logic tok0_rej_comb;
  logic all8_acc_comb;

  always_comb begin
    tok0_rej_comb = (!tree_mask_i[0]) ||
      ((sext17(target_prob_i[15:0]) + sext17(accept_thresh_i)) <
        sext17(draft_prob_i[15:0]));

    all8_acc_comb = (tree_mask_i == 8'hFF) && ($signed(accept_thresh_i) >= $signed(16'd0));
    for (int k = 0; k < 8; k++) begin
      if ($signed(target_prob_i[k*16 +: 16]) < $signed(draft_prob_i[k*16 +: 16])) begin
        all8_acc_comb = 1'b0;
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      q_cmd_valid  <= 1'b0;
      q_mode_spec  <= 1'b0;
      q_prec_fp8   <= 1'b0;
      q_cmd_tag    <= 8'd0;
      q_tok0_rej   <= 1'b0;
      q_all8_acc   <= 1'b0;
      q_saved_prev <= 32'd0;
    end else begin
      q_cmd_valid  <= cmd_valid_i;
      q_mode_spec  <= mode_spec_i;
      q_prec_fp8   <= prec_fp8_i;
      q_cmd_tag    <= cmd_tag_i;
      q_tok0_rej   <= tok0_rej_comb;
      q_all8_acc   <= all8_acc_comb;
      q_saved_prev <= total_kv_bytes_saved_o;

      assert (cmd_ready_o == 1'b1);
      assert (accepted_len_o <= 4'd8);
      assert ((accepted_bitmap_o & (accepted_bitmap_o + 8'd1)) == 8'd0);

      if (q_cmd_valid) begin
        assert (done_valid_o == 1'b1);
        assert (done_tag_o == q_cmd_tag);

        if (q_mode_spec) begin
          if (q_tok0_rej) begin
            assert (accepted_len_o == 4'd0);
            assert (accepted_bitmap_o == 8'h00);
          end
          if (q_all8_acc) begin
            assert (accepted_bitmap_o == 8'hFF);
            assert (accepted_len_o == 4'd8);
          end
        end else begin
          if (!q_prec_fp8) begin
            assert (total_kv_bytes_saved_o == (q_saved_prev + 32'd8));
          end
          assert (flash_req_valid_o == 1'b1);
        end
      end else begin
        assert (done_valid_o == 1'b0);
      end
    end
  end

endmodule : mlu_cambricon_llm_flash_kv_formal
