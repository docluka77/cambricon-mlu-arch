// =============================================================================
// File: rtl/mlu_bang_icu.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Stage 3A — BANG ISA Instruction Control Unit (ICU) & Multi-Queue
//              Hazard Scoreboard. Decodes 128-bit mlu_inst_t instructions,
//              tracks in-flight tags across 5 execution queues (TFU, VFU, MFU,
//              MPU, LLM_KV), enforces RAW/WAR/WAW memory space & region hazard
//              interlocks on NRAM/WRAM/SRAM plus explicit dep_mask barriers,
//              and executes OP_SYNC_IPU and OP_SYNC_CLUSTER synchronization.
// =============================================================================
`include "mlu_pkg.sv"

module mlu_bang_icu #(
  parameter int unsigned SCOREBOARD_SLOTS = 8
) (
  input  logic             clk_i,
  input  logic             rst_ni,

  // Fetch / Upstream Instruction Stream
  input  logic             inst_valid_i,
  output logic             inst_ready_o,
  input  logic [127:0]     inst_i,

  // 5 Execution Queue Dispatch Interfaces
  // [0]=ENG_TFU_MAT, [1]=ENG_VFU_VEC, [2]=ENG_MFU_DMA, [3]=ENG_MPU_COL, [4]=ENG_LLM_KV
  output logic [4:0]       eng_cmd_valid_o,
  input  logic [4:0]       eng_cmd_ready_i,
  output logic [127:0]     eng_cmd_inst_o,
  output logic [4:0]       icu_dispatch_mask_o,

  // Dynamic Power/Clock Gate Hint Interface (OP_PWR_GATE_CFG)
  output logic             pwr_gate_cfg_valid_o,
  output logic [7:0]       idle_threshold_o,

  // MTP Cluster Hardware Union-Task Barrier Interface (OP_SYNC_CLUSTER)
  output logic             cluster_sync_req_o,
  input  logic             cluster_sync_ack_i,

  // Execution Engine Completion Interface
  input  logic [4:0]       eng_done_valid_i,
  input  logic [4:0][7:0]  eng_done_tag_i,

  // Status & Performance Telemetry Counters
  output logic [4:0]       queue_busy_o,
  output logic             hazard_stall_o,
  output logic [31:0]      inst_retired_cnt_o,
  output logic [31:0]      hazard_stall_cnt_o
);

  // ---------------------------------------------------------------------------
  // 1. Instruction Field Decode
  // ---------------------------------------------------------------------------
  mlu_pkg::mlu_inst_t dec_inst;
  assign dec_inst       = inst_i;
  assign eng_cmd_inst_o = inst_i;

  logic is_ctrl_inst;
  logic is_sync_ipu;
  logic is_sync_cluster;
  logic is_pwr_cfg;

  assign is_sync_ipu     = (dec_inst.opcode == mlu_pkg::OP_SYNC_IPU);
  assign is_sync_cluster = (dec_inst.opcode == mlu_pkg::OP_SYNC_CLUSTER);
  assign is_pwr_cfg      = (dec_inst.opcode == mlu_pkg::OP_PWR_GATE_CFG);
  assign is_ctrl_inst    = (dec_inst.engine == mlu_pkg::ENG_ICU_CTRL) ||
                           (dec_inst.opcode == mlu_pkg::OP_NOP)       ||
                           is_sync_ipu || is_sync_cluster || is_pwr_cfg;

  // Map target engine enum to 0..4 queue index and 5-bit one-hot mask
  logic [2:0] target_q_idx;
  logic [4:0] target_q_mask;

  always_comb begin
    target_q_idx  = 3'd0;
    target_q_mask = 5'b00000;
    if (!is_ctrl_inst) begin
      unique case (dec_inst.engine)
        mlu_pkg::ENG_TFU_MAT: begin target_q_idx = 3'd0; target_q_mask = 5'b00001; end
        mlu_pkg::ENG_VFU_VEC: begin target_q_idx = 3'd1; target_q_mask = 5'b00010; end
        mlu_pkg::ENG_MFU_DMA: begin target_q_idx = 3'd2; target_q_mask = 5'b00100; end
        mlu_pkg::ENG_MPU_COL: begin target_q_idx = 3'd3; target_q_mask = 5'b01000; end
        mlu_pkg::ENG_LLM_KV:  begin target_q_idx = 3'd4; target_q_mask = 5'b10000; end
        default:              begin target_q_idx = 3'd0; target_q_mask = 5'b00001; end
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // 2. Multi-Queue In-Flight Scoreboard Storage
  // ---------------------------------------------------------------------------
  logic [SCOREBOARD_SLOTS-1:0]       sb_valid_q;
  logic [SCOREBOARD_SLOTS-1:0][2:0]  sb_q_idx_q;
  logic [SCOREBOARD_SLOTS-1:0][7:0]  sb_tag_q;
  logic [SCOREBOARD_SLOTS-1:0][2:0]  sb_src_space_q;
  logic [SCOREBOARD_SLOTS-1:0][2:0]  sb_dst_space_q;
  logic [SCOREBOARD_SLOTS-1:0][21:0] sb_src_reg_q;
  logic [SCOREBOARD_SLOTS-1:0][21:0] sb_dst_reg_q;
  logic [SCOREBOARD_SLOTS-1:0]       sb_uses_wram_q;
  logic [SCOREBOARD_SLOTS-1:0][5:0]  sb_wram_reg_q;

  // Compute per-queue busy flags from active scoreboard slots
  always_comb begin
    queue_busy_o = 5'b00000;
    for (int s = 0; s < SCOREBOARD_SLOTS; s++) begin
      if (sb_valid_q[s]) begin
        if (sb_q_idx_q[s] < 3'd5) begin
          queue_busy_o[sb_q_idx_q[s]] = 1'b1;
        end
      end
    end
  end

  // Helper: check if memory space is an on-chip scratchpad subject to hazard checks
  function automatic logic is_scratchpad_space(input logic [2:0] sp);
    is_scratchpad_space = (sp == mlu_pkg::MEM_SPACE_NRAM) ||
                          (sp == mlu_pkg::MEM_SPACE_WRAM) ||
                          (sp == mlu_pkg::MEM_SPACE_SRAM);
  endfunction

  // Address region extraction (1 KB granularity: bits [31:10])
  logic [21:0] dec_src_reg;
  logic [21:0] dec_dst_reg;
  logic [5:0]  dec_wram_reg;
  logic        dec_uses_wram;

  assign dec_src_reg   = dec_inst.src0_addr[31:10];
  assign dec_dst_reg   = dec_inst.dst_addr[31:10];
  assign dec_wram_reg  = dec_inst.src1_or_strd[15:10];
  assign dec_uses_wram = (dec_inst.engine == mlu_pkg::ENG_TFU_MAT);

  // ---------------------------------------------------------------------------
  // 3. Hazard Detection (RAW / WAR / WAW / Tag Collision / Explicit dep_mask)
  // ---------------------------------------------------------------------------
  logic dep_mask_hazard;
  logic mem_or_tag_hazard;
  logic sb_full;
  logic [$clog2(SCOREBOARD_SLOTS)-1:0] free_slot_idx;

  // Explicit 4-bit dependency mask:
  // bit 0: TFU, bit 1: VFU, bit 2: MFU, bit 3: MPU or LLM_KV
  assign dep_mask_hazard = (dec_inst.dep_mask[0] && queue_busy_o[0]) ||
                           (dec_inst.dep_mask[1] && queue_busy_o[1]) ||
                           (dec_inst.dep_mask[2] && queue_busy_o[2]) ||
                           (dec_inst.dep_mask[3] && (queue_busy_o[3] || queue_busy_o[4]));

  always_comb begin
    mem_or_tag_hazard = 1'b0;
    for (int s = 0; s < SCOREBOARD_SLOTS; s++) begin
      if (sb_valid_q[s] && !is_ctrl_inst) begin
        // Tag ID collision check
        if (sb_tag_q[s] == dec_inst.tag_id) begin
          mem_or_tag_hazard = 1'b1;
        end
        // RAW Hazard: new instruction reads from an in-flight destination region
        if (is_scratchpad_space(dec_inst.src_space) &&
            (sb_dst_space_q[s] == dec_inst.src_space) &&
            (sb_dst_reg_q[s]   == dec_src_reg)) begin
          mem_or_tag_hazard = 1'b1;
        end
        // Implicit WRAM weight read RAW hazard for TFU matrix instructions
        if (dec_uses_wram &&
            (sb_dst_space_q[s] == mlu_pkg::MEM_SPACE_WRAM) &&
            (sb_dst_reg_q[s][5:0] == dec_wram_reg)) begin
          mem_or_tag_hazard = 1'b1;
        end
        // WAW Hazard: new instruction writes to an in-flight destination region
        if (is_scratchpad_space(dec_inst.dst_space) &&
            (sb_dst_space_q[s] == dec_inst.dst_space) &&
            (sb_dst_reg_q[s]   == dec_dst_reg)) begin
          mem_or_tag_hazard = 1'b1;
        end
        // WAR Hazard: new instruction writes to an in-flight source region
        if (is_scratchpad_space(dec_inst.dst_space) &&
            (sb_src_space_q[s] == dec_inst.dst_space) &&
            (sb_src_reg_q[s]   == dec_dst_reg)) begin
          mem_or_tag_hazard = 1'b1;
        end
        if (sb_uses_wram_q[s] &&
            (dec_inst.dst_space == mlu_pkg::MEM_SPACE_WRAM) &&
            (dec_dst_reg[5:0]   == sb_wram_reg_q[s])) begin
          mem_or_tag_hazard = 1'b1;
        end
      end
    end
  end

  // Find first available scoreboard slot
  always_comb begin
    sb_full       = 1'b1;
    free_slot_idx = '0;
    for (int s = SCOREBOARD_SLOTS - 1; s >= 0; s--) begin
      if (!sb_valid_q[s]) begin
        sb_full       = 1'b0;
        free_slot_idx = s[$clog2(SCOREBOARD_SLOTS)-1:0];
      end
    end
  end

  // ---------------------------------------------------------------------------
  // 4. Barrier & Dispatch Handshake Control
  // ---------------------------------------------------------------------------
  logic all_queues_idle;
  logic target_eng_ready;
  logic can_issue_eng;
  logic can_retire_ctrl;

  assign all_queues_idle  = (queue_busy_o == 5'b00000);
  assign target_eng_ready = |(target_q_mask & eng_cmd_ready_i);

  // Wake-up signal to PMU: assert immediately when a valid engine instruction arrives
  assign icu_dispatch_mask_o = (inst_valid_i && !is_ctrl_inst) ? target_q_mask : 5'b00000;

  // Cluster sync request is asserted when OP_SYNC_CLUSTER is valid and local queues are drained
  assign cluster_sync_req_o  = inst_valid_i && is_sync_cluster && all_queues_idle;

  assign can_issue_eng = inst_valid_i && !is_ctrl_inst &&
                         !dep_mask_hazard && !mem_or_tag_hazard && !sb_full;

  assign can_retire_ctrl = inst_valid_i && is_ctrl_inst && !dep_mask_hazard &&
                           (is_sync_cluster ? (all_queues_idle && cluster_sync_ack_i) :
                            is_sync_ipu     ? all_queues_idle : 1'b1);

  assign eng_cmd_valid_o = can_issue_eng ? target_q_mask : 5'b00000;
  assign inst_ready_o    = is_ctrl_inst ? can_retire_ctrl : (can_issue_eng && target_eng_ready);
  assign hazard_stall_o  = inst_valid_i && !inst_ready_o;

  // Count how many engine instructions complete in this cycle
  logic [31:0] done_cnt_comb;
  always_comb begin
    done_cnt_comb = 32'd0;
    for (int e = 0; e < 5; e++) begin
      if (eng_done_valid_i[e]) begin
        done_cnt_comb = done_cnt_comb + 32'd1;
      end
    end
    if (can_retire_ctrl) begin
      done_cnt_comb = done_cnt_comb + 32'd1;
    end
  end

  // ---------------------------------------------------------------------------
  // 5. Sequential Scoreboard & Telemetry Counter Updates
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sb_valid_q           <= '0;
      sb_q_idx_q           <= '0;
      sb_tag_q             <= '0;
      sb_src_space_q       <= '0;
      sb_dst_space_q       <= '0;
      sb_src_reg_q         <= '0;
      sb_dst_reg_q         <= '0;
      sb_uses_wram_q       <= '0;
      sb_wram_reg_q        <= '0;
      pwr_gate_cfg_valid_o <= 1'b0;
      idle_threshold_o     <= 8'd16;
      inst_retired_cnt_o   <= 32'd0;
      hazard_stall_cnt_o   <= 32'd0;
    end else begin
      pwr_gate_cfg_valid_o <= 1'b0;

      // Clear completed scoreboard entries across all 5 execution engines
      for (int s = 0; s < SCOREBOARD_SLOTS; s++) begin
        for (int e = 0; e < 5; e++) begin
          if (eng_done_valid_i[e] && sb_valid_q[s] &&
              (sb_q_idx_q[s] == e[2:0]) && (sb_tag_q[s] == eng_done_tag_i[e])) begin
            sb_valid_q[s] <= 1'b0;
          end
        end
      end

      // Allocate scoreboard slot on successful engine instruction dispatch
      if (can_issue_eng && target_eng_ready) begin
        sb_valid_q[free_slot_idx]     <= 1'b1;
        sb_q_idx_q[free_slot_idx]     <= target_q_idx;
        sb_tag_q[free_slot_idx]       <= dec_inst.tag_id;
        sb_src_space_q[free_slot_idx] <= dec_inst.src_space;
        sb_dst_space_q[free_slot_idx] <= dec_inst.dst_space;
        sb_src_reg_q[free_slot_idx]   <= dec_src_reg;
        sb_dst_reg_q[free_slot_idx]   <= dec_dst_reg;
        sb_uses_wram_q[free_slot_idx] <= dec_uses_wram;
        sb_wram_reg_q[free_slot_idx]  <= dec_wram_reg;
      end

      // Latch dynamic power gate threshold hint on OP_PWR_GATE_CFG
      if (can_retire_ctrl && is_pwr_cfg) begin
        pwr_gate_cfg_valid_o <= 1'b1;
        idle_threshold_o     <= dec_inst.len_or_dims[7:0];
      end

      // Update performance counters
      inst_retired_cnt_o <= inst_retired_cnt_o + done_cnt_comb;
      if (hazard_stall_o) begin
        hazard_stall_cnt_o <= hazard_stall_cnt_o + 32'd1;
      end
    end
  end

  // Tie off unused instruction fields cleanly for zero Verilator -Wall warnings
  wire _unused_ok = &{1'b0, dec_inst.prec, dec_inst.sparse_mode,
                      dec_inst.dst_addr[9:0], dec_inst.src0_addr[9:0],
                      dec_inst.src1_or_strd[9:0], dec_inst.len_or_dims[15:8]};

endmodule : mlu_bang_icu
