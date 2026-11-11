//      // verilator_coverage annotation
        // =============================================================================
        // File: uvm_tb/uvm_cambricon_llm_kv/mlu_cambricon_llm_kv_if.sv
        // Description: SystemVerilog Interface for UVM Suite 10:
        //              mlu_cambricon_llm_flash_kv (Cambricon-LLM MICRO 2024).
        // =============================================================================
        `ifndef MLU_CAMBRICON_LLM_KV_IF_SV
        `define MLU_CAMBRICON_LLM_KV_IF_SV
        
        import mlu_pkg::*;
        
        interface mlu_cambricon_llm_kv_if (
 000305   input logic clk_i
        );
%000001   logic              rst_ni;
 000300   logic              cmd_valid_i;
%000001   logic              cmd_ready_o;
%000001   mlu_opcode_e       opcode_i;
~000075   mlu_prec_e         prec_i;
~000150   logic [7:0]        cmd_tag_i;
 000150   logic [3:0]        kv_wr_slot_i;
~000150   logic [31:0]       flash_base_page_i;
~000219   logic [127:0]      kv_fp16_in_i;
%000001   logic              kv_rd_en_i;
 000150   logic [3:0]        kv_rd_addr_i;
 000451   logic [127:0]      kv_dequant_out_o;
~000053   logic [63:0]       kv_packed_out_o;
%000001   logic              flash_req_valid_o;
~000075   logic [31:0]       flash_page_addr_o;
 000012   logic              flash_ecc_clean_i;
~000300   logic [127:0]      draft_prob_i;
~000300   logic [127:0]      target_prob_i;
~000011   logic [7:0]        tree_mask_i;
~000061   logic [15:0]       accept_thresh_i;
%000001   logic              done_valid_o;
~000150   logic [7:0]        done_tag_o;
 000032   logic [7:0]        accepted_bitmap_o;
 000049   logic [3:0]        accepted_len_o;
 000049   logic [2:0]        bonus_token_idx_o;
~000033   logic [31:0]       total_accepted_tokens_o;
~000075   logic [31:0]       total_kv_bytes_saved_o;
%000003   logic [31:0]       flash_ecc_err_cnt_o;
        endinterface : mlu_cambricon_llm_kv_if
        
        `endif // MLU_CAMBRICON_LLM_KV_IF_SV
        
