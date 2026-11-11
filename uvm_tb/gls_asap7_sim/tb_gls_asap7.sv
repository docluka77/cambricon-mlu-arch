// =============================================================================
// File: uvm_tb/gls_asap7_sim/tb_gls_asap7.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06)
// Description: Stage 22 — Post-Synthesis ASAP7 7nm Gate-Level Netlist Simulation
//              (GLS) Lockstep Co-Verification & Toggle Activity Harness
// =============================================================================
`include "mlu_pkg.sv"

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off PINCONNECTEMPTY */

module tb_gls_asap7 (
  input logic clk_i,
  input logic rst_ni
);
  import mlu_pkg::*;

  int unsigned cyc_cnt;
  logic [63:0] lfsr_q;
  int unsigned chk_cnt [0:7];
  int unsigned err_cnt [0:7];
  int unsigned total_checks;
  int unsigned total_errors;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cyc_cnt <= 32'd0;
      lfsr_q  <= 64'hCAFE_BABE_1357_9BDF;
    end else begin
      cyc_cnt <= cyc_cnt + 32'd1;
      lfsr_q  <= {lfsr_q[62:0], lfsr_q[63] ^ lfsr_q[61] ^ lfsr_q[60] ^ lfsr_q[58]};
    end
  end

  // ===========================================================================
  // 1. mlu_sram_secded_ecc (Golden RTL vs. ASAP7 7nm Gate-Level Netlist)
  // ===========================================================================
  logic [63:0] ecc_data_i;
  logic [71:0] ecc_err_mask_i;
  logic [71:0] rtl_ecc_cw_o, gls_ecc_cw_o;
  logic [63:0] rtl_ecc_data_o, gls_ecc_data_o;
  logic [7:0]  rtl_ecc_syn_o, gls_ecc_syn_o;
  logic        rtl_ecc_sec_o, gls_ecc_sec_o;
  logic        rtl_ecc_ded_o, gls_ecc_ded_o;

  assign ecc_data_i     = lfsr_q ^ {32'hA5A5_5A5A, cyc_cnt};
  assign ecc_err_mask_i = (cyc_cnt[2:0] == 3'd1) ? (72'd1 << (cyc_cnt[8:3] % 72)) :
                          (cyc_cnt[2:0] == 3'd2) ? ((72'd3) << (cyc_cnt[8:3] % 70)) : 72'd0;

  mlu_sram_secded_ecc u_rtl_ecc (
    .data_i            (ecc_data_i),
    .codeword_o        (rtl_ecc_cw_o),
    .codeword_i        (rtl_ecc_cw_o),
    .err_inject_mask_i (ecc_err_mask_i),
    .data_o            (rtl_ecc_data_o),
    .syndrome_o        (rtl_ecc_syn_o),
    .sec_err_o         (rtl_ecc_sec_o),
    .ded_err_o         (rtl_ecc_ded_o)
  );

  gls_mlu_sram_secded_ecc u_gls_ecc (
    .data_i            (ecc_data_i),
    .codeword_o        (gls_ecc_cw_o),
    .codeword_i        (rtl_ecc_cw_o),
    .err_inject_mask_i (ecc_err_mask_i),
    .data_o            (gls_ecc_data_o),
    .syndrome_o        (gls_ecc_syn_o),
    .sec_err_o         (gls_ecc_sec_o),
    .ded_err_o         (gls_ecc_ded_o)
  );

  // ===========================================================================
  // 2. mlu_pmu_clock_gate (Golden RTL vs. ASAP7 7nm Gate-Level Netlist)
  // ===========================================================================
  logic [4:0]  pmu_eng_busy_i, pmu_disp_mask_i;
  logic [2:0]  pmu_mem_active_i;
  logic        pmu_cfg_valid_i;
  logic [7:0]  pmu_idle_thresh_i;
  logic [4:0]  rtl_pmu_clk_en_o, gls_pmu_clk_en_o;
  logic [2:0]  rtl_pmu_slp_o, gls_pmu_slp_o;
  logic [2:0]  rtl_pmu_dslp_o, gls_pmu_dslp_o;
  logic [2:0]  rtl_pmu_wake_o, gls_pmu_wake_o;
  logic [31:0] rtl_pmu_mac_cyc_o, gls_pmu_mac_cyc_o;
  logic [31:0] rtl_pmu_gated_cyc_o, gls_pmu_gated_cyc_o;
  logic [31:0] rtl_pmu_slp_cyc_o, gls_pmu_slp_cyc_o;

  assign pmu_eng_busy_i    = (cyc_cnt[4]) ? lfsr_q[4:0] : 5'b00000;
  assign pmu_disp_mask_i   = (cyc_cnt[3]) ? lfsr_q[9:5] : 5'b00000;
  assign pmu_mem_active_i  = (cyc_cnt[5]) ? lfsr_q[12:10] : 3'b000;
  assign pmu_cfg_valid_i   = (cyc_cnt == 32'd10);
  assign pmu_idle_thresh_i = 8'd4;

  mlu_pmu_clock_gate u_rtl_pmu (
    .clk_i                  (clk_i),
    .rst_ni                 (rst_ni),
    .eng_busy_i             (pmu_eng_busy_i),
    .icu_dispatch_mask_i    (pmu_disp_mask_i),
    .mem_active_i           (pmu_mem_active_i),
    .pwr_gate_cfg_valid_i   (pmu_cfg_valid_i),
    .idle_threshold_i       (pmu_idle_thresh_i),
    .eng_clk_en_o           (rtl_pmu_clk_en_o),
    .sram_slp_o             (rtl_pmu_slp_o),
    .sram_dslp_o            (rtl_pmu_dslp_o),
    .sram_wake_ready_o      (rtl_pmu_wake_o),
    .active_mac_cycles_o    (rtl_pmu_mac_cyc_o),
    .gated_saved_cycles_o   (rtl_pmu_gated_cyc_o),
    .sram_sleep_cycles_o    (rtl_pmu_slp_cyc_o)
  );

  gls_mlu_pmu_clock_gate u_gls_pmu (
    .clk_i                  (clk_i),
    .rst_ni                 (rst_ni),
    .eng_busy_i             (pmu_eng_busy_i),
    .icu_dispatch_mask_i    (pmu_disp_mask_i),
    .mem_active_i           (pmu_mem_active_i),
    .pwr_gate_cfg_valid_i   (pmu_cfg_valid_i),
    .idle_threshold_i       (pmu_idle_thresh_i),
    .eng_clk_en_o           (gls_pmu_clk_en_o),
    .sram_slp_o             (gls_pmu_slp_o),
    .sram_dslp_o            (gls_pmu_dslp_o),
    .sram_wake_ready_o      (gls_pmu_wake_o),
    .active_mac_cycles_o    (gls_pmu_mac_cyc_o),
    .gated_saved_cycles_o   (gls_pmu_gated_cyc_o),
    .sram_sleep_cycles_o    (gls_pmu_slp_cyc_o)
  );

  // ===========================================================================
  // 3. mlu_bang_icu (Golden RTL vs. ASAP7 7nm Gate-Level Netlist)
  // ===========================================================================
  logic         icu_inst_valid_i;
  logic [127:0] icu_inst_i;
  logic [4:0]   icu_eng_ready_i, icu_eng_done_v_i;
  logic [39:0]  icu_eng_done_tag_i;
  logic         icu_sync_ack_i;
  logic         rtl_icu_ready_o, gls_icu_ready_o;
  logic [4:0]   rtl_icu_cmd_v_o, gls_icu_cmd_v_o;
  logic [127:0] rtl_icu_cmd_inst_o, gls_icu_cmd_inst_o;
  logic [4:0]   rtl_icu_disp_mask_o, gls_icu_disp_mask_o;
  logic         rtl_icu_pwr_cfg_o, gls_icu_pwr_cfg_o;
  logic [7:0]   rtl_icu_idle_th_o, gls_icu_idle_th_o;
  logic         rtl_icu_sync_req_o, gls_icu_sync_req_o;
  logic [4:0]   rtl_icu_q_busy_o, gls_icu_q_busy_o;
  logic         rtl_icu_haz_o, gls_icu_haz_o;
  logic [31:0]  rtl_icu_ret_cnt_o, gls_icu_ret_cnt_o;
  logic [31:0]  rtl_icu_haz_cnt_o, gls_icu_haz_cnt_o;

  logic [5:0] icu_opc_sel;
  always_comb begin
    case (cyc_cnt[2:0])
      3'd0: icu_opc_sel = OP_BANG_CONV2D;
      3'd1: icu_opc_sel = OP_BANG_RMSNORM;
      3'd2: icu_opc_sel = OP_BANG_MEMCPY_2D;
      3'd3: icu_opc_sel = OP_MPU_BCAST_SRAM;
      3'd4: icu_opc_sel = OP_SYNC_IPU;
      3'd5: icu_opc_sel = OP_PWR_GATE_CFG;
      default: icu_opc_sel = OP_BANG_SPARSE_MM;
    endcase
  end

  assign icu_inst_valid_i   = (cyc_cnt > 32'd5) && (cyc_cnt[1:0] == 2'b00);
  assign icu_inst_i         = {icu_opc_sel, lfsr_q[2:0], 3'b000, 1'b0, 1'b0, cyc_cnt[7:0],
                               lfsr_q[4:0], lfsr_q[9:5], lfsr_q[31:0], lfsr_q[63:32],
                               16'd4, 8'd8, 8'h55};
  assign icu_eng_ready_i    = 5'b11111;
  assign icu_sync_ack_i     = rtl_icu_sync_req_o;
  assign icu_eng_done_v_i   = rtl_icu_cmd_v_o;
  assign icu_eng_done_tag_i = {5{rtl_icu_cmd_inst_o[113:106]}};

  mlu_bang_icu u_rtl_icu (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .inst_valid_i        (icu_inst_valid_i),
    .inst_ready_o        (rtl_icu_ready_o),
    .inst_i              (icu_inst_i),
    .eng_cmd_valid_o     (rtl_icu_cmd_v_o),
    .eng_cmd_ready_i     (icu_eng_ready_i),
    .eng_cmd_inst_o      (rtl_icu_cmd_inst_o),
    .icu_dispatch_mask_o (rtl_icu_disp_mask_o),
    .pwr_gate_cfg_valid_o(rtl_icu_pwr_cfg_o),
    .idle_threshold_o    (rtl_icu_idle_th_o),
    .cluster_sync_req_o  (rtl_icu_sync_req_o),
    .cluster_sync_ack_i  (icu_sync_ack_i),
    .eng_done_valid_i    (icu_eng_done_v_i),
    .eng_done_tag_i      (icu_eng_done_tag_i),
    .queue_busy_o        (rtl_icu_q_busy_o),
    .hazard_stall_o      (rtl_icu_haz_o),
    .inst_retired_cnt_o  (rtl_icu_ret_cnt_o),
    .hazard_stall_cnt_o  (rtl_icu_haz_cnt_o)
  );

  gls_mlu_bang_icu u_gls_icu (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .inst_valid_i        (icu_inst_valid_i),
    .inst_ready_o        (gls_icu_ready_o),
    .inst_i              (icu_inst_i),
    .eng_cmd_valid_o     (gls_icu_cmd_v_o),
    .eng_cmd_ready_i     (icu_eng_ready_i),
    .eng_cmd_inst_o      (gls_icu_cmd_inst_o),
    .icu_dispatch_mask_o (gls_icu_disp_mask_o),
    .pwr_gate_cfg_valid_o(gls_icu_pwr_cfg_o),
    .idle_threshold_o    (gls_icu_idle_th_o),
    .cluster_sync_req_o  (gls_icu_sync_req_o),
    .cluster_sync_ack_i  (icu_sync_ack_i),
    .eng_done_valid_i    (icu_eng_done_v_i),
    .eng_done_tag_i      (icu_eng_done_tag_i),
    .queue_busy_o        (gls_icu_q_busy_o),
    .hazard_stall_o      (gls_icu_haz_o),
    .inst_retired_cnt_o  (gls_icu_ret_cnt_o),
    .hazard_stall_cnt_o  (gls_icu_haz_cnt_o)
  );

  // ===========================================================================
  // 4. mlu_mfu_dma_engine (Golden RTL vs. ASAP7 7nm Gate-Level Netlist)
  // ===========================================================================
  logic         mfu_cmd_valid_i;
  logic [127:0] mfu_cmd_inst_i;
  logic [63:0]  mfu_idx_off_i;
  logic [7:0]   mfu_bitmap_i;
  logic         mfu_rd_resp_v_i;
  logic [63:0]  mfu_rd_resp_d_i;
  logic         rtl_mfu_ready_o, gls_mfu_ready_o;
  logic         rtl_mfu_rd_v_o, gls_mfu_rd_v_o;
  logic [2:0]   rtl_mfu_rd_sp_o, gls_mfu_rd_sp_o;
  logic [31:0]  rtl_mfu_rd_addr_o, gls_mfu_rd_addr_o;
  logic         rtl_mfu_wr_v_o, gls_mfu_wr_v_o;
  logic [2:0]   rtl_mfu_wr_sp_o, gls_mfu_wr_sp_o;
  logic [31:0]  rtl_mfu_wr_addr_o, gls_mfu_wr_addr_o;
  logic [63:0]  rtl_mfu_wr_data_o, gls_mfu_wr_data_o;
  logic         rtl_mfu_xpose_o, gls_mfu_xpose_o;
  logic         rtl_mfu_busy_o, gls_mfu_busy_o;
  logic [31:0]  rtl_mfu_comp_b_o, gls_mfu_comp_b_o;
  logic [31:0]  rtl_mfu_uncomp_b_o, gls_mfu_uncomp_b_o;
  logic         rtl_mfu_done_v_o, gls_mfu_done_v_o;
  logic [7:0]   rtl_mfu_done_tag_o, gls_mfu_done_tag_o;

  logic [5:0] mfu_opc_sel;
  always_comb begin
    case (cyc_cnt[4:3])
      2'd0: mfu_opc_sel = OP_BANG_MEMCPY_2D;
      2'd1: mfu_opc_sel = OP_BANG_GATHER;
      2'd2: mfu_opc_sel = OP_BANG_SCATTER;
      default: mfu_opc_sel = OP_BANG_DECOMP_DMA;
    endcase
  end

  assign mfu_cmd_valid_i = (cyc_cnt > 32'd6) && rtl_mfu_ready_o && (cyc_cnt[2:0] == 3'd0);
  assign mfu_cmd_inst_i  = {mfu_opc_sel, 3'b000, 3'b001, 1'b0, 1'b0, cyc_cnt[7:0],
                            5'd0, 5'd0, {16'd8, 16'h0100}, {16'd16, 16'h0200},
                            16'd2, 8'd2, 8'd2};
  assign mfu_idx_off_i   = lfsr_q;
  assign mfu_bitmap_i    = (lfsr_q[7:0] | 8'h05);
  assign mfu_rd_resp_v_i = rtl_mfu_rd_v_o;
  assign mfu_rd_resp_d_i = lfsr_q ^ {32'h1234_5678, rtl_mfu_rd_addr_o};

  mlu_mfu_dma_engine u_rtl_mfu (
    .clk_i                  (clk_i),
    .rst_ni                 (rst_ni),
    .cmd_valid_i            (mfu_cmd_valid_i),
    .cmd_ready_o            (rtl_mfu_ready_o),
    .cmd_inst_i             (mfu_cmd_inst_i),
    .idx_offset_i           (mfu_idx_off_i),
    .decomp_bitmap_i        (mfu_bitmap_i),
    .rd_req_valid_o         (rtl_mfu_rd_v_o),
    .rd_req_space_o         (rtl_mfu_rd_sp_o),
    .rd_req_addr_o          (rtl_mfu_rd_addr_o),
    .rd_resp_valid_i        (mfu_rd_resp_v_i),
    .rd_resp_data_i         (mfu_rd_resp_d_i),
    .wr_req_valid_o         (rtl_mfu_wr_v_o),
    .wr_req_space_o         (rtl_mfu_wr_sp_o),
    .wr_req_addr_o          (rtl_mfu_wr_addr_o),
    .wr_req_data_o          (rtl_mfu_wr_data_o),
    .nram_transpose_mode_o  (rtl_mfu_xpose_o),
    .mfu_busy_o             (rtl_mfu_busy_o),
    .compressed_bytes_rd_o  (rtl_mfu_comp_b_o),
    .uncompressed_bytes_wr_o(rtl_mfu_uncomp_b_o),
    .done_valid_o           (rtl_mfu_done_v_o),
    .done_tag_o             (rtl_mfu_done_tag_o)
  );

  gls_mlu_mfu_dma_engine u_gls_mfu (
    .clk_i                  (clk_i),
    .rst_ni                 (rst_ni),
    .cmd_valid_i            (mfu_cmd_valid_i),
    .cmd_ready_o            (gls_mfu_ready_o),
    .cmd_inst_i             (mfu_cmd_inst_i),
    .idx_offset_i           (mfu_idx_off_i),
    .decomp_bitmap_i        (mfu_bitmap_i),
    .rd_req_valid_o         (gls_mfu_rd_v_o),
    .rd_req_space_o         (gls_mfu_rd_sp_o),
    .rd_req_addr_o          (gls_mfu_rd_addr_o),
    .rd_resp_valid_i        (mfu_rd_resp_v_i),
    .rd_resp_data_i         (mfu_rd_resp_d_i),
    .wr_req_valid_o         (gls_mfu_wr_v_o),
    .wr_req_space_o         (gls_mfu_wr_sp_o),
    .wr_req_addr_o          (gls_mfu_wr_addr_o),
    .wr_req_data_o          (gls_mfu_wr_data_o),
    .nram_transpose_mode_o  (gls_mfu_xpose_o),
    .mfu_busy_o             (gls_mfu_busy_o),
    .compressed_bytes_rd_o  (gls_mfu_comp_b_o),
    .uncompressed_bytes_wr_o(gls_mfu_uncomp_b_o),
    .done_valid_o           (gls_mfu_done_v_o),
    .done_tag_o             (gls_mfu_done_tag_o)
  );

  // ===========================================================================
  // 5. mlu_c2c_serdes_pcs (Golden RTL vs. ASAP7 7nm Gate-Level Netlist)
  // ===========================================================================
  logic         pcs_tx_valid_i, pcs_err_crc_i;
  logic [127:0] pcs_tx_flit_i;
  logic         rtl_pcs_tx_ready_o, gls_pcs_tx_ready_o;
  logic         rtl_pcs_ltx_v_o, gls_pcs_ltx_v_o;
  logic [127:0] rtl_pcs_ltx_flit_o, gls_pcs_ltx_flit_o;
  logic         rtl_pcs_rx_v_o, gls_pcs_rx_v_o;
  logic [127:0] rtl_pcs_rx_flit_o, gls_pcs_rx_flit_o;
  logic         rtl_pcs_ack_v_o, gls_pcs_ack_v_o;
  logic [4:0]   rtl_pcs_ack_seq_o, gls_pcs_ack_seq_o;
  logic         rtl_pcs_nack_v_o, gls_pcs_nack_v_o;
  logic [4:0]   rtl_pcs_nack_seq_o, gls_pcs_nack_seq_o;
  logic [31:0]  rtl_pcs_crc_cnt_o, gls_pcs_crc_cnt_o;
  logic [31:0]  rtl_pcs_retx_cnt_o, gls_pcs_retx_cnt_o;

  assign pcs_tx_valid_i = (cyc_cnt > 32'd5) && rtl_pcs_tx_ready_o && (cyc_cnt[1:0] != 2'b11);
  assign pcs_tx_flit_i  = {2'b11, cyc_cnt[0], 4'd0, 4'd1, 5'd0, 16'd0, lfsr_q[31:0], lfsr_q};
  assign pcs_err_crc_i  = (cyc_cnt[4:0] == 5'd15) && rtl_pcs_ltx_v_o && !rtl_pcs_nack_v_o;

  mlu_c2c_serdes_pcs u_rtl_pcs (
    .clk              (clk_i),
    .rst_n            (rst_ni),
    .tx_valid_i       (pcs_tx_valid_i),
    .tx_ready_o       (rtl_pcs_tx_ready_o),
    .tx_flit_i        (pcs_tx_flit_i),
    .link_tx_valid_o  (rtl_pcs_ltx_v_o),
    .link_tx_flit_o   (rtl_pcs_ltx_flit_o),
    .link_rx_valid_i  (rtl_pcs_ltx_v_o),
    .link_rx_flit_i   (rtl_pcs_ltx_flit_o),
    .err_inject_crc_i (pcs_err_crc_i),
    .rx_valid_o       (rtl_pcs_rx_v_o),
    .rx_flit_o        (rtl_pcs_rx_flit_o),
    .ack_valid_o      (rtl_pcs_ack_v_o),
    .ack_seq_o        (rtl_pcs_ack_seq_o),
    .nack_valid_o     (rtl_pcs_nack_v_o),
    .nack_seq_o       (rtl_pcs_nack_seq_o),
    .replay_trigger_i (rtl_pcs_nack_v_o),
    .replay_seq_i     (rtl_pcs_nack_seq_o),
    .crc_err_cnt_o    (rtl_pcs_crc_cnt_o),
    .retransmit_cnt_o (rtl_pcs_retx_cnt_o)
  );

  gls_mlu_c2c_serdes_pcs u_gls_pcs (
    .clk              (clk_i),
    .rst_n            (rst_ni),
    .tx_valid_i       (pcs_tx_valid_i),
    .tx_ready_o       (gls_pcs_tx_ready_o),
    .tx_flit_i        (pcs_tx_flit_i),
    .link_tx_valid_o  (gls_pcs_ltx_v_o),
    .link_tx_flit_o   (gls_pcs_ltx_flit_o),
    .link_rx_valid_i  (rtl_pcs_ltx_v_o),
    .link_rx_flit_i   (rtl_pcs_ltx_flit_o),
    .err_inject_crc_i (pcs_err_crc_i),
    .rx_valid_o       (gls_pcs_rx_v_o),
    .rx_flit_o        (gls_pcs_rx_flit_o),
    .ack_valid_o      (gls_pcs_ack_v_o),
    .ack_seq_o        (gls_pcs_ack_seq_o),
    .nack_valid_o     (gls_pcs_nack_v_o),
    .nack_seq_o       (gls_pcs_nack_seq_o),
    .replay_trigger_i (rtl_pcs_nack_v_o),
    .replay_seq_i     (rtl_pcs_nack_seq_o),
    .crc_err_cnt_o    (gls_pcs_crc_cnt_o),
    .retransmit_cnt_o (gls_pcs_retx_cnt_o)
  );

  // ===========================================================================
  // 6. mlu_cambricon_llm_flash_kv (Golden RTL vs. ASAP7 7nm Gate-Level Netlist)
  // ===========================================================================
  logic         kv_cmd_valid_i, kv_rd_en_i, kv_ecc_clean_i;
  logic [5:0]   kv_opcode_i;
  logic [2:0]   kv_prec_i;
  logic [7:0]   kv_tag_i, kv_tree_mask_i;
  logic [3:0]   kv_wr_slot_i, kv_rd_addr_i;
  logic [31:0]  kv_base_page_i;
  logic [127:0] kv_fp16_in_i, kv_draft_p_i, kv_target_p_i;
  logic [15:0]  kv_thresh_i;
  logic         rtl_kv_ready_o, gls_kv_ready_o;
  logic [127:0] rtl_kv_deq_o, gls_kv_deq_o;
  logic [63:0]  rtl_kv_pack_o, gls_kv_pack_o;
  logic         rtl_kv_freq_v_o, gls_kv_freq_v_o;
  logic [31:0]  rtl_kv_fpage_o, gls_kv_fpage_o;
  logic         rtl_kv_done_v_o, gls_kv_done_v_o;
  logic [7:0]   rtl_kv_done_tag_o, gls_kv_done_tag_o;
  logic [7:0]   rtl_kv_acc_bmap_o, gls_kv_acc_bmap_o;
  logic [3:0]   rtl_kv_acc_len_o, gls_kv_acc_len_o;
  logic [2:0]   rtl_kv_bonus_o, gls_kv_bonus_o;
  logic [31:0]  rtl_kv_tot_acc_o, gls_kv_tot_acc_o;
  logic [31:0]  rtl_kv_tot_sav_o, gls_kv_tot_sav_o;
  logic [31:0]  rtl_kv_ecc_err_o, gls_kv_ecc_err_o;

  assign kv_cmd_valid_i = (cyc_cnt > 32'd5) && (cyc_cnt[1:0] == 2'b01);
  assign kv_opcode_i    = cyc_cnt[2] ? OP_LLM_SPEC_VERIFY : OP_LLM_KV_PACK;
  assign kv_prec_i      = cyc_cnt[3] ? PREC_FP8_E4M3 : PREC_INT4;
  assign kv_tag_i       = cyc_cnt[7:0];
  assign kv_wr_slot_i   = cyc_cnt[5:2];
  assign kv_base_page_i = {16'h0010, lfsr_q[15:0]};
  assign kv_fp16_in_i   = {lfsr_q, lfsr_q ^ 64'h5555_AAAA_1234_5678};
  assign kv_rd_en_i     = (cyc_cnt > 32'd8);
  assign kv_rd_addr_i   = cyc_cnt[5:2];
  assign kv_ecc_clean_i = (cyc_cnt[4:0] != 5'd19);
  assign kv_draft_p_i   = {lfsr_q[63:0], lfsr_q[63:0]};
  assign kv_target_p_i  = {lfsr_q[62:0], 1'b1, lfsr_q[62:0], 1'b1};
  assign kv_tree_mask_i = lfsr_q[7:0] | 8'h0F;
  assign kv_thresh_i    = 16'h0100;

  mlu_cambricon_llm_flash_kv u_rtl_kv (
    .clk_i                  (clk_i),
    .rst_ni                 (rst_ni),
    .cmd_valid_i            (kv_cmd_valid_i),
    .cmd_ready_o            (rtl_kv_ready_o),
    .opcode_i               (kv_opcode_i),
    .prec_i                 (kv_prec_i),
    .cmd_tag_i              (kv_tag_i),
    .kv_wr_slot_i           (kv_wr_slot_i),
    .flash_base_page_i      (kv_base_page_i),
    .kv_fp16_in_i           (kv_fp16_in_i),
    .kv_rd_en_i             (kv_rd_en_i),
    .kv_rd_addr_i           (kv_rd_addr_i),
    .kv_dequant_out_o       (rtl_kv_deq_o),
    .kv_packed_out_o        (rtl_kv_pack_o),
    .flash_req_valid_o      (rtl_kv_freq_v_o),
    .flash_page_addr_o      (rtl_kv_fpage_o),
    .flash_ecc_clean_i      (kv_ecc_clean_i),
    .draft_prob_i           (kv_draft_p_i),
    .target_prob_i          (kv_target_p_i),
    .tree_mask_i            (kv_tree_mask_i),
    .accept_thresh_i        (kv_thresh_i),
    .done_valid_o           (rtl_kv_done_v_o),
    .done_tag_o             (rtl_kv_done_tag_o),
    .accepted_bitmap_o      (rtl_kv_acc_bmap_o),
    .accepted_len_o         (rtl_kv_acc_len_o),
    .bonus_token_idx_o      (rtl_kv_bonus_o),
    .total_accepted_tokens_o(rtl_kv_tot_acc_o),
    .total_kv_bytes_saved_o (rtl_kv_tot_sav_o),
    .flash_ecc_err_cnt_o    (rtl_kv_ecc_err_o)
  );

  gls_mlu_cambricon_llm_flash_kv u_gls_kv (
    .clk_i                  (clk_i),
    .rst_ni                 (rst_ni),
    .cmd_valid_i            (kv_cmd_valid_i),
    .cmd_ready_o            (gls_kv_ready_o),
    .opcode_i               (kv_opcode_i),
    .prec_i                 (kv_prec_i),
    .cmd_tag_i              (kv_tag_i),
    .kv_wr_slot_i           (kv_wr_slot_i),
    .flash_base_page_i      (kv_base_page_i),
    .kv_fp16_in_i           (kv_fp16_in_i),
    .kv_rd_en_i             (kv_rd_en_i),
    .kv_rd_addr_i           (kv_rd_addr_i),
    .kv_dequant_out_o       (gls_kv_deq_o),
    .kv_packed_out_o        (gls_kv_pack_o),
    .flash_req_valid_o      (gls_kv_freq_v_o),
    .flash_page_addr_o      (gls_kv_fpage_o),
    .flash_ecc_clean_i      (kv_ecc_clean_i),
    .draft_prob_i           (kv_draft_p_i),
    .target_prob_i          (kv_target_p_i),
    .tree_mask_i            (kv_tree_mask_i),
    .accept_thresh_i        (kv_thresh_i),
    .done_valid_o           (gls_kv_done_v_o),
    .done_tag_o             (gls_kv_done_tag_o),
    .accepted_bitmap_o      (gls_kv_acc_bmap_o),
    .accepted_len_o         (gls_kv_acc_len_o),
    .bonus_token_idx_o      (gls_kv_bonus_o),
    .total_accepted_tokens_o(gls_kv_tot_acc_o),
    .total_kv_bytes_saved_o (gls_kv_tot_sav_o),
    .flash_ecc_err_cnt_o    (gls_kv_ecc_err_o)
  );

  // ===========================================================================
  // 7. mlu_sram_sp_macro (Golden RTL vs. ASAP7 7nm Gate-Level Netlist)
  // ===========================================================================
  logic        sram_req_en_i, sram_req_we_i;
  logic [7:0]  sram_req_addr_i, sram_req_wmask_i;
  logic [63:0] sram_req_wdata_i;
  logic [71:0] sram_err_mask_i;
  logic        sram_bist_en_i, sram_repair_en_i, sram_scrub_en_i;
  logic [7:0]  sram_repair_addr_i;
  logic        sram_slp_i, sram_dslp_i, sram_sd_i;

  logic [63:0] rtl_sram_rdata_o, gls_sram_rdata_o;
  logic        rtl_sram_rvalid_o, gls_sram_rvalid_o;
  logic        rtl_sram_sec_o, gls_sram_sec_o;
  logic        rtl_sram_ded_o, gls_sram_ded_o;
  logic [7:0]  rtl_sram_syn_o, gls_sram_syn_o;
  logic        rtl_sram_bdone_o, gls_sram_bdone_o;
  logic        rtl_sram_bfail_o, gls_sram_bfail_o;
  logic [7:0]  rtl_sram_bfaddr_o, gls_sram_bfaddr_o;
  logic [63:0] rtl_sram_spare_o, gls_sram_spare_o;
  logic [7:0]  rtl_sram_saddr_o, gls_sram_saddr_o;
  logic        rtl_sram_pready_o, gls_sram_pready_o;

  assign sram_bist_en_i     = (cyc_cnt >= 32'd20 && cyc_cnt <= 32'd260);
  assign sram_req_en_i      = (cyc_cnt >= 32'd1 && cyc_cnt < 32'd18) ? 1'b1 :
                              (cyc_cnt > 32'd270) ? lfsr_q[0] : 1'b0;
  assign sram_req_we_i      = (cyc_cnt >= 32'd1 && cyc_cnt < 32'd18) ? 1'b1 : lfsr_q[1];
  assign sram_req_addr_i    = (cyc_cnt >= 32'd1 && cyc_cnt < 32'd18) ? cyc_cnt[7:0] : {5'd0, lfsr_q[4:2]};
  assign sram_req_wdata_i   = lfsr_q ^ {32'h55AA_AA55, cyc_cnt};
  assign sram_req_wmask_i   = 8'hFF;
  assign sram_err_mask_i    = (cyc_cnt > 32'd300 && cyc_cnt[4:0] == 5'd3) ? 72'd1 : 72'd0;
  assign sram_repair_en_i   = (cyc_cnt > 32'd500);
  assign sram_repair_addr_i = 8'd7;
  assign sram_scrub_en_i    = (cyc_cnt > 32'd1000 && !sram_req_en_i);
  assign sram_slp_i         = (cyc_cnt >= 32'd2000 && cyc_cnt < 32'd2010);
  assign sram_dslp_i        = (cyc_cnt >= 32'd2020 && cyc_cnt < 32'd2030);
  assign sram_sd_i          = (cyc_cnt >= 32'd2040 && cyc_cnt < 32'd2050);

  mlu_sram_sp_macro u_rtl_sram (
    .clk                (clk_i), .rst_n              (rst_ni),
    .req_en_i           (sram_req_en_i), .req_we_i           (sram_req_we_i),
    .req_addr_i         (sram_req_addr_i), .req_wdata_i        (sram_req_wdata_i),
    .req_wmask_i        (sram_req_wmask_i), .rdata_o            (rtl_sram_rdata_o),
    .rvalid_o           (rtl_sram_rvalid_o), .err_inject_mask_i  (sram_err_mask_i),
    .sec_err_o          (rtl_sram_sec_o), .ded_err_o          (rtl_sram_ded_o),
    .syndrome_o         (rtl_sram_syn_o), .bist_en_i          (sram_bist_en_i),
    .bist_done_o        (rtl_sram_bdone_o), .bist_fail_o        (rtl_sram_bfail_o),
    .bist_fail_addr_o   (rtl_sram_bfaddr_o), .repair_en_i        (sram_repair_en_i),
    .repair_bad_addr_i  (sram_repair_addr_i), .repair_spare_data_q(rtl_sram_spare_o),
    .scrub_en_i         (sram_scrub_en_i), .scrub_addr_o       (rtl_sram_saddr_o),
    .slp_i              (sram_slp_i), .dslp_i             (sram_dslp_i),
    .sd_i               (sram_sd_i), .pwr_ready_o        (rtl_sram_pready_o)
  );

  gls_mlu_sram_sp_macro u_gls_sram (
    .clk                (clk_i), .rst_n              (rst_ni),
    .req_en_i           (sram_req_en_i), .req_we_i           (sram_req_we_i),
    .req_addr_i         (sram_req_addr_i), .req_wdata_i        (sram_req_wdata_i),
    .req_wmask_i        (sram_req_wmask_i), .rdata_o            (gls_sram_rdata_o),
    .rvalid_o           (gls_sram_rvalid_o), .err_inject_mask_i  (sram_err_mask_i),
    .sec_err_o          (gls_sram_sec_o), .ded_err_o          (gls_sram_ded_o),
    .syndrome_o         (gls_sram_syn_o), .bist_en_i          (sram_bist_en_i),
    .bist_done_o        (gls_sram_bdone_o), .bist_fail_o        (gls_sram_bfail_o),
    .bist_fail_addr_o   (gls_sram_bfaddr_o), .repair_en_i        (sram_repair_en_i),
    .repair_bad_addr_i  (sram_repair_addr_i), .repair_spare_data_q(gls_sram_spare_o),
    .scrub_en_i         (sram_scrub_en_i), .scrub_addr_o       (gls_sram_saddr_o),
    .slp_i              (sram_slp_i), .dslp_i             (sram_dslp_i),
    .sd_i               (sram_sd_i), .pwr_ready_o        (gls_sram_pready_o)
  );

  // ===========================================================================
  // 8. mlu_mpu_core (Golden RTL vs. ASAP7 7nm Gate-Level Netlist)
  // ===========================================================================
  logic              mpu_cmd_valid_i;
  logic [127:0]      mpu_cmd_inst_i;
  logic [3:0]        mpu_ipu_req_v_i, mpu_ipu_req_we_i;
  logic [3:0][10:0]  mpu_ipu_req_addr_i;
  logic [3:0][63:0]  mpu_ipu_req_wdata_i;
  logic              mpu_dma_v_i, mpu_dma_we_i;
  logic [10:0]       mpu_dma_addr_i;
  logic [63:0]       mpu_dma_wdata_i;
  logic              mpu_noc_tx_r_i, mpu_noc_rx_v_i;
  logic [127:0]      mpu_noc_rx_flit_i;
  logic [2:0]        mpu_err_bank_i;
  logic [71:0]       mpu_err_mask_i;

  logic              rtl_mpu_ready_o, gls_mpu_ready_o;
  logic              rtl_mpu_busy_o, gls_mpu_busy_o;
  logic              rtl_mpu_done_v_o, gls_mpu_done_v_o;
  logic [7:0]        rtl_mpu_done_tag_o, gls_mpu_done_tag_o;
  logic [3:0]        rtl_mpu_ipu_gnt_o, gls_mpu_ipu_gnt_o;
  logic [3:0][63:0]  rtl_mpu_ipu_rdata_o, gls_mpu_ipu_rdata_o;
  logic [3:0]        rtl_mpu_ipu_rval_o, gls_mpu_ipu_rval_o;
  logic              rtl_mpu_dma_gnt_o, gls_mpu_dma_gnt_o;
  logic [63:0]       rtl_mpu_dma_rdata_o, gls_mpu_dma_rdata_o;
  logic              rtl_mpu_dma_rval_o, gls_mpu_dma_rval_o;
  logic [3:0]        rtl_mpu_bcast_v_o, gls_mpu_bcast_v_o;
  logic [10:0]       rtl_mpu_bcast_addr_o, gls_mpu_bcast_addr_o;
  logic [255:0]      rtl_mpu_bcast_data_o, gls_mpu_bcast_data_o;
  logic              rtl_mpu_ntx_v_o, gls_mpu_ntx_v_o;
  logic [127:0]      rtl_mpu_ntx_flit_o, gls_mpu_ntx_flit_o;
  logic              rtl_mpu_nrx_r_o, gls_mpu_nrx_r_o;
  logic              rtl_mpu_sec_o, gls_mpu_sec_o;
  logic              rtl_mpu_ded_o, gls_mpu_ded_o;
  logic [31:0]       rtl_mpu_bcast_cnt_o, gls_mpu_bcast_cnt_o;
  logic [31:0]       rtl_mpu_allred_cnt_o, gls_mpu_allred_cnt_o;

  logic [6:0] mpu_init_idx;
  assign mpu_init_idx   = cyc_cnt[6:0];
  assign mpu_dma_v_i    = (cyc_cnt >= 32'd1 && cyc_cnt < 32'd265) ? 1'b1 : (cyc_cnt[2:0] == 3'd3);
  assign mpu_dma_we_i   = (cyc_cnt >= 32'd1 && cyc_cnt < 32'd260) ? 1'b1 : cyc_cnt[3];
  assign mpu_dma_addr_i = (cyc_cnt >= 32'd1 && cyc_cnt < 32'd260) ?
                          {mpu_init_idx[6:4], 4'b0000, mpu_init_idx[3:0]} :
                          {lfsr_q[6:4], 4'b0000, lfsr_q[3:0]};
  assign mpu_dma_wdata_i     = lfsr_q ^ {32'hCAFE_0000, cyc_cnt};
  assign mpu_cmd_valid_i     = (cyc_cnt > 32'd270) && rtl_mpu_ready_o && (cyc_cnt[3:0] == 4'd0);
  assign mpu_cmd_inst_i      = {cyc_cnt[4] ? OP_MPU_ALLREDUCE : OP_MPU_BCAST_SRAM,
                                3'b000, 3'b000, 1'b0, 1'b0, cyc_cnt[7:0], 5'd0, 5'd0,
                                32'h0000_0000, 32'h0000_0002, 16'd2, 8'd2, 8'd0};
  assign mpu_ipu_req_v_i     = (cyc_cnt > 32'd270) ? lfsr_q[3:0] : 4'b0000;
  assign mpu_ipu_req_we_i    = lfsr_q[7:4];
  assign mpu_ipu_req_addr_i  = {{3'd3, 4'd0, lfsr_q[11:8]}, {3'd2, 4'd0, lfsr_q[15:12]},
                                {3'd1, 4'd0, lfsr_q[19:16]}, {3'd0, 4'd0, lfsr_q[23:20]}};
  assign mpu_ipu_req_wdata_i = {lfsr_q, ~lfsr_q, lfsr_q ^ 64'hFF00_FF00, lfsr_q ^ 64'h00FF_00FF};
  assign mpu_noc_tx_r_i      = 1'b1;
  assign mpu_noc_rx_v_i      = rtl_mpu_ntx_v_o;
  assign mpu_noc_rx_flit_i   = rtl_mpu_ntx_flit_o;
  assign mpu_err_bank_i      = cyc_cnt[5:3];
  assign mpu_err_mask_i      = (cyc_cnt > 32'd270 && cyc_cnt[4:0] == 5'd7) ? 72'd1 : 72'd0;

  mlu_mpu_core u_rtl_mpu (
    .clk_i               (clk_i), .rst_ni              (rst_ni),
    .mpu_cmd_valid_i     (mpu_cmd_valid_i), .mpu_cmd_ready_o     (rtl_mpu_ready_o),
    .mpu_cmd_inst_i      (mpu_cmd_inst_i), .mpu_busy_o          (rtl_mpu_busy_o),
    .mpu_done_valid_o    (rtl_mpu_done_v_o), .mpu_done_tag_o      (rtl_mpu_done_tag_o),
    .ipu_req_valid_i     (mpu_ipu_req_v_i), .ipu_req_we_i        (mpu_ipu_req_we_i),
    .ipu_req_addr_i      (mpu_ipu_req_addr_i), .ipu_req_wdata_i     (mpu_ipu_req_wdata_i),
    .ipu_req_grant_o     (rtl_mpu_ipu_gnt_o), .ipu_resp_rdata_o    (rtl_mpu_ipu_rdata_o),
    .ipu_resp_valid_o    (rtl_mpu_ipu_rval_o), .ext_dma_valid_i     (mpu_dma_v_i),
    .ext_dma_we_i        (mpu_dma_we_i), .ext_dma_addr_i      (mpu_dma_addr_i),
    .ext_dma_wdata_i     (mpu_dma_wdata_i), .ext_dma_grant_o     (rtl_mpu_dma_gnt_o),
    .ext_dma_rdata_o     (rtl_mpu_dma_rdata_o), .ext_dma_rvalid_o    (rtl_mpu_dma_rval_o),
    .bcast_valid_o       (rtl_mpu_bcast_v_o), .bcast_dst_addr_o    (rtl_mpu_bcast_addr_o),
    .bcast_data_o        (rtl_mpu_bcast_data_o), .noc_tx_valid_o      (rtl_mpu_ntx_v_o),
    .noc_tx_ready_i      (mpu_noc_tx_r_i), .noc_tx_flit_o       (rtl_mpu_ntx_flit_o),
    .noc_rx_valid_i      (mpu_noc_rx_v_i), .noc_rx_ready_o      (rtl_mpu_nrx_r_o),
    .noc_rx_flit_i       (mpu_noc_rx_flit_i), .err_inject_bank_i   (mpu_err_bank_i),
    .err_inject_mask_i   (mpu_err_mask_i), .mpu_sec_err_o       (rtl_mpu_sec_o),
    .mpu_ded_err_o       (rtl_mpu_ded_o), .bcast_beats_cnt_o   (rtl_mpu_bcast_cnt_o),
    .allreduce_flit_cnt_o(rtl_mpu_allred_cnt_o)
  );

  gls_mlu_mpu_core u_gls_mpu (
    .clk_i               (clk_i), .rst_ni              (rst_ni),
    .mpu_cmd_valid_i     (mpu_cmd_valid_i), .mpu_cmd_ready_o     (gls_mpu_ready_o),
    .mpu_cmd_inst_i      (mpu_cmd_inst_i), .mpu_busy_o          (gls_mpu_busy_o),
    .mpu_done_valid_o    (gls_mpu_done_v_o), .mpu_done_tag_o      (gls_mpu_done_tag_o),
    .ipu_req_valid_i     (mpu_ipu_req_v_i), .ipu_req_we_i        (mpu_ipu_req_we_i),
    .ipu_req_addr_i      (mpu_ipu_req_addr_i), .ipu_req_wdata_i     (mpu_ipu_req_wdata_i),
    .ipu_req_grant_o     (gls_mpu_ipu_gnt_o), .ipu_resp_rdata_o    (gls_mpu_ipu_rdata_o),
    .ipu_resp_valid_o    (gls_mpu_ipu_rval_o), .ext_dma_valid_i     (mpu_dma_v_i),
    .ext_dma_we_i        (mpu_dma_we_i), .ext_dma_addr_i      (mpu_dma_addr_i),
    .ext_dma_wdata_i     (mpu_dma_wdata_i), .ext_dma_grant_o     (gls_mpu_dma_gnt_o),
    .ext_dma_rdata_o     (gls_mpu_dma_rdata_o), .ext_dma_rvalid_o    (gls_mpu_dma_rval_o),
    .bcast_valid_o       (gls_mpu_bcast_v_o), .bcast_dst_addr_o    (gls_mpu_bcast_addr_o),
    .bcast_data_o        (gls_mpu_bcast_data_o), .noc_tx_valid_o      (gls_mpu_ntx_v_o),
    .noc_tx_ready_i      (mpu_noc_tx_r_i), .noc_tx_flit_o       (gls_mpu_ntx_flit_o),
    .noc_rx_valid_i      (mpu_noc_rx_v_i), .noc_rx_ready_o      (gls_mpu_nrx_r_o),
    .noc_rx_flit_i       (mpu_noc_rx_flit_i), .err_inject_bank_i   (mpu_err_bank_i),
    .err_inject_mask_i   (mpu_err_mask_i), .mpu_sec_err_o       (gls_mpu_sec_o),
    .mpu_ded_err_o       (gls_mpu_ded_o), .bcast_beats_cnt_o   (gls_mpu_bcast_cnt_o),
    .allreduce_flit_cnt_o(gls_mpu_allred_cnt_o)
  );

  // ===========================================================================
  // Cycle-Accurate Lockstep Output Comparison (RTL vs. ASAP7 7nm Gate Netlists)
  // & Gate-Level Netlist Dynamic Bit-Toggle Activity Factor (alpha_GLS)
  // ===========================================================================
  logic [511:0] gls_sample_bus, gls_sample_bus_q;
  longint unsigned gls_toggle_bits;
  longint unsigned gls_total_bit_cycs;

  assign gls_sample_bus = {
    gls_ecc_cw_o, gls_ecc_data_o, gls_ecc_syn_o, gls_ecc_sec_o, gls_ecc_ded_o,
    gls_pmu_clk_en_o, gls_pmu_slp_o, gls_pmu_dslp_o, gls_pmu_wake_o,
    gls_icu_cmd_v_o, gls_icu_disp_mask_o, gls_icu_ret_cnt_o[15:0],
    gls_mfu_rd_v_o, gls_mfu_wr_v_o, gls_mfu_wr_addr_o, gls_mfu_wr_data_o[63:0],
    gls_pcs_ltx_v_o, gls_pcs_ltx_flit_o[63:0], gls_pcs_rx_v_o, gls_pcs_rx_flit_o[63:0],
    gls_kv_deq_o[63:0], gls_kv_pack_o[31:0], gls_kv_acc_bmap_o, gls_kv_acc_len_o,
    gls_sram_rdata_o[7:0], gls_sram_rvalid_o, gls_sram_bdone_o, gls_mpu_bcast_v_o, gls_mpu_bcast_addr_o
  };

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int k = 0; k < 8; k++) begin
        chk_cnt[k] <= 32'd0;
        err_cnt[k] <= 32'd0;
      end
      total_checks       <= 32'd0;
      total_errors       <= 32'd0;
      gls_sample_bus_q   <= '0;
      gls_toggle_bits    <= 64'd0;
      gls_total_bit_cycs <= 64'd0;
    end else if (cyc_cnt >= 32'd5) begin
      gls_sample_bus_q   <= gls_sample_bus;
      gls_toggle_bits    <= gls_toggle_bits + 64'($countones(gls_sample_bus ^ gls_sample_bus_q));
      gls_total_bit_cycs <= gls_total_bit_cycs + 64'd512;
      chk_cnt[0] <= chk_cnt[0] + 1;
      if ({rtl_ecc_cw_o, rtl_ecc_data_o, rtl_ecc_syn_o, rtl_ecc_sec_o, rtl_ecc_ded_o} !==
          {gls_ecc_cw_o, gls_ecc_data_o, gls_ecc_syn_o, gls_ecc_sec_o, gls_ecc_ded_o}) begin
        err_cnt[0] <= err_cnt[0] + 1; total_errors <= total_errors + 1;
        $display("[GLS_ERR][ECC] cyc=%0d", cyc_cnt);
      end
      chk_cnt[1] <= chk_cnt[1] + 1;
      if ({rtl_pmu_clk_en_o, rtl_pmu_slp_o, rtl_pmu_dslp_o, rtl_pmu_wake_o, rtl_pmu_mac_cyc_o, rtl_pmu_gated_cyc_o, rtl_pmu_slp_cyc_o} !==
          {gls_pmu_clk_en_o, gls_pmu_slp_o, gls_pmu_dslp_o, gls_pmu_wake_o, gls_pmu_mac_cyc_o, gls_pmu_gated_cyc_o, gls_pmu_slp_cyc_o}) begin
        err_cnt[1] <= err_cnt[1] + 1; total_errors <= total_errors + 1;
        $display("[GLS_ERR][PMU] cyc=%0d", cyc_cnt);
      end
      chk_cnt[2] <= chk_cnt[2] + 1;
      if ({rtl_icu_ready_o, rtl_icu_cmd_v_o, rtl_icu_cmd_inst_o, rtl_icu_disp_mask_o, rtl_icu_pwr_cfg_o, rtl_icu_idle_th_o, rtl_icu_sync_req_o, rtl_icu_q_busy_o, rtl_icu_haz_o, rtl_icu_ret_cnt_o, rtl_icu_haz_cnt_o} !==
          {gls_icu_ready_o, gls_icu_cmd_v_o, gls_icu_cmd_inst_o, gls_icu_disp_mask_o, gls_icu_pwr_cfg_o, gls_icu_idle_th_o, gls_icu_sync_req_o, gls_icu_q_busy_o, gls_icu_haz_o, gls_icu_ret_cnt_o, gls_icu_haz_cnt_o}) begin
        err_cnt[2] <= err_cnt[2] + 1; total_errors <= total_errors + 1;
        $display("[GLS_ERR][ICU] cyc=%0d", cyc_cnt);
      end
      chk_cnt[3] <= chk_cnt[3] + 1;
      if ({rtl_mfu_ready_o, rtl_mfu_rd_v_o, rtl_mfu_rd_sp_o, rtl_mfu_rd_addr_o, rtl_mfu_wr_v_o, rtl_mfu_wr_sp_o, rtl_mfu_wr_addr_o, rtl_mfu_wr_data_o, rtl_mfu_xpose_o, rtl_mfu_busy_o, rtl_mfu_comp_b_o, rtl_mfu_uncomp_b_o, rtl_mfu_done_v_o, rtl_mfu_done_tag_o} !==
          {gls_mfu_ready_o, gls_mfu_rd_v_o, gls_mfu_rd_sp_o, gls_mfu_rd_addr_o, gls_mfu_wr_v_o, gls_mfu_wr_sp_o, gls_mfu_wr_addr_o, gls_mfu_wr_data_o, gls_mfu_xpose_o, gls_mfu_busy_o, gls_mfu_comp_b_o, gls_mfu_uncomp_b_o, gls_mfu_done_v_o, gls_mfu_done_tag_o}) begin
        err_cnt[3] <= err_cnt[3] + 1; total_errors <= total_errors + 1;
        $display("[GLS_ERR][MFU] cyc=%0d", cyc_cnt);
      end
      chk_cnt[4] <= chk_cnt[4] + 1;
      if ({rtl_pcs_tx_ready_o, rtl_pcs_ltx_v_o, rtl_pcs_ltx_flit_o, rtl_pcs_rx_v_o, rtl_pcs_rx_flit_o, rtl_pcs_ack_v_o, rtl_pcs_ack_seq_o, rtl_pcs_nack_v_o, rtl_pcs_nack_seq_o, rtl_pcs_crc_cnt_o, rtl_pcs_retx_cnt_o} !==
          {gls_pcs_tx_ready_o, gls_pcs_ltx_v_o, gls_pcs_ltx_flit_o, gls_pcs_rx_v_o, gls_pcs_rx_flit_o, gls_pcs_ack_v_o, gls_pcs_ack_seq_o, gls_pcs_nack_v_o, gls_pcs_nack_seq_o, gls_pcs_crc_cnt_o, gls_pcs_retx_cnt_o}) begin
        err_cnt[4] <= err_cnt[4] + 1; total_errors <= total_errors + 1;
        $display("[GLS_ERR][PCS] cyc=%0d", cyc_cnt);
      end
      chk_cnt[5] <= chk_cnt[5] + 1;
      if ({rtl_kv_ready_o, rtl_kv_deq_o, rtl_kv_pack_o, rtl_kv_freq_v_o, rtl_kv_fpage_o, rtl_kv_done_v_o, rtl_kv_done_tag_o, rtl_kv_acc_bmap_o, rtl_kv_acc_len_o, rtl_kv_bonus_o, rtl_kv_tot_acc_o, rtl_kv_tot_sav_o, rtl_kv_ecc_err_o} !==
          {gls_kv_ready_o, gls_kv_deq_o, gls_kv_pack_o, gls_kv_freq_v_o, gls_kv_fpage_o, gls_kv_done_v_o, gls_kv_done_tag_o, gls_kv_acc_bmap_o, gls_kv_acc_len_o, gls_kv_bonus_o, gls_kv_tot_acc_o, gls_kv_tot_sav_o, gls_kv_ecc_err_o}) begin
        err_cnt[5] <= err_cnt[5] + 1; total_errors <= total_errors + 1;
        $display("[GLS_ERR][KV] cyc=%0d", cyc_cnt);
      end
      if (cyc_cnt >= 32'd20) begin
        chk_cnt[6] <= chk_cnt[6] + 1;
        if ({rtl_sram_rdata_o, rtl_sram_rvalid_o, rtl_sram_sec_o, rtl_sram_ded_o, rtl_sram_syn_o, rtl_sram_bdone_o, rtl_sram_bfail_o, rtl_sram_bfaddr_o, rtl_sram_spare_o, rtl_sram_saddr_o, rtl_sram_pready_o} !==
            {gls_sram_rdata_o, gls_sram_rvalid_o, gls_sram_sec_o, gls_sram_ded_o, gls_sram_syn_o, gls_sram_bdone_o, gls_sram_bfail_o, gls_sram_bfaddr_o, gls_sram_spare_o, gls_sram_saddr_o, gls_sram_pready_o}) begin
          err_cnt[6] <= err_cnt[6] + 1; total_errors <= total_errors + 1;
          $display("[GLS_ERR][SRAM] cyc=%0d", cyc_cnt);
        end
      end
      if (cyc_cnt >= 32'd270) begin
        chk_cnt[7] <= chk_cnt[7] + 1;
        if ({rtl_mpu_ready_o, rtl_mpu_busy_o, rtl_mpu_done_v_o, rtl_mpu_done_tag_o, rtl_mpu_ipu_gnt_o, rtl_mpu_ipu_rdata_o, rtl_mpu_ipu_rval_o, rtl_mpu_dma_gnt_o, rtl_mpu_dma_rdata_o, rtl_mpu_dma_rval_o, rtl_mpu_bcast_v_o, rtl_mpu_bcast_addr_o, rtl_mpu_bcast_data_o, rtl_mpu_ntx_v_o, rtl_mpu_ntx_flit_o, rtl_mpu_nrx_r_o, rtl_mpu_sec_o, rtl_mpu_ded_o, rtl_mpu_bcast_cnt_o, rtl_mpu_allred_cnt_o} !==
            {gls_mpu_ready_o, gls_mpu_busy_o, gls_mpu_done_v_o, gls_mpu_done_tag_o, gls_mpu_ipu_gnt_o, gls_mpu_ipu_rdata_o, gls_mpu_ipu_rval_o, gls_mpu_dma_gnt_o, gls_mpu_dma_rdata_o, gls_mpu_dma_rval_o, gls_mpu_bcast_v_o, gls_mpu_bcast_addr_o, gls_mpu_bcast_data_o, gls_mpu_ntx_v_o, gls_mpu_ntx_flit_o, gls_mpu_nrx_r_o, gls_mpu_sec_o, gls_mpu_ded_o, gls_mpu_bcast_cnt_o, gls_mpu_allred_cnt_o}) begin
          err_cnt[7] <= err_cnt[7] + 1; total_errors <= total_errors + 1;
          $display("[GLS_ERR][MPU] cyc=%0d", cyc_cnt);
        end
        total_checks <= total_checks + 8;
      end else begin
        total_checks <= total_checks + 7;
      end
      if (cyc_cnt == 32'd5000) begin
        $display("[GLS_SUMMARY] cycles=5000 total_checks=%0d total_errors=%0d", total_checks, total_errors);
        $display("[GLS_MOD] 0:mlu_sram_secded_ecc checks=%0d errs=%0d", chk_cnt[0], err_cnt[0]);
        $display("[GLS_MOD] 1:mlu_pmu_clock_gate checks=%0d errs=%0d mac_cyc=%0d gated_cyc=%0d", chk_cnt[1], err_cnt[1], gls_pmu_mac_cyc_o, gls_pmu_gated_cyc_o);
        $display("[GLS_MOD] 2:mlu_bang_icu checks=%0d errs=%0d retired=%0d haz_stalls=%0d", chk_cnt[2], err_cnt[2], gls_icu_ret_cnt_o, gls_icu_haz_cnt_o);
        $display("[GLS_MOD] 3:mlu_mfu_dma_engine checks=%0d errs=%0d comp_b=%0d uncomp_b=%0d", chk_cnt[3], err_cnt[3], gls_mfu_comp_b_o, gls_mfu_uncomp_b_o);
        $display("[GLS_MOD] 4:mlu_c2c_serdes_pcs checks=%0d errs=%0d crc_err=%0d retx=%0d", chk_cnt[4], err_cnt[4], gls_pcs_crc_cnt_o, gls_pcs_retx_cnt_o);
        $display("[GLS_MOD] 5:mlu_cambricon_llm_flash_kv checks=%0d errs=%0d acc_tok=%0d kv_saved=%0d", chk_cnt[5], err_cnt[5], gls_kv_tot_acc_o, gls_kv_tot_sav_o);
        $display("[GLS_MOD] 6:mlu_sram_sp_macro checks=%0d errs=%0d bist_done=%0d bist_fail=%0d", chk_cnt[6], err_cnt[6], gls_sram_bdone_o, gls_sram_bfail_o);
        $display("[GLS_MOD] 7:mlu_mpu_core checks=%0d errs=%0d bcast=%0d allred=%0d", chk_cnt[7], err_cnt[7], gls_mpu_bcast_cnt_o, gls_mpu_allred_cnt_o);
        $display("[GLS_TOGGLE] toggle_bits=%0d total_bit_cycs=%0d", gls_toggle_bits, gls_total_bit_cycs);
        $finish;
      end
    end
  end
endmodule
