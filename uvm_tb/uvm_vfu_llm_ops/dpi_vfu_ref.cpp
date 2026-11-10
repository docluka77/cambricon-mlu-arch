// =============================================================================
// File: uvm_tb/uvm_vfu_llm_ops/dpi_vfu_ref.cpp
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Bit-Exact C++17 DPI-C Reference Model for mlu_vfu_sfu_pipe
//              covering all 7 BANG Vector & LLM SFU opcodes.
// =============================================================================
#include <cstdint>
#include <algorithm>

namespace {

int      g_status        = 1;
uint32_t g_dpi_calls     = 0;
uint32_t g_softmax_sum   = 0;
uint16_t g_softmax_max   = 0x8000;
uint16_t g_absmax        = 0;
uint16_t g_min_val       = 0;
uint16_t g_max_val       = 0;
uint16_t g_dyn_scale     = 1;
uint64_t g_exp_vec_lo    = 0;
uint64_t g_exp_vec_hi    = 0;
uint8_t  g_exp_tag       = 0;

inline int32_t sext16(uint16_t v) {
  return static_cast<int32_t>(static_cast<int16_t>(v));
}

inline uint16_t sat_s16(int32_t val) {
  if (val > 32767) return static_cast<uint16_t>(32767);
  if (val < -32768) return static_cast<uint16_t>(0x8000);
  return static_cast<uint16_t>(val & 0xFFFF);
}

inline uint16_t abs_s16(uint16_t xi) {
  if (xi == 0x8000) return 32767;
  if (xi & 0x8000) return static_cast<uint16_t>((~xi + 1u) & 0xFFFFu);
  return xi;
}

inline uint16_t pwl_exp_q88(int32_t d32) {
  int32_t y = 1;
  if (d32 >= 0) {
    y = 256;
  } else if (d32 >= -256) {
    y = 256 + ((162 * d32) >> 8);
  } else if (d32 >= -512) {
    y = 94  + ((59  * (d32 + 256)) >> 8);
  } else if (d32 >= -768) {
    y = 35  + ((22  * (d32 + 512)) >> 8);
  } else if (d32 >= -1024) {
    y = 13  + ((8   * (d32 + 768)) >> 8);
  } else if (d32 >= -1536) {
    y = 5   + ((2   * (d32 + 1024)) >> 8);
  } else {
    y = 1;
  }
  int32_t clamped = (y < 1) ? 1 : ((y > 256) ? 256 : y);
  return sat_s16(clamped);
}

inline uint16_t pwl_sigmoid_q88(uint16_t g_q88) {
  int32_t g32   = sext16(g_q88);
  int32_t abs_g = (g32 < 0) ? -g32 : g32;
  int32_t pos_sig = 256;
  if (abs_g <= 256) {
    pos_sig = 128 + ((60 * abs_g) >> 8);
  } else if (abs_g <= 512) {
    pos_sig = 188 + ((38 * (abs_g - 256)) >> 8);
  } else if (abs_g <= 1024) {
    pos_sig = 226 + ((25 * (abs_g - 512)) >> 9);
  } else {
    pos_sig = 256;
  }
  return sat_s16((g32 < 0) ? (256 - pos_sig) : pos_sig);
}

inline uint16_t rsqrt_lut_nr_q88(uint32_t var_q88) {
  uint32_t v_safe = (var_q88 == 0u) ? 1u : var_q88;
  uint32_t y0 = 32u;
  if      (v_safe < 16u)    y0 = 1448u;
  else if (v_safe < 64u)    y0 = 724u;
  else if (v_safe < 128u)   y0 = 418u;
  else if (v_safe < 192u)   y0 = 324u;
  else if (v_safe < 320u)   y0 = 256u;
  else if (v_safe < 512u)   y0 = 202u;
  else if (v_safe < 768u)   y0 = 162u;
  else if (v_safe < 1280u)  y0 = 128u;
  else if (v_safe < 2560u)  y0 = 96u;
  else if (v_safe < 5120u)  y0 = 68u;
  else if (v_safe < 10240u) y0 = 48u;
  else                      y0 = 32u;

  uint64_t v_y0_sq = (static_cast<uint64_t>(v_safe) * y0 * y0) >> 16;
  uint64_t term    = (v_y0_sq >= 760ULL) ? 8ULL : (768ULL - v_y0_sq);
  uint64_t y1      = (static_cast<uint64_t>(y0) * term) >> 9;
  if (y1 == 0ULL) return 1u;
  if (y1 > 32767ULL) return 32767u;
  return static_cast<uint16_t>(y1 & 0xFFFFu);
}

inline uint16_t calc_dyn_scale(uint16_t absmax_v, uint32_t prec_v) {
  uint32_t sc = (prec_v == 0u) ? (static_cast<uint32_t>(absmax_v) / 7u)
                               : (static_cast<uint32_t>(absmax_v) / 127u);
  if (absmax_v == 0u || sc == 0u) return 1u;
  if (sc > 65535u) return 0xFFFFu;
  return static_cast<uint16_t>(sc & 0xFFFFu);
}

} // namespace

extern "C" {

void dpi_vfu_set_status(int status) { g_status = status; }
int  dpi_vfu_get_status()           { return g_status; }
uint32_t dpi_vfu_get_calls()        { return g_dpi_calls; }

void dpi_vfu_ref_reset() {
  g_softmax_sum = 0u;
  g_softmax_max = 0x8000u;
  g_absmax      = 0u;
  g_min_val     = 0u;
  g_max_val     = 0u;
  g_dyn_scale   = 1u;
  g_exp_vec_lo  = 0ULL;
  g_exp_vec_hi  = 0ULL;
  g_exp_tag     = 0u;
}

void dpi_vfu_ref_exec(
  uint32_t opcode,
  uint32_t prec,
  uint32_t tag_id,
  uint32_t cont_mode,
  uint64_t va_lo, uint64_t va_hi,
  uint64_t vb_lo, uint64_t vb_hi,
  uint64_t lut_lo, uint64_t lut_hi
) {
  g_dpi_calls++;
  g_exp_tag = static_cast<uint8_t>(tag_id & 0xFFu);

  uint16_t va[8], vb[8], vlut[8], vexp[8], res[8];
  for (int i = 0; i < 4; i++) {
    va[i]     = static_cast<uint16_t>((va_lo  >> (i * 16)) & 0xFFFFULL);
    va[i + 4] = static_cast<uint16_t>((va_hi  >> (i * 16)) & 0xFFFFULL);
    vb[i]     = static_cast<uint16_t>((vb_lo  >> (i * 16)) & 0xFFFFULL);
    vb[i + 4] = static_cast<uint16_t>((vb_hi  >> (i * 16)) & 0xFFFFULL);
    vlut[i]   = static_cast<uint16_t>((lut_lo >> (i * 16)) & 0xFFFFULL);
    vlut[i+4] = static_cast<uint16_t>((lut_hi >> (i * 16)) & 0xFFFFULL);
  }

  int16_t  comb_max    = static_cast<int16_t>(va[0]);
  int16_t  comb_min    = static_cast<int16_t>(va[0]);
  uint16_t comb_absmax = 0u;
  uint32_t comb_sq_sum = 0u;

  for (int i = 0; i < 8; i++) {
    int16_t sv = static_cast<int16_t>(va[i]);
    if (sv > comb_max) comb_max = sv;
    if (sv < comb_min) comb_min = sv;
    uint16_t av = abs_s16(va[i]);
    if (av > comb_absmax) comb_absmax = av;
    comb_sq_sum += (static_cast<uint32_t>(av) * static_cast<uint32_t>(av)) >> 8;
  }

  uint16_t comb_dyn_scale = calc_dyn_scale(comb_absmax, prec);
  int16_t  old_max_s      = static_cast<int16_t>(g_softmax_max);
  int16_t  comb_m_new     = ((cont_mode & 1u) && (old_max_s > comb_max)) ? old_max_s : comb_max;
  uint16_t comb_old_exp   = pwl_exp_q88(sext16(g_softmax_max) - sext16(static_cast<uint16_t>(comb_m_new)));
  uint32_t comb_l_scaled  = (cont_mode & 1u) ? ((g_softmax_sum * static_cast<uint32_t>(comb_old_exp)) >> 8) : 0u;
  uint32_t comb_l_new     = comb_l_scaled;

  for (int i = 0; i < 8; i++) {
    vexp[i]     = pwl_exp_q88(sext16(va[i]) - sext16(static_cast<uint16_t>(comb_m_new)));
    comb_l_new += static_cast<uint32_t>(vexp[i]);
  }
  if (comb_l_new == 0u) comb_l_new = 1u;

  uint32_t comb_mean_sq = (comb_sq_sum >> 3) + 1u;
  uint16_t comb_rsqrt   = rsqrt_lut_nr_q88(comb_mean_sq);

  uint32_t denom_safe = (comb_l_new == 0u) ? 1u : comb_l_new;
  int32_t  sc_safe    = (comb_dyn_scale == 0u) ? 1 : static_cast<int32_t>(comb_dyn_scale);

  for (int i = 0; i < 8; i++) res[i] = va[i];

  switch (opcode) {
    case 0x20: // OP_BANG_VADD
      for (int i = 0; i < 8; i++) res[i] = sat_s16(sext16(va[i]) + sext16(vb[i]));
      break;
    case 0x21: // OP_BANG_VMUL
      for (int i = 0; i < 8; i++) res[i] = sat_s16((sext16(va[i]) * sext16(vb[i])) >> 8);
      break;
    case 0x22: // OP_BANG_SOFTMAX
      for (int i = 0; i < 8; i++) {
        uint32_t p_val = (static_cast<uint32_t>(vexp[i]) << 8) / denom_safe;
        res[i] = (p_val > 256u) ? 256u : static_cast<uint16_t>(p_val & 0xFFFFu);
      }
      g_softmax_max = static_cast<uint16_t>(comb_m_new);
      g_softmax_sum = comb_l_new;
      break;
    case 0x23: // OP_BANG_ROPE
      for (int k = 0; k < 4; k++) {
        res[2*k]   = sat_s16((sext16(va[2*k])*sext16(vlut[2*k])   - sext16(va[2*k+1])*sext16(vlut[2*k+1])) >> 8);
        res[2*k+1] = sat_s16((sext16(va[2*k])*sext16(vlut[2*k+1]) + sext16(va[2*k+1])*sext16(vlut[2*k]))   >> 8);
      }
      break;
    case 0x24: // OP_BANG_RMSNORM
      for (int i = 0; i < 8; i++) {
        int32_t nx = (sext16(va[i]) * sext16(comb_rsqrt)) >> 8;
        res[i]     = sat_s16((nx * sext16(vb[i])) >> 8);
      }
      break;
    case 0x25: // OP_BANG_SWIGLU
      for (int i = 0; i < 8; i++) {
        int32_t silu_v = (sext16(va[i]) * sext16(pwl_sigmoid_q88(va[i]))) >> 8;
        res[i]         = sat_s16((silu_v * sext16(vb[i])) >> 8);
      }
      break;
    case 0x26: // OP_BANG_QUANT_STAT
      for (int i = 0; i < 8; i++) {
        int32_t qv = sext16(va[i]) / sc_safe;
        if (prec == 0u) {
          int32_t c = (qv > 7) ? 7 : ((qv < -8) ? -8 : qv);
          res[i] = static_cast<uint16_t>(c & 0xFFFF);
        } else {
          int32_t c = (qv > 127) ? 127 : ((qv < -128) ? -128 : qv);
          res[i] = static_cast<uint16_t>(c & 0xFFFF);
        }
      }
      g_absmax    = comb_absmax;
      g_min_val   = static_cast<uint16_t>(comb_min);
      g_max_val   = static_cast<uint16_t>(comb_max);
      g_dyn_scale = comb_dyn_scale;
      break;
    default:
      break;
  }

  g_exp_vec_lo = 0ULL;
  g_exp_vec_hi = 0ULL;
  for (int i = 0; i < 4; i++) {
    g_exp_vec_lo |= (static_cast<uint64_t>(res[i])     << (i * 16));
    g_exp_vec_hi |= (static_cast<uint64_t>(res[i + 4]) << (i * 16));
  }
}

uint64_t dpi_vfu_exp_vec_lo()      { return g_exp_vec_lo; }
uint64_t dpi_vfu_exp_vec_hi()      { return g_exp_vec_hi; }
uint32_t dpi_vfu_exp_softmax_sum() { return g_softmax_sum; }
uint32_t dpi_vfu_exp_softmax_max() { return g_softmax_max; }
uint32_t dpi_vfu_exp_absmax()      { return g_absmax; }
uint32_t dpi_vfu_exp_min_val()     { return g_min_val; }
uint32_t dpi_vfu_exp_max_val()     { return g_max_val; }
uint32_t dpi_vfu_exp_dyn_scale()   { return g_dyn_scale; }
uint32_t dpi_vfu_exp_tag()         { return g_exp_tag; }

} // extern "C"
