// =============================================================================
// File: uvm_tb/uvm_mlu_link_noc/dpi_link_noc_ref.cpp
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Cycle-Accurate Bit-Exact C++17 DPI-C Reference Model for
//              mlu_link_noc_router (ROUTER_ID=1) + mlu_c2c_serdes_pcs (REPLAY_DEPTH=8).
// =============================================================================
#include <cstdint>
#include <cstring>

namespace {

struct Flit128 {
  uint64_t lo;
  uint64_t hi;
};

int      g_status    = 1;
uint32_t g_dpi_calls = 0;

// Router State (ROUTER_ID = 1)
constexpr uint32_t ROUTER_ID = 1u;
bool     r_vc0_valid[5], r_vc1_valid[5];
Flit128  r_vc0_flit[5],  r_vc1_flit[5];
uint32_t r_vc0_dst_p[5], r_vc1_dst_p[5];
bool     r_lock_active[5];
uint32_t r_lock_in_p[5];
bool     r_lock_vc[5];
uint32_t r_rr_ptr[5];
uint32_t r_routed_cnt = 0;
uint32_t r_vc1_cnt    = 0;

// Router Combinational Latched Inputs & Outputs
bool     in_allreduce_en = false;
bool     in_port_valid[5];
Flit128  in_port_flit[5];
bool     in_out_ready[5];

bool     comb_in_ready[5];
bool     comb_vc0_push[5], comb_vc1_push[5];
bool     comb_vc0_pop[5],  comb_vc1_pop[5];
bool     comb_out_grant_v[5];
uint32_t comb_out_grant_in_p[5];
bool     comb_out_grant_vc[5];
bool     comb_out_ar_any[5];
Flit128  comb_out_flit[5];

// SerDes PCS State (REPLAY_DEPTH = 8)
uint32_t s_tx_seq          = 0;
bool     s_replay_active   = false;
uint32_t s_replay_curr_seq = 0;
Flit128  s_replay_buf[8];
uint32_t s_rx_exp_seq      = 0;
uint32_t s_crc_err_cnt     = 0;
uint32_t s_retransmit_cnt  = 0;

// SerDes Combinational Inputs & Outputs
bool     in_tx_valid       = false;
Flit128  in_tx_flit        = {0ULL, 0ULL};
bool     in_err_inject_crc = false;
bool     in_replay_trigger = false;
uint32_t in_replay_seq     = 0;

bool     comb_tx_ready     = true;
Flit128  comb_tx_formed    = {0ULL, 0ULL};
bool     comb_link_valid   = false;
Flit128  comb_link_flit    = {0ULL, 0ULL};
bool     comb_rx_valid     = false;
Flit128  comb_rx_flit      = {0ULL, 0ULL};
bool     comb_ack_valid    = false;
uint32_t comb_ack_seq      = 0;
bool     comb_nack_valid   = false;
uint32_t comb_nack_seq     = 0;
bool     comb_rx_crc_ok    = false;
bool     comb_rx_seq_ok    = false;

inline uint32_t route_lookup(uint32_t dst_id) {
  dst_id &= 0xFu;
  if (dst_id == ROUTER_ID) return 0u;
  uint32_t top2 = (dst_id >> 2) & 0x3u;
  if (top2 == 3u) return 4u;
  if (top2 == 2u) return 3u;
  if (top2 == 1u) return 2u;
  return ((dst_id & 0x3u) > (ROUTER_ID & 0x3u)) ? 1u : 2u;
}

inline uint16_t calc_crc16_ccitt(uint64_t hi, uint64_t lo) {
  uint16_t crc = 0xFFFFu;
  uint16_t top16 = static_cast<uint16_t>((hi >> 48) & 0xFFFFULL);
  uint32_t mid32 = static_cast<uint32_t>(hi & 0xFFFFFFFFULL);
  for (int i = 111; i >= 0; i--) {
    uint32_t bit_i = 0u;
    if (i >= 96)      bit_i = (top16 >> (i - 96)) & 1u;
    else if (i >= 64) bit_i = (mid32 >> (i - 64)) & 1u;
    else              bit_i = static_cast<uint32_t>((lo >> i) & 1ULL);
    uint32_t fb = bit_i ^ ((crc >> 15) & 1u);
    crc = static_cast<uint16_t>(((crc << 1) & 0xFFFFu) ^ (fb ? 0x1021u : 0x0000u));
  }
  return crc;
}

} // namespace

extern "C" {

void dpi_noc_set_status(int status) { g_status = status; }
int  dpi_noc_get_status()           { return g_status; }
uint32_t dpi_noc_get_calls()        { return g_dpi_calls; }

void dpi_noc_ref_reset() {
  for (int p = 0; p < 5; p++) {
    r_vc0_valid[p] = false; r_vc1_valid[p] = false;
    r_vc0_flit[p]  = {0ULL, 0ULL}; r_vc1_flit[p] = {0ULL, 0ULL};
    r_vc0_dst_p[p] = 0u; r_vc1_dst_p[p] = 0u;
    r_lock_active[p] = false; r_lock_in_p[p] = 0u; r_lock_vc[p] = false;
    r_rr_ptr[p] = 0u;
    in_port_valid[p] = false; in_port_flit[p] = {0ULL, 0ULL}; in_out_ready[p] = true;
  }
  r_routed_cnt      = 0u;
  r_vc1_cnt         = 0u;
  s_tx_seq          = 0u;
  s_replay_active   = false;
  s_replay_curr_seq = 0u;
  s_rx_exp_seq      = 0u;
  s_crc_err_cnt     = 0u;
  s_retransmit_cnt  = 0u;
  for (int i = 0; i < 8; i++) s_replay_buf[i] = {0ULL, 0ULL};
}

void dpi_noc_ref_set_router_port(int p, uint32_t in_valid, uint64_t flit_lo, uint64_t flit_hi, uint32_t out_ready) {
  if (p < 0 || p >= 5) return;
  in_port_valid[p] = (in_valid & 1u) != 0u;
  in_port_flit[p]  = {flit_lo, flit_hi};
  in_out_ready[p]  = (out_ready & 1u) != 0u;
}

void dpi_noc_ref_set_global_and_serdes(
  uint32_t allreduce_en,
  uint32_t tx_valid,
  uint64_t tx_flit_lo,
  uint64_t tx_flit_hi,
  uint32_t err_inject_crc,
  uint32_t replay_trigger,
  uint32_t replay_seq
) {
  in_allreduce_en   = (allreduce_en & 1u) != 0u;
  in_tx_valid       = (tx_valid & 1u) != 0u;
  in_tx_flit        = {tx_flit_lo, tx_flit_hi};
  in_err_inject_crc = (err_inject_crc & 1u) != 0u;
  in_replay_trigger = (replay_trigger & 1u) != 0u;
  in_replay_seq     = replay_seq & 0x1Fu;
}

void dpi_noc_ref_eval_comb() {
  g_dpi_calls++;
  for (int p = 0; p < 5; p++) {
    comb_vc0_pop[p] = false;
    comb_vc1_pop[p] = false;
  }

  for (int op = 0; op < 5; op++) {
    comb_out_grant_v[op]    = false;
    comb_out_grant_in_p[op] = 0u;
    comb_out_grant_vc[op]   = false;
    comb_out_ar_any[op]     = false;
    comb_out_flit[op]       = {0ULL, 0ULL};

    if (r_lock_active[op]) {
      uint32_t lp = r_lock_in_p[op];
      if (r_lock_vc[op]) {
        if (r_vc1_valid[lp]) {
          comb_out_grant_v[op]    = true;
          comb_out_grant_in_p[op] = lp;
          comb_out_grant_vc[op]   = true;
          comb_out_flit[op]       = r_vc1_flit[lp];
          if (in_out_ready[op]) comb_vc1_pop[lp] = true;
        }
      end_lock_vc:;
      } else {
        if (r_vc0_valid[lp]) {
          comb_out_grant_v[op]    = true;
          comb_out_grant_in_p[op] = lp;
          comb_out_grant_vc[op]   = false;
          comb_out_flit[op]       = r_vc0_flit[lp];
          if (in_out_ready[op]) comb_vc0_pop[lp] = true;
        }
      }
    } else {
      for (uint32_t off = 0; off < 5; off++) {
        uint32_t sum3   = (r_rr_ptr[op] + (off & 0x7u)) & 0x7u;
        uint32_t ip_idx = (sum3 >= 5u) ? ((sum3 - 5u) & 0x7u) : sum3;
        if (!comb_out_grant_v[op] && r_vc1_valid[ip_idx] && (r_vc1_dst_p[ip_idx] == static_cast<uint32_t>(op))) {
          comb_out_grant_v[op]    = true;
          comb_out_grant_in_p[op] = ip_idx;
          comb_out_grant_vc[op]   = true;
          comb_out_flit[op]       = r_vc1_flit[ip_idx];
        }
      }
      if (!comb_out_grant_v[op]) {
        for (uint32_t off = 0; off < 5; off++) {
          uint32_t sum3   = (r_rr_ptr[op] + (off & 0x7u)) & 0x7u;
          uint32_t ip_idx = (sum3 >= 5u) ? ((sum3 - 5u) & 0x7u) : sum3;
          if (!comb_out_grant_v[op] && r_vc0_valid[ip_idx] && (r_vc0_dst_p[ip_idx] == static_cast<uint32_t>(op))) {
            comb_out_grant_v[op]    = true;
            comb_out_grant_in_p[op] = ip_idx;
            comb_out_grant_vc[op]   = false;
            comb_out_flit[op]       = r_vc0_flit[ip_idx];
          }
        }
      }
      if (comb_out_grant_v[op]) {
        uint32_t gp = comb_out_grant_in_p[op];
        uint32_t ftype = static_cast<uint32_t>((comb_out_flit[op].hi >> 62) & 0x3ULL);
        if (comb_out_grant_vc[op] && in_allreduce_en && (ftype == 0u)) {
          uint64_t sum_payload = 0ULL;
          for (int ip = 0; ip < 5; ip++) {
            uint32_t ip_ft = static_cast<uint32_t>((r_vc1_flit[ip].hi >> 62) & 0x3ULL);
            if (r_vc1_valid[ip] && (r_vc1_dst_p[ip] == static_cast<uint32_t>(op)) && (ip_ft == 0u)) {
              comb_out_ar_any[op] = true;
              sum_payload += r_vc1_flit[ip].lo;
              if (in_out_ready[op]) comb_vc1_pop[ip] = true;
            }
          }
          comb_out_flit[op].lo = sum_payload;
        } else if (in_out_ready[op]) {
          if (comb_out_grant_vc[op]) comb_vc1_pop[gp] = true;
          else                       comb_vc0_pop[gp] = true;
        }
      }
    }
  }

  for (int p = 0; p < 5; p++) {
    bool vc_is_1 = ((in_port_flit[p].hi >> 61) & 1ULL) != 0ULL;
    if (in_port_valid[p]) {
      if (vc_is_1) comb_in_ready[p] = !r_vc1_valid[p] || comb_vc1_pop[p];
      else         comb_in_ready[p] = !r_vc0_valid[p] || comb_vc0_pop[p];
    } else {
      comb_in_ready[p] = !r_vc0_valid[p] || !r_vc1_valid[p];
    }
    comb_vc0_push[p] = in_port_valid[p] && !vc_is_1 && comb_in_ready[p];
    comb_vc1_push[p] = in_port_valid[p] &&  vc_is_1 && comb_in_ready[p];
  }

  // SerDes PCS Combinational Logic
  comb_tx_ready  = !s_replay_active;
  comb_tx_formed = in_tx_flit;
  comb_tx_formed.hi &= ~(0x1FULL << 48);
  comb_tx_formed.hi |= (static_cast<uint64_t>(s_tx_seq & 0x1Fu) << 48);
  uint16_t tx_crc = calc_crc16_ccitt(comb_tx_formed.hi, comb_tx_formed.lo);
  comb_tx_formed.hi &= ~(0xFFFFULL << 32);
  comb_tx_formed.hi |= (static_cast<uint64_t>(tx_crc) << 32);

  if (s_replay_active) {
    comb_link_valid = true;
    comb_link_flit  = s_replay_buf[s_replay_curr_seq & 0x7u];
  } else if (in_tx_valid && comb_tx_ready) {
    comb_link_valid = true;
    comb_link_flit  = comb_tx_formed;
  } else {
    comb_link_valid = false;
    comb_link_flit  = {0ULL, 0ULL};
  }

  Flit128 rx_corr = comb_link_flit;
  if (in_err_inject_crc) rx_corr.lo ^= 1ULL;
  uint16_t rx_calc_crc = calc_crc16_ccitt(rx_corr.hi, rx_corr.lo);
  uint16_t rx_emb_crc  = static_cast<uint16_t>((rx_corr.hi >> 32) & 0xFFFFULL);
  uint32_t rx_pkt_seq  = static_cast<uint32_t>((rx_corr.hi >> 48) & 0x1FULL);
  comb_rx_crc_ok = (rx_calc_crc == rx_emb_crc);
  comb_rx_seq_ok = (rx_pkt_seq == s_rx_exp_seq);

  comb_rx_valid   = false;
  comb_rx_flit    = {0ULL, 0ULL};
  comb_ack_valid  = false;
  comb_ack_seq    = s_rx_exp_seq;
  comb_nack_valid = false;
  comb_nack_seq   = s_rx_exp_seq;

  if (comb_link_valid) {
    if (comb_rx_crc_ok && comb_rx_seq_ok) {
      comb_rx_valid  = true;
      comb_rx_flit   = rx_corr;
      comb_ack_valid = true;
      comb_ack_seq   = s_rx_exp_seq;
    } else {
      comb_nack_valid = true;
      comb_nack_seq   = s_rx_exp_seq;
    }
  }
}

void dpi_noc_ref_step_seq() {
  for (int p = 0; p < 5; p++) {
    if (comb_vc0_push[p]) {
      r_vc0_valid[p] = true;
      r_vc0_flit[p]  = in_port_flit[p];
      uint32_t ft = static_cast<uint32_t>((in_port_flit[p].hi >> 62) & 0x3ULL);
      if (ft == 1u || ft == 0u) {
        uint32_t dst = static_cast<uint32_t>((in_port_flit[p].hi >> 53) & 0xFULL);
        r_vc0_dst_p[p] = route_lookup(dst);
      }
    } else if (comb_vc0_pop[p]) {
      r_vc0_valid[p] = false;
    }

    if (comb_vc1_push[p]) {
      r_vc1_valid[p] = true;
      r_vc1_flit[p]  = in_port_flit[p];
      uint32_t ft = static_cast<uint32_t>((in_port_flit[p].hi >> 62) & 0x3ULL);
      if (ft == 1u || ft == 0u) {
        uint32_t dst = static_cast<uint32_t>((in_port_flit[p].hi >> 53) & 0xFULL);
        r_vc1_dst_p[p] = route_lookup(dst);
      }
    } else if (comb_vc1_pop[p]) {
      r_vc1_valid[p] = false;
    }
  }

  for (int op = 0; op < 5; op++) {
    if (comb_out_grant_v[op] && in_out_ready[op]) {
      r_routed_cnt++;
      if (comb_out_grant_vc[op] || comb_out_ar_any[op]) r_vc1_cnt++;
      uint32_t ft = static_cast<uint32_t>((comb_out_flit[op].hi >> 62) & 0x3ULL);
      if (!r_lock_active[op]) {
        if (ft == 1u) {
          r_lock_active[op] = true;
          r_lock_in_p[op]   = comb_out_grant_in_p[op];
          r_lock_vc[op]     = comb_out_grant_vc[op];
        }
        r_rr_ptr[op] = (comb_out_grant_in_p[op] == 4u) ? 0u : (comb_out_grant_in_p[op] + 1u);
      } else {
        if (ft == 3u) {
          r_lock_active[op] = false;
          r_rr_ptr[op]      = (r_lock_in_p[op] == 4u) ? 0u : (r_lock_in_p[op] + 1u);
        }
      }
    }
  }

  if (!s_replay_active && in_tx_valid && comb_tx_ready) {
    s_replay_buf[s_tx_seq & 0x7u] = comb_tx_formed;
    s_tx_seq = (s_tx_seq + 1u) & 0x1Fu;
  }
  if (s_replay_active) {
    s_retransmit_cnt++;
    if (((s_replay_curr_seq + 1u) & 0x1Fu) == s_tx_seq) s_replay_active = false;
    else s_replay_curr_seq = (s_replay_curr_seq + 1u) & 0x1Fu;
  } else if (in_replay_trigger) {
    s_replay_active   = true;
    s_replay_curr_seq = in_replay_seq & 0x1Fu;
  }
  if (comb_link_valid) {
    if (comb_rx_crc_ok && comb_rx_seq_ok) s_rx_exp_seq = (s_rx_exp_seq + 1u) & 0x1Fu;
    else s_crc_err_cnt++;
  }
}

uint32_t dpi_noc_exp_out_valid_mask() {
  uint32_t m = 0u;
  for (int p = 0; p < 5; p++) if (comb_out_grant_v[p]) m |= (1u << p);
  return m;
}
uint32_t dpi_noc_exp_in_ready_mask() {
  uint32_t m = 0u;
  for (int p = 0; p < 5; p++) if (comb_in_ready[p]) m |= (1u << p);
  return m;
}
uint64_t dpi_noc_exp_out_flit_lo(int p) { return comb_out_flit[p].lo; }
uint64_t dpi_noc_exp_out_flit_hi(int p) { return comb_out_flit[p].hi; }
uint32_t dpi_noc_exp_routed_cnt()       { return r_routed_cnt; }
uint32_t dpi_noc_exp_vc1_cnt()          { return r_vc1_cnt; }
uint32_t dpi_noc_exp_rx_valid()         { return comb_rx_valid ? 1u : 0u; }
uint64_t dpi_noc_exp_rx_flit_lo()       { return comb_rx_flit.lo; }
uint64_t dpi_noc_exp_rx_flit_hi()       { return comb_rx_flit.hi; }
uint32_t dpi_noc_exp_ack_valid()        { return comb_ack_valid ? 1u : 0u; }
uint32_t dpi_noc_exp_ack_seq()          { return comb_ack_seq; }
uint32_t dpi_noc_exp_nack_valid()       { return comb_nack_valid ? 1u : 0u; }
uint32_t dpi_noc_exp_nack_seq()         { return comb_nack_seq; }
uint32_t dpi_noc_exp_crc_err_cnt()      { return s_crc_err_cnt; }
uint32_t dpi_noc_exp_retransmit_cnt()   { return s_retransmit_cnt; }

} // extern "C"
