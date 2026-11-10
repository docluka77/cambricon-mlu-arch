// =============================================================================
// File: uvm_tb/uvm_cambricon_llm_kv/tb_cambricon_llm_kv_top.sv
// Description: Top-level UVM Testbench for Suite 10:
//              mlu_cambricon_llm_flash_kv (Cambricon-LLM MICRO 2024).
// =============================================================================
`timescale 1ns/1ps
`include "uvm_macros.svh"

module tb_cambricon_llm_kv_top;
  import uvm_pkg::*;
  import mlu_pkg::*;
  import mlu_cambricon_llm_kv_uvm_pkg::*;

  logic clk = 1'b0;
  always #5ns clk = ~clk;

  mlu_cambricon_llm_kv_if vif (.clk_i(clk));

  mlu_cambricon_llm_flash_kv #(
    .KV_RING_DEPTH(16)
  ) u_dut (
    .clk_i                   (clk),
    .rst_ni                  (vif.rst_ni),
    .cmd_valid_i             (vif.cmd_valid_i),
    .cmd_ready_o             (vif.cmd_ready_o),
    .opcode_i                (vif.opcode_i),
    .prec_i                  (vif.prec_i),
    .cmd_tag_i               (vif.cmd_tag_i),
    .kv_wr_slot_i            (vif.kv_wr_slot_i),
    .flash_base_page_i       (vif.flash_base_page_i),
    .kv_fp16_in_i            (vif.kv_fp16_in_i),
    .kv_rd_en_i              (vif.kv_rd_en_i),
    .kv_rd_addr_i            (vif.kv_rd_addr_i),
    .kv_dequant_out_o        (vif.kv_dequant_out_o),
    .kv_packed_out_o         (vif.kv_packed_out_o),
    .flash_req_valid_o       (vif.flash_req_valid_o),
    .flash_page_addr_o       (vif.flash_page_addr_o),
    .flash_ecc_clean_i       (vif.flash_ecc_clean_i),
    .draft_prob_i            (vif.draft_prob_i),
    .target_prob_i           (vif.target_prob_i),
    .tree_mask_i             (vif.tree_mask_i),
    .accept_thresh_i         (vif.accept_thresh_i),
    .done_valid_o            (vif.done_valid_o),
    .done_tag_o              (vif.done_tag_o),
    .accepted_bitmap_o       (vif.accepted_bitmap_o),
    .accepted_len_o          (vif.accepted_len_o),
    .bonus_token_idx_o       (vif.bonus_token_idx_o),
    .total_accepted_tokens_o (vif.total_accepted_tokens_o),
    .total_kv_bytes_saved_o  (vif.total_kv_bytes_saved_o),
    .flash_ecc_err_cnt_o     (vif.flash_ecc_err_cnt_o)
  );

  initial begin
    uvm_config_db#(virtual mlu_cambricon_llm_kv_if)::set(null, "*", "vif", vif);
    run_test("mlu_cambricon_llm_kv_test");
  end

endmodule : tb_cambricon_llm_kv_top
