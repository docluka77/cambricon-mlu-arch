// =============================================================================
// File: uvm_tb/uvm_bang_icu_pmu/dpi_icu_pmu_ref.cpp
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: C++17 Cycle-Accurate Bit-Exact DPI-C Reference Model for
//              mlu_bang_icu (8-slot RAW/WAR/WAW/dep_mask scoreboard) and
//              mlu_pmu_clock_gate (0-cycle wakeup & SRAM light/deep sleep).
// =============================================================================
#include <cstdint>
#include <cstring>

static int      g_icu_status = 0;
static uint32_t g_icu_dpi_calls = 0;

struct IcuPmuState {
  bool     sb_valid[8];
  uint8_t  sb_q_idx[8];
  uint8_t  sb_tag[8];
  uint8_t  sb_src_space[8];
  uint8_t  sb_dst_space[8];
  uint32_t sb_src_reg[8];
  uint32_t sb_dst_reg[8];
  bool     sb_uses_wram[8];
  uint8_t  sb_wram_reg[8];

  bool     pwr_gate_cfg_valid_q;
  uint8_t  idle_threshold_o_q;
  uint32_t inst_retired_cnt_q;
  uint32_t hazard_stall_cnt_q;

  uint8_t  pmu_idle_thresh_q;
  uint16_t eng_idle_cnt_q[5];
  uint16_t mem_idle_cnt_q[3];
  uint8_t  sram_slp_q;
  uint8_t  sram_dslp_q;
  uint32_t active_mac_cycles_q;
  uint32_t gated_saved_cycles_q;
  uint32_t sram_sleep_cycles_q;

  // Combinational outputs evaluated on current cycle before posedge
  uint8_t  exp_inst_ready;
  uint8_t  exp_eng_cmd_valid;
  uint8_t  exp_icu_dispatch_mask;
  uint8_t  exp_cluster_sync_req;
  uint8_t  exp_queue_busy;
  uint8_t  exp_hazard_stall;
  uint32_t exp_inst_retired_cnt;
  uint32_t exp_hazard_stall_cnt;
  uint8_t  exp_eng_clk_en;
  uint8_t  exp_sram_slp;
  uint8_t  exp_sram_dslp;
  uint8_t  exp_sram_wake_ready;
  uint32_t exp_gated_saved_cycles;
  uint32_t exp_sram_sleep_cycles;
} g_st;

static bool is_scratchpad(uint8_t sp) {
  return (sp == 0U || sp == 1U || sp == 2U);
}

extern "C" void dpi_icu_set_status(int status) { g_icu_status = status; }
extern "C" int  dpi_icu_get_status() { return g_icu_status; }
extern "C" uint32_t dpi_icu_get_calls() { return g_icu_dpi_calls; }

extern "C" void dpi_icu_reset() {
  std::memset(&g_st, 0, sizeof(g_st));
  g_st.idle_threshold_o_q = 16;
  g_st.pmu_idle_thresh_q  = 4;
}

extern "C" void dpi_icu_eval_and_step(
  uint32_t inst_valid,
  uint64_t inst_hi,
  uint64_t inst_lo,
  uint32_t eng_ready,
  uint32_t cluster_ack,
  uint32_t done_valid,
  uint64_t done_tags_packed
) {
  g_icu_dpi_calls++;

  uint8_t  opcode       = (inst_hi >> 58) & 0x3FU;
  uint8_t  engine       = (inst_hi >> 55) & 0x07U;
  uint8_t  src_space    = (inst_hi >> 47) & 0x07U;
  uint8_t  dst_space    = (inst_hi >> 44) & 0x07U;
  uint8_t  dep_mask     = (inst_hi >> 40) & 0x0FU;
  uint8_t  tag_id       = (inst_hi >> 32) & 0xFFU;
  uint32_t dst_addr     = (uint32_t)(inst_hi & 0xFFFFFFFFULL);
  uint32_t src0_addr    = (uint32_t)((inst_lo >> 32) & 0xFFFFFFFFULL);
  uint16_t src1_or_strd = (uint16_t)((inst_lo >> 16) & 0xFFFFULL);
  uint16_t len_or_dims  = (uint16_t)(inst_lo & 0xFFFFULL);
  bool is_sync_ipu     = (opcode == 0x01U);
  bool is_sync_cluster = (opcode == 0x02U);
  bool is_pwr_cfg      = (opcode == 0x03U);
  bool is_ctrl_inst    = (engine == 0U) || (opcode == 0x00U) || is_sync_ipu || is_sync_cluster || is_pwr_cfg;

  uint8_t target_q_idx = 0;
  uint8_t target_q_mask = 0;
  if (!is_ctrl_inst) {
    switch (engine) {
      case 1: target_q_idx = 0; target_q_mask = 0x01; break;
      case 2: target_q_idx = 1; target_q_mask = 0x02; break;
      case 3: target_q_idx = 2; target_q_mask = 0x04; break;
      case 4: target_q_idx = 3; target_q_mask = 0x08; break;
      case 5: target_q_idx = 4; target_q_mask = 0x10; break;
      default: target_q_idx = 0; target_q_mask = 0x01; break;
    }
  }

  uint8_t q_busy = 0;
  for (int s = 0; s < 8; s++) {
    if (g_st.sb_valid[s] && g_st.sb_q_idx[s] < 5) {
      q_busy |= (1U << g_st.sb_q_idx[s]);
    }
  }

  uint32_t dec_src_reg  = (src0_addr >> 10) & 0x3FFFFFU;
  uint32_t dec_dst_reg  = (dst_addr >> 10) & 0x3FFFFFU;
  uint8_t  dec_wram_reg = (src1_or_strd >> 10) & 0x3FU;
  bool     dec_uses_wram = (engine == 1U);

  bool dep_mask_hazard =
    ((dep_mask & 1U) && (q_busy & 1U)) ||
    ((dep_mask & 2U) && (q_busy & 2U)) ||
    ((dep_mask & 4U) && (q_busy & 4U)) ||
    ((dep_mask & 8U) && (q_busy & 0x18U));

  bool mem_or_tag_hazard = false;
  for (int s = 0; s < 8; s++) {
    if (g_st.sb_valid[s] && !is_ctrl_inst) {
      if (g_st.sb_tag[s] == tag_id) mem_or_tag_hazard = true;
      if (is_scratchpad(src_space) && g_st.sb_dst_space[s] == src_space && g_st.sb_dst_reg[s] == dec_src_reg)
        mem_or_tag_hazard = true;
      if (dec_uses_wram && g_st.sb_dst_space[s] == 1U && (g_st.sb_dst_reg[s] & 0x3FU) == dec_wram_reg)
        mem_or_tag_hazard = true;
      if (is_scratchpad(dst_space) && g_st.sb_dst_space[s] == dst_space && g_st.sb_dst_reg[s] == dec_dst_reg)
        mem_or_tag_hazard = true;
      if (is_scratchpad(dst_space) && g_st.sb_src_space[s] == dst_space && g_st.sb_src_reg[s] == dec_dst_reg)
        mem_or_tag_hazard = true;
      if (g_st.sb_uses_wram[s] && dst_space == 1U && (dec_dst_reg & 0x3FU) == g_st.sb_wram_reg[s])
        mem_or_tag_hazard = true;
    }
  }

  bool sb_full = true;
  int free_slot = 0;
  for (int s = 7; s >= 0; s--) {
    if (!g_st.sb_valid[s]) {
      sb_full = false;
      free_slot = s;
    }
  }

  bool all_idle = (q_busy == 0);
  bool target_ready = ((target_q_mask & (uint8_t)eng_ready) != 0);
  uint8_t icu_disp_mask = (inst_valid && !is_ctrl_inst) ? target_q_mask : 0U;
  uint8_t cluster_req   = (inst_valid && is_sync_cluster && all_idle) ? 1U : 0U;
  bool can_issue_eng    = (inst_valid != 0) && !is_ctrl_inst && !dep_mask_hazard && !mem_or_tag_hazard && !sb_full;
  bool can_retire_ctrl  = (inst_valid != 0) && is_ctrl_inst && !dep_mask_hazard &&
                          (is_sync_cluster ? (all_idle && (cluster_ack != 0)) :
                           is_sync_ipu     ? all_idle : true);

  uint8_t eng_cmd_valid = can_issue_eng ? target_q_mask : 0U;
  uint8_t inst_ready    = is_ctrl_inst ? (can_retire_ctrl ? 1U : 0U) : ((can_issue_eng && target_ready) ? 1U : 0U);
  uint8_t hazard_stall  = (inst_valid != 0 && !inst_ready) ? 1U : 0U;

  // PMU combinational evaluation
  uint8_t eng_clk_en = 0;
  for (int e = 0; e < 5; e++) {
    bool b = ((q_busy >> e) & 1U) || ((icu_disp_mask >> e) & 1U);
    if (b || g_st.eng_idle_cnt_q[e] < (uint16_t)g_st.pmu_idle_thresh_q) {
      eng_clk_en |= (1U << e);
    }
  }

  g_st.exp_inst_ready         = inst_ready;
  g_st.exp_eng_cmd_valid      = eng_cmd_valid;
  g_st.exp_icu_dispatch_mask  = icu_disp_mask;
  g_st.exp_cluster_sync_req   = cluster_req;
  g_st.exp_queue_busy         = q_busy;
  g_st.exp_hazard_stall       = hazard_stall;
  g_st.exp_inst_retired_cnt   = g_st.inst_retired_cnt_q;
  g_st.exp_hazard_stall_cnt   = g_st.hazard_stall_cnt_q;
  g_st.exp_eng_clk_en         = eng_clk_en;
  g_st.exp_sram_slp           = g_st.sram_slp_q;
  g_st.exp_sram_dslp          = g_st.sram_dslp_q;
  g_st.exp_sram_wake_ready    = (~(g_st.sram_slp_q | g_st.sram_dslp_q)) & 0x07U;
  g_st.exp_gated_saved_cycles = g_st.gated_saved_cycles_q;
  g_st.exp_sram_sleep_cycles  = g_st.sram_sleep_cycles_q;
  // Sequential state update (modeling posedge clk)
  uint32_t done_cnt = 0;
  for (int e = 0; e < 5; e++) {
    if ((done_valid >> e) & 1U) done_cnt++;
  }
  if (can_retire_ctrl) done_cnt++;

  // PMU sequential update uses pre-posedge signals
  uint16_t deep_thresh = (g_st.pmu_idle_thresh_q == 0) ? 4 : ((uint16_t)g_st.pmu_idle_thresh_q << 1);
  uint8_t mem_active = (((q_busy >> 3) & 1U) << 2) |
                       (((q_busy >> 0) & 1U) << 1) |
                       (((q_busy >> 0) | (q_busy >> 2)) & 1U);
  bool mem_wake[3];
  mem_wake[0] = (mem_active & 1U) || ((icu_disp_mask & 0x07U) != 0);
  mem_wake[1] = (mem_active & 2U) || ((icu_disp_mask & 0x05U) != 0);
  mem_wake[2] = (mem_active & 4U) || ((icu_disp_mask & 0x1CU) != 0);

  uint32_t gated_inc = 0;
  for (int e = 0; e < 5; e++) {
    if (((eng_clk_en >> e) & 1U) == 0) gated_inc++;
  }
  uint32_t sleep_inc = 0;
  for (int m = 0; m < 3; m++) {
    if (((g_st.sram_slp_q >> m) & 1U) || ((g_st.sram_dslp_q >> m) & 1U)) sleep_inc++;
  }

  if (g_st.pwr_gate_cfg_valid_q) {
    g_st.pmu_idle_thresh_q = (g_st.idle_threshold_o_q == 0) ? 1 : g_st.idle_threshold_o_q;
  }
  for (int e = 0; e < 5; e++) {
    if (((q_busy >> e) & 1U) || ((icu_disp_mask >> e) & 1U)) {
      g_st.eng_idle_cnt_q[e] = 0;
    } else if (g_st.eng_idle_cnt_q[e] < 0x1FE) {
      g_st.eng_idle_cnt_q[e]++;
    }
  }
  for (int m = 0; m < 3; m++) {
    if (mem_wake[m]) {
      g_st.mem_idle_cnt_q[m] = 0;
      g_st.sram_slp_q  &= ~(1U << m);
      g_st.sram_dslp_q &= ~(1U << m);
    } else {
      uint16_t next_c = g_st.mem_idle_cnt_q[m] + 1;
      if (g_st.mem_idle_cnt_q[m] < 0x1FE) g_st.mem_idle_cnt_q[m] = next_c;
      if (next_c >= deep_thresh) {
        g_st.sram_slp_q  &= ~(1U << m);
        g_st.sram_dslp_q |=  (1U << m);
      } else if (next_c >= (uint16_t)g_st.pmu_idle_thresh_q) {
        g_st.sram_slp_q  |=  (1U << m);
        g_st.sram_dslp_q &= ~(1U << m);
      }
    }
  }
  if (q_busy & 1U) g_st.active_mac_cycles_q++;
  g_st.gated_saved_cycles_q += gated_inc;
  g_st.sram_sleep_cycles_q  += sleep_inc;

  // ICU sequential update
  g_st.pwr_gate_cfg_valid_q = false;
  for (int s = 0; s < 8; s++) {
    for (int e = 0; e < 5; e++) {
      uint8_t dtag = (uint8_t)((done_tags_packed >> (e * 8)) & 0xFFULL);
      if (((done_valid >> e) & 1U) && g_st.sb_valid[s] &&
          g_st.sb_q_idx[s] == (uint8_t)e && g_st.sb_tag[s] == dtag) {
        g_st.sb_valid[s] = false;
      }
    }
  }
  if (can_issue_eng && target_ready) {
    g_st.sb_valid[free_slot]     = true;
    g_st.sb_q_idx[free_slot]     = target_q_idx;
    g_st.sb_tag[free_slot]       = tag_id;
    g_st.sb_src_space[free_slot] = src_space;
    g_st.sb_dst_space[free_slot] = dst_space;
    g_st.sb_src_reg[free_slot]   = dec_src_reg;
    g_st.sb_dst_reg[free_slot]   = dec_dst_reg;
    g_st.sb_uses_wram[free_slot] = dec_uses_wram;
    g_st.sb_wram_reg[free_slot]  = dec_wram_reg;
  }
  if (can_retire_ctrl && is_pwr_cfg) {
    g_st.pwr_gate_cfg_valid_q = true;
    g_st.idle_threshold_o_q   = (uint8_t)(len_or_dims & 0xFFU);
  }
  g_st.inst_retired_cnt_q += done_cnt;
  if (hazard_stall) g_st.hazard_stall_cnt_q++;
}

extern "C" uint32_t dpi_icu_exp_inst_ready()        { return g_st.exp_inst_ready; }
extern "C" uint32_t dpi_icu_exp_eng_cmd_valid()     { return g_st.exp_eng_cmd_valid; }
extern "C" uint32_t dpi_icu_exp_dispatch_mask()     { return g_st.exp_icu_dispatch_mask; }
extern "C" uint32_t dpi_icu_exp_cluster_sync_req()  { return g_st.exp_cluster_sync_req; }
extern "C" uint32_t dpi_icu_exp_queue_busy()        { return g_st.exp_queue_busy; }
extern "C" uint32_t dpi_icu_exp_hazard_stall()      { return g_st.exp_hazard_stall; }
extern "C" uint32_t dpi_icu_exp_inst_retired_cnt()  { return g_st.exp_inst_retired_cnt; }
extern "C" uint32_t dpi_icu_exp_hazard_stall_cnt()  { return g_st.exp_hazard_stall_cnt; }
extern "C" uint32_t dpi_pmu_exp_eng_clk_en()        { return g_st.exp_eng_clk_en; }
extern "C" uint32_t dpi_pmu_exp_sram_slp()          { return g_st.exp_sram_slp; }
extern "C" uint32_t dpi_pmu_exp_sram_dslp()         { return g_st.exp_sram_dslp; }
extern "C" uint32_t dpi_pmu_exp_sram_wake_ready()   { return g_st.exp_sram_wake_ready; }
extern "C" uint32_t dpi_pmu_exp_gated_saved_cycles(){ return g_st.exp_gated_saved_cycles; }
extern "C" uint32_t dpi_pmu_exp_sram_sleep_cycles() { return g_st.exp_sram_sleep_cycles; }
