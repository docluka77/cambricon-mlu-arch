//      // verilator_coverage annotation
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
 000305   input  logic              clk_i,
%000001   input  logic              rst_ni,
        
          // BANG ISA Command Issue Interface (ENG_LLM_KV)
 000300   input  logic              cmd_valid_i,
%000001   output logic              cmd_ready_o,
%000001   input  logic [5:0]        opcode_i,
~000075   input  logic [2:0]        prec_i,
~000150   input  logic [7:0]        cmd_tag_i,
 000150   input  logic [3:0]        kv_wr_slot_i,
~000150   input  logic [31:0]       flash_base_page_i,
        
          // Mode 1 (OP_LLM_KV_PACK): 8x16-bit KV Vector Input & On-the-Fly Dequant Read
~000292   input  logic [127:0]      kv_fp16_in_i,
%000001   input  logic              kv_rd_en_i,
 000150   input  logic [3:0]        kv_rd_addr_i,
 000504   output logic [127:0]      kv_dequant_out_o,
~000057   output logic [63:0]       kv_packed_out_o,
        
          // Cambricon-LLM Dedicated In-Flash Channel Streaming Interface
%000001   output logic              flash_req_valid_o,
~000075   output logic [31:0]       flash_page_addr_o,
 000012   input  logic              flash_ecc_clean_i,
        
          // Mode 2 (OP_LLM_SPEC_VERIFY): Speculative Draft-Token Tree Verification
~000300   input  logic [127:0]      draft_prob_i,
~000300   input  logic [127:0]      target_prob_i,
~000011   input  logic [7:0]        tree_mask_i,
~000061   input  logic [15:0]       accept_thresh_i,
        
          // Completion & Telemetry Outputs
%000001   output logic              done_valid_o,
~000150   output logic [7:0]        done_tag_o,
 000032   output logic [7:0]        accepted_bitmap_o,
 000049   output logic [3:0]        accepted_len_o,
 000049   output logic [2:0]        bonus_token_idx_o,
~000033   output logic [31:0]       total_accepted_tokens_o,
~000075   output logic [31:0]       total_kv_bytes_saved_o,
%000003   output logic [31:0]       flash_ecc_err_cnt_o
        );
        
          assign cmd_ready_o = 1'b1;
        
 005478   function automatic logic signed [16:0] sext17(input logic [15:0] v);
 005478     sext17 = $signed({v[15], v});
          endfunction
        
          // Internal 16-Entry Compressed KV-Cache Ring Buffer (64-bit/entry = 2x Compression)
          logic [63:0]               kv_ring_mem  [0:KV_RING_DEPTH-1];
%000001   logic [KV_RING_DEPTH-1:0]  kv_ring_fp8; // 0 = Asymmetric INT4, 1 = FP8-E4M3
        
          // ---------------------------------------------------------------------------
          // 1. Per-Token Dynamic Min/Max & Asymmetric INT4 / FP8-E4M3 Quantizer
          // ---------------------------------------------------------------------------
~000073   logic signed [15:0] x_vec [0:7];
%000001   always_comb begin
%000008     for (int k = 0; k < 8; k++) begin
%000008       x_vec[k] = $signed(kv_fp16_in_i[k*16 +: 16]);
            end
          end
        
~000071   logic signed [15:0] min_l1 [0:3], max_l1 [0:3];
~000069   logic signed [15:0] min_l2 [0:1], max_l2 [0:1];
~000066   logic signed [15:0] min_val, max_val;
~000046   logic [16:0]        span_u;
%000003   logic [3:0]         shift_amt;
~000054   logic [16:0]        diff_u   [0:7];
~000041   logic [16:0]        scaled_u [0:7];
~000066   logic [63:0]        packed_int4_comb;
~000065   logic [63:0]        packed_fp8_comb;
~000057   logic [63:0]        packed_kv_comb;
        
 000303   always_comb begin
 001212     for (int i = 0; i < 4; i++) begin
 001212       min_l1[i] = (x_vec[2*i] < x_vec[2*i+1]) ? x_vec[2*i] : x_vec[2*i+1];
 001212       max_l1[i] = (x_vec[2*i] > x_vec[2*i+1]) ? x_vec[2*i] : x_vec[2*i+1];
            end
 000606     for (int i = 0; i < 2; i++) begin
 000606       min_l2[i] = (min_l1[2*i] < min_l1[2*i+1]) ? min_l1[2*i] : min_l1[2*i+1];
 000606       max_l2[i] = (max_l1[2*i] > max_l1[2*i+1]) ? max_l1[2*i] : max_l1[2*i+1];
            end
 000303     min_val = (min_l2[0] < min_l2[1]) ? min_l2[0] : min_l2[1];
 000303     max_val = (max_l2[0] > max_l2[1]) ? max_l2[0] : max_l2[1];
        
 000303     span_u = $unsigned(sext17(max_val) - sext17(min_val));
%000000     if      (span_u[16:15] != 2'b00) shift_amt = 4'd13;
 000222     else if (span_u[14])             shift_amt = 4'd11;
 000038     else if (span_u[13])             shift_amt = 4'd10;
%000000     else if (span_u[12])             shift_amt = 4'd9;
%000000     else if (span_u[11])             shift_amt = 4'd8;
%000000     else if (span_u[10])             shift_amt = 4'd7;
%000000     else if (span_u[9])              shift_amt = 4'd6;
%000000     else if (span_u[8])              shift_amt = 4'd5;
%000000     else if (span_u[7])              shift_amt = 4'd4;
%000000     else if (span_u[6])              shift_amt = 4'd3;
%000000     else if (span_u[5])              shift_amt = 4'd2;
~000043     else if (span_u[4])              shift_amt = 4'd1;
 000043     else                             shift_amt = 4'd0;
        
 000303     packed_int4_comb[63:48] = {12'd0, shift_amt};
 000303     packed_int4_comb[47:32] = min_val;
 002424     for (int k = 0; k < 8; k++) begin
 002424       diff_u[k]   = $unsigned(sext17(x_vec[k]) - sext17(min_val));
 002424       scaled_u[k] = diff_u[k] >> shift_amt;
 002424       packed_int4_comb[k*4 +: 4] = (scaled_u[k] > 17'd15) ? 4'd15 : scaled_u[k][3:0];
 002424       packed_fp8_comb[k*8 +: 8]  = kv_fp16_in_i[k*16 + 8 +: 8];
            end
        
 000303     packed_kv_comb = (prec_i == mlu_pkg::PREC_INT4) ? packed_int4_comb : packed_fp8_comb;
          end
        
          logic _unused_span_ok;
          assign _unused_span_ok = &{1'b0, span_u[3:0], scaled_u[0][16:4], scaled_u[1][16:4],
                                     scaled_u[2][16:4], scaled_u[3][16:4], scaled_u[4][16:4],
                                     scaled_u[5][16:4], scaled_u[6][16:4], scaled_u[7][16:4]};
        
          // ---------------------------------------------------------------------------
          // 2. On-the-Fly Dequantizer for FlashAttention KV Readback
          // ---------------------------------------------------------------------------
 000152   logic [63:0] rd_entry;
 000150   logic        rd_is_fp8;
          assign rd_entry  = kv_ring_mem[kv_rd_addr_i[$clog2(KV_RING_DEPTH)-1:0]];
          assign rd_is_fp8 = kv_ring_fp8[kv_rd_addr_i[$clog2(KV_RING_DEPTH)-1:0]];
        
 001206   always_comb begin
 001206     kv_dequant_out_o = 128'd0;
~001202     if (kv_rd_en_i) begin
 009616       for (int k = 0; k < 8; k++) begin
 004992         if (rd_is_fp8) begin
 004624           kv_dequant_out_o[k*16 +: 16] = {rd_entry[k*8 +: 8], 8'h00};
 004992         end else begin
 004992           kv_dequant_out_o[k*16 +: 16] = rd_entry[47:32] +
 004992             ({12'd0, rd_entry[k*4 +: 4]} << rd_entry[51:48]);
                end
              end
            end
          end
        
          // ---------------------------------------------------------------------------
          // 3. Mode 2: Hardware Speculative Decoding Draft-Token Tree Verifier
          // ---------------------------------------------------------------------------
~000075   logic signed [16:0] lhs_s [0:7];
~000075   logic signed [16:0] rhs_s [0:7];
 000032   logic [7:0]         token_ok_comb;
 000032   logic [7:0]         prefix_accept_comb;
 000049   logic [3:0]         accepted_len_comb;
 000050   logic [2:0]         bonus_idx_comb;
        
%000001   always_comb begin
%000008     for (int k = 0; k < 8; k++) begin
%000008       lhs_s[k] = sext17(target_prob_i[k*16 +: 16]) + sext17(accept_thresh_i);
%000008       rhs_s[k] = sext17(draft_prob_i[k*16 +: 16]);
%000008       token_ok_comb[k] = tree_mask_i[k] && (lhs_s[k] >= rhs_s[k]);
            end
%000001     prefix_accept_comb[0] = token_ok_comb[0];
%000001     prefix_accept_comb[1] = &token_ok_comb[1:0];
%000001     prefix_accept_comb[2] = &token_ok_comb[2:0];
%000001     prefix_accept_comb[3] = &token_ok_comb[3:0];
%000001     prefix_accept_comb[4] = &token_ok_comb[4:0];
%000001     prefix_accept_comb[5] = &token_ok_comb[5:0];
%000001     prefix_accept_comb[6] = &token_ok_comb[6:0];
%000001     prefix_accept_comb[7] = &token_ok_comb[7:0];
%000001     accepted_len_comb = {3'd0, prefix_accept_comb[0]} + {3'd0, prefix_accept_comb[1]} +
%000001                         {3'd0, prefix_accept_comb[2]} + {3'd0, prefix_accept_comb[3]} +
%000001                         {3'd0, prefix_accept_comb[4]} + {3'd0, prefix_accept_comb[5]} +
%000001                         {3'd0, prefix_accept_comb[6]} + {3'd0, prefix_accept_comb[7]};
%000001     bonus_idx_comb = (accepted_len_comb == 4'd8) ? 3'd7 : accepted_len_comb[2:0];
          end
        
          // ---------------------------------------------------------------------------
          // 4. Sequential Ring Buffer, Flash Streaming & Telemetry Update
          // ---------------------------------------------------------------------------
 000305   always_ff @(posedge clk_i or negedge rst_ni) begin
~000302     if (!rst_ni) begin
~000048       for (int i = 0; i < KV_RING_DEPTH; i++) begin
 000048         kv_ring_mem[i] <= 64'd0;
              end
%000003       kv_ring_fp8             <= '0;
%000003       kv_packed_out_o         <= 64'd0;
%000003       flash_req_valid_o       <= 1'b0;
%000003       flash_page_addr_o       <= 32'd0;
%000003       done_valid_o            <= 1'b0;
%000003       done_tag_o              <= 8'd0;
%000003       accepted_bitmap_o       <= 8'd0;
%000003       accepted_len_o          <= 4'd0;
%000003       bonus_token_idx_o       <= 3'd0;
%000003       total_accepted_tokens_o <= 32'd0;
%000003       total_kv_bytes_saved_o  <= 32'd0;
%000003       flash_ecc_err_cnt_o     <= 32'd0;
 000302     end else begin
 000302       done_valid_o      <= 1'b0;
 000302       flash_req_valid_o <= 1'b0;
        
~000300       if (cmd_valid_i) begin
 000300         done_valid_o <= 1'b1;
 000300         done_tag_o   <= cmd_tag_i;
        
 000150         if (opcode_i == mlu_pkg::OP_LLM_KV_PACK) begin
 000150           kv_ring_mem[kv_wr_slot_i[$clog2(KV_RING_DEPTH)-1:0]] <= packed_kv_comb;
 000150           kv_ring_fp8[kv_wr_slot_i[$clog2(KV_RING_DEPTH)-1:0]] <= (prec_i != mlu_pkg::PREC_INT4);
 000150           kv_packed_out_o           <= packed_kv_comb;
 000150           flash_req_valid_o         <= 1'b1;
 000150           flash_page_addr_o         <= flash_base_page_i + {28'd0, kv_wr_slot_i};
 000150           total_kv_bytes_saved_o    <= total_kv_bytes_saved_o + 32'd8;
~000144           if (!flash_ecc_clean_i) begin
%000006             flash_ecc_err_cnt_o <= flash_ecc_err_cnt_o + 32'd1;
                  end
~000150         end else if (opcode_i == mlu_pkg::OP_LLM_SPEC_VERIFY) begin
 000150           accepted_bitmap_o       <= prefix_accept_comb;
 000150           accepted_len_o          <= accepted_len_comb;
 000150           bonus_token_idx_o       <= bonus_idx_comb;
 000150           total_accepted_tokens_o <= total_accepted_tokens_o + {28'd0, accepted_len_comb};
                end
              end
            end
          end
        
        endmodule : mlu_cambricon_llm_flash_kv
        `endif // MLU_CAMBRICON_LLM_FLASH_KV_SV
        
