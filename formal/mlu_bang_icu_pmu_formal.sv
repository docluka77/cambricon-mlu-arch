// =============================================================================
// File: formal/mlu_bang_icu_pmu_formal.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Sequential SAT / BMC Formal Wrapper for mlu_bang_icu and
//              mlu_pmu_clock_gate:
//              - Property 1: Scoreboard RAW Hazard Safety on NRAM/WRAM/SRAM
//              - Property 2: Sync Barrier Safety (OP_SYNC_IPU / OP_SYNC_CLUSTER)
//              - Property 3: PMU Zero-Cycle Immediate Wakeup Guarantee
// =============================================================================
`include "mlu_pkg.sv"

module mlu_bang_icu_pmu_formal (
  input  logic            clk_i,
  input  logic            rst_ni,
  input  logic            inst_valid_i,
  input  logic [127:0]    inst_i,
  input  logic [4:0]      eng_cmd_ready_i,
  input  logic            cluster_sync_ack_i,
  input  logic [4:0]      eng_done_valid_i,
  input  logic [4:0][7:0] eng_done_tag_i,
  input  logic [2:0]      mem_active_i,
  output logic [4:0]      eng_cmd_valid_o,
  output logic [4:0]      eng_clk_en_o,
  output logic            hazard_stall_o
);

  logic         inst_ready;
  logic [127:0] eng_cmd_inst;
  logic [4:0]   icu_dispatch_mask;
  logic         pwr_gate_cfg_valid;
  logic [7:0]   idle_threshold;
  logic         cluster_sync_req;
  logic [4:0]   queue_busy;
  logic [31:0]  inst_retired_cnt, hazard_stall_cnt;
  logic [2:0]   sram_slp, sram_dslp, sram_wake_ready;
  logic [31:0]  active_mac_cycles, gated_saved_cycles, sram_sleep_cycles;

  mlu_pkg::mlu_inst_t raw_inst, dec_inst;
  assign raw_inst = inst_i;
  always_comb begin
    dec_inst              = raw_inst;
    dec_inst.tag_id       = {6'd0, raw_inst.tag_id[1:0]};
    dec_inst.dst_addr     = {20'd0, raw_inst.dst_addr[11:10], 10'd0};
    dec_inst.src0_addr    = {20'd0, raw_inst.src0_addr[11:10], 10'd0};
    dec_inst.src1_or_strd = {4'd0, raw_inst.src1_or_strd[11:10], 10'd0};
  end

  mlu_bang_icu #(
    .SCOREBOARD_SLOTS (2)
  ) u_icu (
    .clk_i                (clk_i),
    .rst_ni               (rst_ni),
    .inst_valid_i         (inst_valid_i),
    .inst_ready_o         (inst_ready),
    .inst_i               (dec_inst),
    .eng_cmd_valid_o      (eng_cmd_valid_o),
    .eng_cmd_ready_i      (eng_cmd_ready_i),
    .eng_cmd_inst_o       (eng_cmd_inst),
    .icu_dispatch_mask_o  (icu_dispatch_mask),
    .pwr_gate_cfg_valid_o (pwr_gate_cfg_valid),
    .idle_threshold_o     (idle_threshold),
    .cluster_sync_req_o   (cluster_sync_req),
    .cluster_sync_ack_i   (cluster_sync_ack_i),
    .eng_done_valid_i     (eng_done_valid_i),
    .eng_done_tag_i       (eng_done_tag_i),
    .queue_busy_o         (queue_busy),
    .hazard_stall_o       (hazard_stall_o),
    .inst_retired_cnt_o   (inst_retired_cnt),
    .hazard_stall_cnt_o   (hazard_stall_cnt)
  );

  mlu_pmu_clock_gate #(
    .DEFAULT_IDLE_THRESH (8'd4)
  ) u_pmu (
    .clk_i                (clk_i),
    .rst_ni               (rst_ni),
    .eng_busy_i           (queue_busy),
    .icu_dispatch_mask_i  (icu_dispatch_mask),
    .mem_active_i         (mem_active_i),
    .pwr_gate_cfg_valid_i (pwr_gate_cfg_valid),
    .idle_threshold_i     (idle_threshold),
    .eng_clk_en_o         (eng_clk_en_o),
    .sram_slp_o           (sram_slp),
    .sram_dslp_o          (sram_dslp),
    .sram_wake_ready_o    (sram_wake_ready),
    .active_mac_cycles_o  (active_mac_cycles),
    .gated_saved_cycles_o (gated_saved_cycles),
    .sram_sleep_cycles_o  (sram_sleep_cycles)
  );

  logic is_ctrl_inst;
  assign is_ctrl_inst = (dec_inst.engine == mlu_pkg::ENG_ICU_CTRL)      ||
                        (dec_inst.opcode == mlu_pkg::OP_NOP)            ||
                        (dec_inst.opcode == mlu_pkg::OP_SYNC_IPU)       ||
                        (dec_inst.opcode == mlu_pkg::OP_SYNC_CLUSTER)   ||
                        (dec_inst.opcode == mlu_pkg::OP_PWR_GATE_CFG);

  // Port-level reference scoreboard tracker for an active in-flight writer
  logic        ref_valid_q;
  logic [2:0]  ref_q_idx_q;
  logic [7:0]  ref_tag_q;
  logic [2:0]  ref_dst_space_q;
  logic [21:0] ref_dst_reg_q;

  logic [2:0] disp_q_idx;
  always_comb begin
    unique case (dec_inst.engine)
      mlu_pkg::ENG_TFU_MAT: disp_q_idx = 3'd0;
      mlu_pkg::ENG_VFU_VEC: disp_q_idx = 3'd1;
      mlu_pkg::ENG_MFU_DMA: disp_q_idx = 3'd2;
      mlu_pkg::ENG_MPU_COL: disp_q_idx = 3'd3;
      mlu_pkg::ENG_LLM_KV:  disp_q_idx = 3'd4;
      default:              disp_q_idx = 3'd0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ref_valid_q     <= 1'b0;
      ref_q_idx_q     <= 3'd0;
      ref_tag_q       <= 8'd0;
      ref_dst_space_q <= 3'd0;
      ref_dst_reg_q   <= 22'd0;
    end else begin
      if (ref_valid_q && eng_done_valid_i[ref_q_idx_q] &&
          (eng_done_tag_i[ref_q_idx_q] == ref_tag_q)) begin
        ref_valid_q <= 1'b0;
      end else if (!ref_valid_q && (|eng_cmd_valid_o) && inst_ready &&
                   ((dec_inst.dst_space == mlu_pkg::MEM_SPACE_NRAM) ||
                    (dec_inst.dst_space == mlu_pkg::MEM_SPACE_WRAM) ||
                    (dec_inst.dst_space == mlu_pkg::MEM_SPACE_SRAM))) begin
        ref_valid_q     <= 1'b1;
        ref_q_idx_q     <= disp_q_idx;
        ref_tag_q       <= dec_inst.tag_id;
        ref_dst_space_q <= dec_inst.dst_space;
        ref_dst_reg_q   <= dec_inst.dst_addr[31:10];
      end
    end
  end

  always_comb begin
    assume (rst_ni == 1'b1);

    // Property 1 (Scoreboard RAW Hazard Safety on NRAM/WRAM/SRAM)
    if (ref_valid_q) begin
      assert (queue_busy[ref_q_idx_q] == 1'b1);
      if (!is_ctrl_inst &&
          (dec_inst.src_space == ref_dst_space_q) &&
          (dec_inst.src0_addr[31:10] == ref_dst_reg_q)) begin
        assert (eng_cmd_valid_o == 5'b00000);
        if (inst_valid_i) begin
          assert (hazard_stall_o == 1'b1);
          assert (!inst_ready);
        end
      end
    end

    // Property 2 (Sync Barrier Safety: OP_SYNC_IPU / OP_SYNC_CLUSTER)
    if ((dec_inst.opcode == mlu_pkg::OP_SYNC_IPU) ||
        (dec_inst.opcode == mlu_pkg::OP_SYNC_CLUSTER)) begin
      assert (eng_cmd_valid_o == 5'b00000);
      if (inst_valid_i && (queue_busy != 5'b00000)) begin
        assert (!inst_ready);
        assert (hazard_stall_o);
      end
    end

    // Property 3 (PMU Zero-Cycle Wakeup Guarantee across all 5 engines)
    if (queue_busy[0] || icu_dispatch_mask[0]) assert (eng_clk_en_o[0] == 1'b1);
    if (queue_busy[1] || icu_dispatch_mask[1]) assert (eng_clk_en_o[1] == 1'b1);
    if (queue_busy[2] || icu_dispatch_mask[2]) assert (eng_clk_en_o[2] == 1'b1);
    if (queue_busy[3] || icu_dispatch_mask[3]) assert (eng_clk_en_o[3] == 1'b1);
    if (queue_busy[4] || icu_dispatch_mask[4]) assert (eng_clk_en_o[4] == 1'b1);
  end

endmodule : mlu_bang_icu_pmu_formal
