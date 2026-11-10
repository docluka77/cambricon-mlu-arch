//      // verilator_coverage annotation
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
 002412   input  logic             clk_i,
%000004   input  logic             rst_ni,
        
          // Fetch / Upstream Instruction Stream
 000294   input  logic             inst_valid_i,
 000322   output logic             inst_ready_o,
~000493   input  logic [127:0]     inst_i,
        
          // 5 Execution Queue Dispatch Interfaces
          // [0]=ENG_TFU_MAT, [1]=ENG_VFU_VEC, [2]=ENG_MFU_DMA, [3]=ENG_MPU_COL, [4]=ENG_LLM_KV
~000069   output logic [4:0]       eng_cmd_valid_o,
~000013   input  logic [4:0]       eng_cmd_ready_i,
~000493   output logic [127:0]     eng_cmd_inst_o,
~000069   output logic [4:0]       icu_dispatch_mask_o,
        
          // Dynamic Power/Clock Gate Hint Interface (OP_PWR_GATE_CFG)
%000001   output logic             pwr_gate_cfg_valid_o,
%000004   output logic [7:0]       idle_threshold_o,
        
          // MTP Cluster Hardware Union-Task Barrier Interface (OP_SYNC_CLUSTER)
~000010   output logic             cluster_sync_req_o,
~000010   input  logic             cluster_sync_ack_i,
        
          // Execution Engine Completion Interface
~000069   input  logic [4:0]       eng_done_valid_i,
~000050   input  logic [4:0][7:0]  eng_done_tag_i,
        
          // Status & Performance Telemetry Counters
~000069   output logic [4:0]       queue_busy_o,
 000311   output logic             hazard_stall_o,
~000161   output logic [31:0]      inst_retired_cnt_o,
~000106   output logic [31:0]      hazard_stall_cnt_o
        );
        
          // ---------------------------------------------------------------------------
          // 1. Instruction Field Decode
          // ---------------------------------------------------------------------------
~000278   mlu_pkg::mlu_inst_t dec_inst;
          assign dec_inst       = inst_i;
          assign eng_cmd_inst_o = inst_i;
        
 000284   logic is_ctrl_inst;
~000010   logic is_sync_ipu;
~000010   logic is_sync_cluster;
%000001   logic is_pwr_cfg;
        
          assign is_sync_ipu     = (dec_inst.opcode == mlu_pkg::OP_SYNC_IPU);
          assign is_sync_cluster = (dec_inst.opcode == mlu_pkg::OP_SYNC_CLUSTER);
          assign is_pwr_cfg      = (dec_inst.opcode == mlu_pkg::OP_PWR_GATE_CFG);
          assign is_ctrl_inst    = (dec_inst.engine == mlu_pkg::ENG_ICU_CTRL) ||
                                   (dec_inst.opcode == mlu_pkg::OP_NOP)       ||
                                   is_sync_ipu || is_sync_cluster || is_pwr_cfg;
        
          // Map target engine enum to 0..4 queue index and 5-bit one-hot mask
~000123   logic [2:0] target_q_idx;
~000069   logic [4:0] target_q_mask;
        
 001483   always_comb begin
 001483     target_q_idx  = 3'd0;
 001483     target_q_mask = 5'b00000;
 000852     if (!is_ctrl_inst) begin
 000852       unique case (dec_inst.engine)
 000166         mlu_pkg::ENG_TFU_MAT: begin target_q_idx = 3'd0; target_q_mask = 5'b00001; end
 000168         mlu_pkg::ENG_VFU_VEC: begin target_q_idx = 3'd1; target_q_mask = 5'b00010; end
 000188         mlu_pkg::ENG_MFU_DMA: begin target_q_idx = 3'd2; target_q_mask = 5'b00100; end
~000166         mlu_pkg::ENG_MPU_COL: begin target_q_idx = 3'd3; target_q_mask = 5'b01000; end
~000164         mlu_pkg::ENG_LLM_KV:  begin target_q_idx = 3'd4; target_q_mask = 5'b10000; end
%000000         default:              begin target_q_idx = 3'd0; target_q_mask = 5'b00001; end
              endcase
            end
          end
        
          // ---------------------------------------------------------------------------
          // 2. Multi-Queue In-Flight Scoreboard Storage
          // ---------------------------------------------------------------------------
~000301   logic [SCOREBOARD_SLOTS-1:0]       sb_valid_q;
~000060   logic [SCOREBOARD_SLOTS-1:0][2:0]  sb_q_idx_q;
~000074   logic [SCOREBOARD_SLOTS-1:0][7:0]  sb_tag_q;
~000048   logic [SCOREBOARD_SLOTS-1:0][2:0]  sb_src_space_q;
~000090   logic [SCOREBOARD_SLOTS-1:0][2:0]  sb_dst_space_q;
~000063   logic [SCOREBOARD_SLOTS-1:0][21:0] sb_src_reg_q;
~000062   logic [SCOREBOARD_SLOTS-1:0][21:0] sb_dst_reg_q;
~000030   logic [SCOREBOARD_SLOTS-1:0]       sb_uses_wram_q;
~000080   logic [SCOREBOARD_SLOTS-1:0][5:0]  sb_wram_reg_q;
        
          // Compute per-queue busy flags from active scoreboard slots
 002416   always_comb begin
 002416     queue_busy_o = 5'b00000;
 019328     for (int s = 0; s < SCOREBOARD_SLOTS; s++) begin
 019155       if (sb_valid_q[s]) begin
~000472         if (sb_q_idx_q[s] < 3'd5) begin
 000472           queue_busy_o[sb_q_idx_q[s]] = 1'b1;
                end
              end
            end
          end
        
          // Helper: check if memory space is an on-chip scratchpad subject to hazard checks
 002619   function automatic logic is_scratchpad_space(input logic [2:0] sp);
 002619     is_scratchpad_space = (sp == mlu_pkg::MEM_SPACE_NRAM) ||
 002619                           (sp == mlu_pkg::MEM_SPACE_WRAM) ||
                                  (sp == mlu_pkg::MEM_SPACE_SRAM);
          endfunction
        
          // Address region extraction (1 KB granularity: bits [31:10])
~000203   logic [21:0] dec_src_reg;
~000142   logic [21:0] dec_dst_reg;
~000080   logic [5:0]  dec_wram_reg;
~000058   logic        dec_uses_wram;
        
          assign dec_src_reg   = dec_inst.src0_addr[31:10];
          assign dec_dst_reg   = dec_inst.dst_addr[31:10];
          assign dec_wram_reg  = dec_inst.src1_or_strd[15:10];
          assign dec_uses_wram = (dec_inst.engine == mlu_pkg::ENG_TFU_MAT);
        
          // ---------------------------------------------------------------------------
          // 3. Hazard Detection (RAW / WAR / WAW / Tag Collision / Explicit dep_mask)
          // ---------------------------------------------------------------------------
~000108   logic dep_mask_hazard;
 000301   logic mem_or_tag_hazard;
%000000   logic sb_full;
~000301   logic [$clog2(SCOREBOARD_SLOTS)-1:0] free_slot_idx;
        
          // Explicit 4-bit dependency mask:
          // bit 0: TFU, bit 1: VFU, bit 2: MFU, bit 3: MPU or LLM_KV
          assign dep_mask_hazard = (dec_inst.dep_mask[0] && queue_busy_o[0]) ||
                                   (dec_inst.dep_mask[1] && queue_busy_o[1]) ||
                                   (dec_inst.dep_mask[2] && queue_busy_o[2]) ||
                                   (dec_inst.dep_mask[3] && (queue_busy_o[3] || queue_busy_o[4]));
        
 003427   always_comb begin
 003427     mem_or_tag_hazard = 1'b0;
 027416     for (int s = 0; s < SCOREBOARD_SLOTS; s++) begin
 026543       if (sb_valid_q[s] && !is_ctrl_inst) begin
                // Tag ID collision check
~000572         if (sb_tag_q[s] == dec_inst.tag_id) begin
 000301           mem_or_tag_hazard = 1'b1;
                end
                // RAW Hazard: new instruction reads from an in-flight destination region
~000520         if (is_scratchpad_space(dec_inst.src_space) &&
                    (sb_dst_space_q[s] == dec_inst.src_space) &&
 000520             (sb_dst_reg_q[s]   == dec_src_reg)) begin
 000520           mem_or_tag_hazard = 1'b1;
                end
                // Implicit WRAM weight read RAW hazard for TFU matrix instructions
~000869         if (dec_uses_wram &&
                    (sb_dst_space_q[s] == mlu_pkg::MEM_SPACE_WRAM) &&
%000004             (sb_dst_reg_q[s][5:0] == dec_wram_reg)) begin
%000004           mem_or_tag_hazard = 1'b1;
                end
                // WAW Hazard: new instruction writes to an in-flight destination region
~000556         if (is_scratchpad_space(dec_inst.dst_space) &&
                    (sb_dst_space_q[s] == dec_inst.dst_space) &&
 000317             (sb_dst_reg_q[s]   == dec_dst_reg)) begin
 000317           mem_or_tag_hazard = 1'b1;
                end
                // WAR Hazard: new instruction writes to an in-flight source region
~000857         if (is_scratchpad_space(dec_inst.dst_space) &&
                    (sb_src_space_q[s] == dec_inst.dst_space) &&
 000017             (sb_src_reg_q[s]   == dec_dst_reg)) begin
 000017           mem_or_tag_hazard = 1'b1;
                end
~000873         if (sb_uses_wram_q[s] &&
                    (dec_inst.dst_space == mlu_pkg::MEM_SPACE_WRAM) &&
%000000             (dec_dst_reg[5:0]   == sb_wram_reg_q[s])) begin
%000000           mem_or_tag_hazard = 1'b1;
                end
              end
            end
          end
        
          // Find first available scoreboard slot
 002416   always_comb begin
 002416     sb_full       = 1'b1;
 002416     free_slot_idx = '0;
 019328     for (int s = SCOREBOARD_SLOTS - 1; s >= 0; s--) begin
 019155       if (!sb_valid_q[s]) begin
 019155         sb_full       = 1'b0;
 019155         free_slot_idx = s[$clog2(SCOREBOARD_SLOTS)-1:0];
              end
            end
          end
        
          // ---------------------------------------------------------------------------
          // 4. Barrier & Dispatch Handshake Control
          // ---------------------------------------------------------------------------
 000302   logic all_queues_idle;
 000283   logic target_eng_ready;
 000301   logic can_issue_eng;
~000021   logic can_retire_ctrl;
        
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
~000322   logic [31:0] done_cnt_comb;
 004111   always_comb begin
 004111     done_cnt_comb = 32'd0;
 020555     for (int e = 0; e < 5; e++) begin
 019351       if (eng_done_valid_i[e]) begin
 001204         done_cnt_comb = done_cnt_comb + 32'd1;
              end
            end
~004017     if (can_retire_ctrl) begin
~000094       done_cnt_comb = done_cnt_comb + 32'd1;
            end
          end
        
          // ---------------------------------------------------------------------------
          // 5. Sequential Scoreboard & Telemetry Counter Updates
          // ---------------------------------------------------------------------------
 002412   always_ff @(posedge clk_i or negedge rst_ni) begin
~002400     if (!rst_ni) begin
~000012       sb_valid_q           <= '0;
~000012       sb_q_idx_q           <= '0;
~000012       sb_tag_q             <= '0;
~000012       sb_src_space_q       <= '0;
~000012       sb_dst_space_q       <= '0;
~000012       sb_src_reg_q         <= '0;
~000012       sb_dst_reg_q         <= '0;
~000012       sb_uses_wram_q       <= '0;
~000012       sb_wram_reg_q        <= '0;
~000012       pwr_gate_cfg_valid_o <= 1'b0;
~000012       idle_threshold_o     <= 8'd16;
~000012       inst_retired_cnt_o   <= 32'd0;
~000012       hazard_stall_cnt_o   <= 32'd0;
 002400     end else begin
 002400       pwr_gate_cfg_valid_o <= 1'b0;
        
              // Clear completed scoreboard entries across all 5 execution engines
 019200       for (int s = 0; s < SCOREBOARD_SLOTS; s++) begin
 096000         for (int e = 0; e < 5; e++) begin
 095975           if (eng_done_valid_i[e] && sb_valid_q[s] &&
 000301               (sb_q_idx_q[s] == e[2:0]) && (sb_tag_q[s] == eng_done_tag_i[e])) begin
 000301             sb_valid_q[s] <= 1'b0;
                  end
                end
              end
        
              // Allocate scoreboard slot on successful engine instruction dispatch
 002375       if (can_issue_eng && target_eng_ready) begin
 000301         sb_valid_q[free_slot_idx]     <= 1'b1;
 000301         sb_q_idx_q[free_slot_idx]     <= target_q_idx;
 000301         sb_tag_q[free_slot_idx]       <= dec_inst.tag_id;
 000301         sb_src_space_q[free_slot_idx] <= dec_inst.src_space;
 000301         sb_dst_space_q[free_slot_idx] <= dec_inst.dst_space;
 000301         sb_src_reg_q[free_slot_idx]   <= dec_src_reg;
 000301         sb_dst_reg_q[free_slot_idx]   <= dec_dst_reg;
 000301         sb_uses_wram_q[free_slot_idx] <= dec_uses_wram;
 000301         sb_wram_reg_q[free_slot_idx]  <= dec_wram_reg;
              end
        
              // Latch dynamic power gate threshold hint on OP_PWR_GATE_CFG
~002400       if (can_retire_ctrl && is_pwr_cfg) begin
%000001         pwr_gate_cfg_valid_o <= 1'b1;
%000001         idle_threshold_o     <= dec_inst.len_or_dims[7:0];
              end
        
              // Update performance counters
 002400       inst_retired_cnt_o <= inst_retired_cnt_o + done_cnt_comb;
~002392       if (hazard_stall_o) begin
~000211         hazard_stall_cnt_o <= hazard_stall_cnt_o + 32'd1;
              end
            end
          end
        
          // Tie off unused instruction fields cleanly for zero Verilator -Wall warnings
          wire _unused_ok = &{1'b0, dec_inst.prec, dec_inst.sparse_mode,
                              dec_inst.dst_addr[9:0], dec_inst.src0_addr[9:0],
                              dec_inst.src1_or_strd[9:0], dec_inst.len_or_dims[15:8]};
        
        endmodule : mlu_bang_icu
        
