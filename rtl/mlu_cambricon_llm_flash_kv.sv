// =============================================================================
// File: rtl/mlu_cambricon_llm_flash_kv.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Cambricon-LLM (MICRO 2024) Flash-Assisted Per-Token Dynamic
//              Asymmetric INT4 / FP8 KV-Cache Quant-Pack & Speculative Decoding
//              Draft-Token Tree Verification Engine.
// =============================================================================
`ifndef MLU_CAMBRICON_LLM_FLASH_KV_SV
`define MLU_CAMBRICON_LLM_FLASH_KV_SV

`include "mlu_pkg.sv"

module mlu_cambricon_llm_flash_kv #(
  parameter int unsigned KV_RING_DEPTH = 16
) (
  input  logic              clk_i,
  input  logic              rst_ni,

  // BANG ISA Command Issue Interface (ENG_LLM_KV)
  input  logic              cmd_valid_i,
  output logic              cmd_ready_o,
  input  logic [5:0]        opcode_i,
  input  logic [2:0]        prec_i,
  input  logic [7:0]        cmd_tag_i,
  input  logic [3:0]        kv_wr_slot_i,
  input  logic [31:0]       flash_base_page_i,

  // Mode 1 (OP_LLM_KV_PACK): 8x16-bit KV Vector Input & On-the-Fly Dequant Read
  input  logic [127:0]      kv_fp16_in_i,
  input  logic              kv_rd_en_i,
  input  logic [3:0]        kv_rd_addr_i,
  output logic [127:0]      kv_dequant_out_o,
  output logic [63:0]       kv_packed_out_o,

  // Cambricon-LLM Dedicated In-Flash Channel Streaming Interface
  output logic              flash_req_valid_o,
  output logic [31:0]       flash_page_addr_o,
  input  logic              flash_ecc_clean_i,

  // Mode 2 (OP_LLM_SPEC_VERIFY): Speculative Draft-Token Tree Verification
  input  logic [127:0]      draft_prob_i,
  input  logic [127:0]      target_prob_i,
  input  logic [7:0]        tree_mask_i,
  input  logic [15:0]       accept_thresh_i,

  // Completion & Telemetry Outputs
  output logic              done_valid_o,
  output logic [7:0]        done_tag_o,
  output logic [7:0]        accepted_bitmap_o,
  output logic [3:0]        accepted_len_o,
  output logic [2:0]        bonus_token_idx_o,
  output logic [31:0]       total_accepted_tokens_o,
  output logic [31:0]       total_kv_bytes_saved_o,
  output logic [31:0]       flash_ecc_err_cnt_o
);

  assign cmd_ready_o = 1'b1;

  function automatic logic signed [16:0] sext17(input logic [15:0] v);
    sext17 = $signed({v[15], v});
  endfunction

  // Internal 16-Entry Compressed KV-Cache Ring Buffer (64-bit/entry = 2x Compression)
  logic [63:0]               kv_ring_mem  [0:KV_RING_DEPTH-1];
  logic [KV_RING_DEPTH-1:0]  kv_ring_fp8; // 0 = Asymmetric INT4, 1 = FP8-E4M3

  // ---------------------------------------------------------------------------
  // 1. Per-Token Dynamic Min/Max & Asymmetric INT4 / FP8-E4M3 Quantizer
  // ---------------------------------------------------------------------------
  logic signed [15:0] x_vec [0:7];
  always_comb begin
    for (int k = 0; k < 8; k++) begin
      x_vec[k] = $signed(kv_fp16_in_i[k*16 +: 16]);
    end
  end

  logic signed [15:0] min_l1 [0:3], max_l1 [0:3];
  logic signed [15:0] min_l2 [0:1], max_l2 [0:1];
  logic signed [15:0] min_val, max_val;
  logic [16:0]        span_u;
  logic [3:0]         shift_amt;
  logic [16:0]        diff_u   [0:7];
  logic [16:0]        scaled_u [0:7];
  logic [63:0]        packed_int4_comb;
  logic [63:0]        packed_fp8_comb;
  logic [63:0]        packed_kv_comb;

  always_comb begin
    for (int i = 0; i < 4; i++) begin
      min_l1[i] = (x_vec[2*i] < x_vec[2*i+1]) ? x_vec[2*i] : x_vec[2*i+1];
      max_l1[i] = (x_vec[2*i] > x_vec[2*i+1]) ? x_vec[2*i] : x_vec[2*i+1];
    end
    for (int i = 0; i < 2; i++) begin
      min_l2[i] = (min_l1[2*i] < min_l1[2*i+1]) ? min_l1[2*i] : min_l1[2*i+1];
      max_l2[i] = (max_l1[2*i] > max_l1[2*i+1]) ? max_l1[2*i] : max_l1[2*i+1];
    end
    min_val = (min_l2[0] < min_l2[1]) ? min_l2[0] : min_l2[1];
    max_val = (max_l2[0] > max_l2[1]) ? max_l2[0] : max_l2[1];

    span_u = $unsigned(sext17(max_val) - sext17(min_val));
    if      (span_u[16:15] != 2'b00) shift_amt = 4'd13;
    else if (span_u[14])             shift_amt = 4'd11;
    else if (span_u[13])             shift_amt = 4'd10;
    else if (span_u[12])             shift_amt = 4'd9;
    else if (span_u[11])             shift_amt = 4'd8;
    else if (span_u[10])             shift_amt = 4'd7;
    else if (span_u[9])              shift_amt = 4'd6;
    else if (span_u[8])              shift_amt = 4'd5;
    else if (span_u[7])              shift_amt = 4'd4;
    else if (span_u[6])              shift_amt = 4'd3;
    else if (span_u[5])              shift_amt = 4'd2;
    else if (span_u[4])              shift_amt = 4'd1;
    else                             shift_amt = 4'd0;

    packed_int4_comb[63:48] = {12'd0, shift_amt};
    packed_int4_comb[47:32] = min_val;
    for (int k = 0; k < 8; k++) begin
      diff_u[k]   = $unsigned(sext17(x_vec[k]) - sext17(min_val));
      scaled_u[k] = diff_u[k] >> shift_amt;
      packed_int4_comb[k*4 +: 4] = (scaled_u[k] > 17'd15) ? 4'd15 : scaled_u[k][3:0];
      packed_fp8_comb[k*8 +: 8]  = kv_fp16_in_i[k*16 + 8 +: 8];
    end

    packed_kv_comb = (prec_i == mlu_pkg::PREC_INT4) ? packed_int4_comb : packed_fp8_comb;
  end

  logic _unused_span_ok;
  assign _unused_span_ok = &{1'b0, span_u[3:0], scaled_u[0][16:4], scaled_u[1][16:4],
                             scaled_u[2][16:4], scaled_u[3][16:4], scaled_u[4][16:4],
                             scaled_u[5][16:4], scaled_u[6][16:4], scaled_u[7][16:4]};

  // ---------------------------------------------------------------------------
  // 2. On-the-Fly Dequantizer for FlashAttention KV Readback
  // ---------------------------------------------------------------------------
  logic [63:0] rd_entry;
  logic        rd_is_fp8;
  assign rd_entry  = kv_ring_mem[kv_rd_addr_i[$clog2(KV_RING_DEPTH)-1:0]];
  assign rd_is_fp8 = kv_ring_fp8[kv_rd_addr_i[$clog2(KV_RING_DEPTH)-1:0]];

  always_comb begin
    kv_dequant_out_o = 128'd0;
    if (kv_rd_en_i) begin
      for (int k = 0; k < 8; k++) begin
        if (rd_is_fp8) begin
          kv_dequant_out_o[k*16 +: 16] = {rd_entry[k*8 +: 8], 8'h00};
        end else begin
          kv_dequant_out_o[k*16 +: 16] = rd_entry[47:32] +
            ({12'd0, rd_entry[k*4 +: 4]} << rd_entry[51:48]);
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // 3. Mode 2: Hardware Speculative Decoding Draft-Token Tree Verifier
  // ---------------------------------------------------------------------------
  logic signed [16:0] lhs_s [0:7];
  logic signed [16:0] rhs_s [0:7];
  logic [7:0]         token_ok_comb;
  logic [7:0]         prefix_accept_comb;
  logic [3:0]         accepted_len_comb;
  logic [2:0]         bonus_idx_comb;

  always_comb begin
    for (int k = 0; k < 8; k++) begin
      lhs_s[k] = sext17(target_prob_i[k*16 +: 16]) + sext17(accept_thresh_i);
      rhs_s[k] = sext17(draft_prob_i[k*16 +: 16]);
      token_ok_comb[k] = tree_mask_i[k] && (lhs_s[k] >= rhs_s[k]);
    end
    prefix_accept_comb[0] = token_ok_comb[0];
    prefix_accept_comb[1] = &token_ok_comb[1:0];
    prefix_accept_comb[2] = &token_ok_comb[2:0];
    prefix_accept_comb[3] = &token_ok_comb[3:0];
    prefix_accept_comb[4] = &token_ok_comb[4:0];
    prefix_accept_comb[5] = &token_ok_comb[5:0];
    prefix_accept_comb[6] = &token_ok_comb[6:0];
    prefix_accept_comb[7] = &token_ok_comb[7:0];
    accepted_len_comb = {3'd0, prefix_accept_comb[0]} + {3'd0, prefix_accept_comb[1]} +
                        {3'd0, prefix_accept_comb[2]} + {3'd0, prefix_accept_comb[3]} +
                        {3'd0, prefix_accept_comb[4]} + {3'd0, prefix_accept_comb[5]} +
                        {3'd0, prefix_accept_comb[6]} + {3'd0, prefix_accept_comb[7]};
    bonus_idx_comb = (accepted_len_comb == 4'd8) ? 3'd7 : accepted_len_comb[2:0];
  end

  // ---------------------------------------------------------------------------
  // 4. Sequential Ring Buffer, Flash Streaming & Telemetry Update
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int i = 0; i < KV_RING_DEPTH; i++) begin
        kv_ring_mem[i] <= 64'd0;
      end
      kv_ring_fp8             <= '0;
      kv_packed_out_o         <= 64'd0;
      flash_req_valid_o       <= 1'b0;
      flash_page_addr_o       <= 32'd0;
      done_valid_o            <= 1'b0;
      done_tag_o              <= 8'd0;
      accepted_bitmap_o       <= 8'd0;
      accepted_len_o          <= 4'd0;
      bonus_token_idx_o       <= 3'd0;
      total_accepted_tokens_o <= 32'd0;
      total_kv_bytes_saved_o  <= 32'd0;
      flash_ecc_err_cnt_o     <= 32'd0;
    end else begin
      done_valid_o      <= 1'b0;
      flash_req_valid_o <= 1'b0;

      if (cmd_valid_i) begin
        done_valid_o <= 1'b1;
        done_tag_o   <= cmd_tag_i;

        if (opcode_i == mlu_pkg::OP_LLM_KV_PACK) begin
          kv_ring_mem[kv_wr_slot_i[$clog2(KV_RING_DEPTH)-1:0]] <= packed_kv_comb;
          kv_ring_fp8[kv_wr_slot_i[$clog2(KV_RING_DEPTH)-1:0]] <= (prec_i != mlu_pkg::PREC_INT4);
          kv_packed_out_o           <= packed_kv_comb;
          flash_req_valid_o         <= 1'b1;
          flash_page_addr_o         <= flash_base_page_i + {28'd0, kv_wr_slot_i};
          total_kv_bytes_saved_o    <= total_kv_bytes_saved_o + 32'd8;
          if (!flash_ecc_clean_i) begin
            flash_ecc_err_cnt_o <= flash_ecc_err_cnt_o + 32'd1;
          end
        end else if (opcode_i == mlu_pkg::OP_LLM_SPEC_VERIFY) begin
          accepted_bitmap_o       <= prefix_accept_comb;
          accepted_len_o          <= accepted_len_comb;
          bonus_token_idx_o       <= bonus_idx_comb;
          total_accepted_tokens_o <= total_accepted_tokens_o + {28'd0, accepted_len_comb};
        end
      end
    end
  end

endmodule : mlu_cambricon_llm_flash_kv
`endif // MLU_CAMBRICON_LLM_FLASH_KV_SV
