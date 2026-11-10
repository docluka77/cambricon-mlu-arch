// =============================================================================
// File: uvm_tb/uvm_cambricon_llm_kv/mlu_cambricon_llm_kv_if.sv
// Description: SystemVerilog Interface for UVM Suite 10:
//              mlu_cambricon_llm_flash_kv (Cambricon-LLM MICRO 2024).
// =============================================================================
`ifndef MLU_CAMBRICON_LLM_KV_IF_SV
`define MLU_CAMBRICON_LLM_KV_IF_SV

import mlu_pkg::*;

interface mlu_cambricon_llm_kv_if (
  input logic clk_i
);
  logic              rst_ni;
  logic              cmd_valid_i;
  logic              cmd_ready_o;
  mlu_opcode_e       opcode_i;
  mlu_prec_e         prec_i;
  logic [7:0]        cmd_tag_i;
  logic [3:0]        kv_wr_slot_i;
  logic [31:0]       flash_base_page_i;
  logic [127:0]      kv_fp16_in_i;
  logic              kv_rd_en_i;
  logic [3:0]        kv_rd_addr_i;
  logic [127:0]      kv_dequant_out_o;
  logic [63:0]       kv_packed_out_o;
  logic              flash_req_valid_o;
  logic [31:0]       flash_page_addr_o;
  logic              flash_ecc_clean_i;
  logic [127:0]      draft_prob_i;
  logic [127:0]      target_prob_i;
  logic [7:0]        tree_mask_i;
  logic [15:0]       accept_thresh_i;
  logic              done_valid_o;
  logic [7:0]        done_tag_o;
  logic [7:0]        accepted_bitmap_o;
  logic [3:0]        accepted_len_o;
  logic [2:0]        bonus_token_idx_o;
  logic [31:0]       total_accepted_tokens_o;
  logic [31:0]       total_kv_bytes_saved_o;
  logic [31:0]       flash_ecc_err_cnt_o;
endinterface : mlu_cambricon_llm_kv_if

`endif // MLU_CAMBRICON_LLM_KV_IF_SV
