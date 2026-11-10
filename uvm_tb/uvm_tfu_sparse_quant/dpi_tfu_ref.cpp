// =============================================================================
// File: uvm_tb/uvm_tfu_sparse_quant/dpi_tfu_ref.cpp
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: C++17 Bit-Exact Cycle-Accurate DPI-C Reference Model for
//              mlu_tfu_fractal_mac across all 8 precisions, Cambricon-S 2:4 &
//              4x4 Block Sparsity, and Cambricon-Q Statistical Quantization.
// =============================================================================
#include <cstdint>
#include <cstring>

static int      g_tfu_status = 0;
static uint32_t g_tfu_dpi_calls = 0;

struct TfuState {
  uint8_t  state_q; // 0=IDLE, 1=STREAM, 2=WB
  uint8_t  op_q;
  uint8_t  prec_q;
  uint8_t  sparse_q;
  uint8_t  tag_q;
  uint16_t beats_rem_q;
  uint8_t  beat_idx_q;
  int32_t  acc_tile_q[8];
  uint32_t zero_skip_cnt_q;
  uint32_t total_mac_ops_q;

  // Combinational outputs before posedge
  uint8_t  exp_cmd_ready;
  uint8_t  exp_stream_ready;
  uint8_t  exp_tfu_busy;
  uint8_t  exp_result_valid;
  uint8_t  exp_done_valid;
  uint8_t  exp_done_tag;
  uint64_t exp_res_w[4];
  uint32_t exp_zero_skip_cnt;
  uint32_t exp_total_mac_ops;
} g_tfu;

static int32_t decode_fp8_e4m3(uint8_t val) {
  bool s = (val >> 7) & 1U;
  uint8_t e = (val >> 3) & 0x0FU;
  uint8_t m = val & 0x07U;
  uint32_t mag = (e == 0) ? (uint32_t)m : (((uint32_t)(8U | m)) << (e - 1));
  return s ? -(int32_t)mag : (int32_t)mag;
}

static int32_t decode_fp8_e5m2(uint8_t val) {
  bool s = (val >> 7) & 1U;
  uint8_t e = (val >> 2) & 0x1FU;
  uint8_t m = val & 0x03U;
  uint8_t sh = (e > 24) ? 17 : ((e > 7) ? (e - 7) : 0);
  uint32_t mag = (e == 0) ? (uint32_t)m : (((uint32_t)(4U | m)) << sh);
  return s ? -(int32_t)mag : (int32_t)mag;
}

static int32_t decode_fp16_bf16(uint16_t val, bool is_bf16) {
  bool s = (val >> 15) & 1U;
  uint8_t e;
  uint8_t m;
  uint32_t mag;
  if (is_bf16) {
    e = (val >> 7) & 0xFFU;
    m = val & 0x7FU;
    if (e < 120) mag = 0;
    else if (e >= 138) mag = 0x3FFFFFFFU;
    else mag = ((uint32_t)(0x80U | m)) << (e - 120);
  } else {
    e = (val >> 10) & 0x1FU;
    m = ((val >> 3) & 0x7FU) | (((val & 0x07U) != 0) ? 1U : 0U);
    if (e < 8) mag = 0;
    else if (e >= 26) mag = 0x3FFFFFFFU;
    else mag = ((uint32_t)(0x80U | m)) << (e - 8);
  }
  return s ? -(int32_t)mag : (int32_t)mag;
}

static uint8_t cambricon_q_quantize(int32_t acc_in, uint16_t scale_q8_8, uint8_t zp_in) {
  int64_t mult_full = (int64_t)acc_in * (int64_t)scale_q8_8;
  bool bit7 = ((mult_full >> 7) & 1LL) != 0;
  bool low6 = (mult_full & 0x7FLL) != 0;
  bool bit8 = ((mult_full >> 8) & 1LL) != 0;
  int64_t rounded = (mult_full >> 8) + ((bit7 && (low6 || bit8)) ? 1LL : 0LL);
  int64_t zp_sext = (int64_t)((int8_t)zp_in);
  int64_t shifted = rounded + zp_sext;
  if (shifted > 127LL) return (uint8_t)127;
  if (shifted < -128LL) return (uint8_t)((int8_t)-128);
  return (uint8_t)(shifted & 0xFFLL);
}
extern "C" void dpi_tfu_set_status(int status) { g_tfu_status = status; }
extern "C" int  dpi_tfu_get_status() { return g_tfu_status; }
extern "C" uint32_t dpi_tfu_get_calls() { return g_tfu_dpi_calls; }

extern "C" void dpi_tfu_reset() {
  std::memset(&g_tfu, 0, sizeof(g_tfu));
  g_tfu.prec_q = 1; // PREC_INT8
}

extern "C" void dpi_tfu_eval_and_step(
  uint32_t cmd_valid,
  uint64_t cmd_inst_hi,
  uint64_t cmd_inst_lo,
  uint32_t stream_valid,
  uint64_t act_w0, uint64_t act_w1, uint64_t act_w2, uint64_t act_w3,
  uint64_t wt_w0,  uint64_t wt_w1,  uint64_t wt_w2,  uint64_t wt_w3,
  uint32_t sparse_meta,
  uint32_t quant_scale,
  uint32_t quant_zp
) {
  g_tfu_dpi_calls++;

  // 1. Evaluate combinational outputs before posedge
  g_tfu.exp_cmd_ready       = (g_tfu.state_q == 0) ? 1U : 0U;
  g_tfu.exp_stream_ready    = (g_tfu.state_q == 1) ? 1U : 0U;
  g_tfu.exp_tfu_busy        = (g_tfu.state_q != 0) ? 1U : 0U;
  g_tfu.exp_result_valid    = (g_tfu.state_q == 2) ? 1U : 0U;
  g_tfu.exp_done_valid      = (g_tfu.state_q == 2) ? 1U : 0U;
  g_tfu.exp_done_tag        = g_tfu.tag_q;
  g_tfu.exp_zero_skip_cnt   = g_tfu.zero_skip_cnt_q;
  g_tfu.exp_total_mac_ops   = g_tfu.total_mac_ops_q;

  uint8_t res_bytes[32];
  std::memset(res_bytes, 0, sizeof(res_bytes));
  if (g_tfu.op_q == 0x13U) { // OP_BANG_QUANT_MM
    for (int c = 0; c < 8; c++) {
      res_bytes[c] = cambricon_q_quantize(g_tfu.acc_tile_q[c], (uint16_t)quant_scale, (uint8_t)quant_zp);
    }
    for (int c = 0; c < 6; c++) {
      uint32_t u = (uint32_t)g_tfu.acc_tile_q[c];
      std::memcpy(&res_bytes[8 + c * 4], &u, 4);
    }
  } else {
    for (int c = 0; c < 8; c++) {
      uint32_t u = (uint32_t)g_tfu.acc_tile_q[c];
      std::memcpy(&res_bytes[c * 4], &u, 4);
    }
  }
  for (int w = 0; w < 4; w++) {
    std::memcpy(&g_tfu.exp_res_w[w], &res_bytes[w * 8], 8);
  }

  // Unpack 256-bit act and wt into 32-byte arrays
  uint8_t act_b[32], wt_b[32], eff_act[32];
  uint64_t act_words[4] = {act_w0, act_w1, act_w2, act_w3};
  uint64_t wt_words[4]  = {wt_w0,  wt_w1,  wt_w2,  wt_w3};
  for (int w = 0; w < 4; w++) {
    std::memcpy(&act_b[w * 8], &act_words[w], 8);
    std::memcpy(&wt_b[w * 8],  &wt_words[w],  8);
  }
  std::memcpy(eff_act, act_b, 32);

  if (g_tfu.sparse_q == 1U || g_tfu.sparse_q == 3U) {
    for (int g = 0; g < 8; g++) {
      uint8_t idx0 = (sparse_meta >> (g * 4)) & 0x03U;
      uint8_t idx1 = (sparse_meta >> (g * 4 + 2)) & 0x03U;
      eff_act[g * 2 + 0]      = act_b[g * 4 + idx0];
      eff_act[g * 2 + 1]      = act_b[g * 4 + idx1];
      eff_act[16 + g * 2 + 0] = act_b[g * 4 + idx0];
      eff_act[16 + g * 2 + 1] = act_b[g * 4 + idx1];
    }
  }

  bool wt_all_zero = (wt_w0 == 0ULL && wt_w1 == 0ULL && wt_w2 == 0ULL && wt_w3 == 0ULL);
  bool block_is_zero = (g_tfu.sparse_q == 2U) &&
                       ((((sparse_meta >> (g_tfu.beat_idx_q & 0x0FU)) & 1U) == 0U) || wt_all_zero);

  int32_t dot_prod = 0;
  uint32_t mac_ops = 32;
  if (!block_is_zero) {
    switch (g_tfu.prec_q) {
      case 0: { // PREC_INT4
        mac_ops = 64;
        for (int i = 0; i < 64; i++) {
          uint8_t a_nib = (eff_act[i / 2] >> ((i & 1) * 4)) & 0x0FU;
          uint8_t b_nib = (wt_b[i / 2]    >> ((i & 1) * 4)) & 0x0FU;
          int32_t a_s = (a_nib & 8U) ? ((int32_t)a_nib - 16) : (int32_t)a_nib;
          int32_t b_s = (b_nib & 8U) ? ((int32_t)b_nib - 16) : (int32_t)b_nib;
          dot_prod += a_s * b_s;
        }
        break;
      }
      case 1: { // PREC_INT8
        mac_ops = 32;
        for (int i = 0; i < 32; i++) {
          dot_prod += (int32_t)((int8_t)eff_act[i]) * (int32_t)((int8_t)wt_b[i]);
        }
        break;
      }
      case 2: { // PREC_FP8_E4M3
        mac_ops = 32;
        for (int i = 0; i < 32; i++) {
          int32_t a32 = decode_fp8_e4m3(eff_act[i]);
          int32_t b32 = decode_fp8_e4m3(wt_b[i]);
          int32_t p32 = (int32_t)((uint32_t)a32 * (uint32_t)b32);
          dot_prod += (p32 >> 12);
        }
        break;
      }
      case 3: { // PREC_FP8_E5M2
        mac_ops = 32;
        for (int i = 0; i < 32; i++) {
          int32_t a32 = decode_fp8_e5m2(eff_act[i]);
          int32_t b32 = decode_fp8_e5m2(wt_b[i]);
          int32_t p32 = (int32_t)((uint32_t)a32 * (uint32_t)b32);
          dot_prod += (p32 >> 14);
        }
        break;
      }
      case 4:
      case 5: { // PREC_FP16 / PREC_BF16
        mac_ops = 16;
        bool is_bf16 = (g_tfu.prec_q == 5);
        for (int i = 0; i < 16; i++) {
          uint16_t a16 = (uint16_t)eff_act[i * 2] | ((uint16_t)eff_act[i * 2 + 1] << 8);
          uint16_t b16 = (uint16_t)wt_b[i * 2]    | ((uint16_t)wt_b[i * 2 + 1]    << 8);
          int32_t a32 = decode_fp16_bf16(a16, is_bf16);
          int32_t b32 = decode_fp16_bf16(b16, is_bf16);
          int32_t p32 = (int32_t)((uint32_t)a32 * (uint32_t)b32);
          dot_prod += (p32 >> 22);
        }
        break;
      }
      default: { // PREC_TF32 / PREC_FP32
        mac_ops = 8;
        for (int i = 0; i < 8; i++) {
          uint16_t a_hi = (uint16_t)eff_act[i * 4 + 2] | ((uint16_t)eff_act[i * 4 + 3] << 8);
          uint16_t b_hi = (uint16_t)wt_b[i * 4 + 2]    | ((uint16_t)wt_b[i * 4 + 3]    << 8);
          int32_t a32 = decode_fp16_bf16(a_hi, true);
          int32_t b32 = decode_fp16_bf16(b_hi, true);
          int32_t p32 = (int32_t)((uint32_t)a32 * (uint32_t)b32);
          dot_prod += (p32 >> 22);
        }
        break;
      }
    }
  }
  // 2. Sequential state transition (posedge clk)
  if (g_tfu.state_q == 0) {
    if (cmd_valid) {
      g_tfu.op_q        = (cmd_inst_hi >> 58) & 0x3FU;
      g_tfu.prec_q      = (cmd_inst_hi >> 52) & 0x07U;
      g_tfu.sparse_q    = (cmd_inst_hi >> 50) & 0x03U;
      g_tfu.tag_q       = (cmd_inst_hi >> 32) & 0xFFU;
      uint16_t len_d    = (uint16_t)(cmd_inst_lo & 0xFFFFULL);
      g_tfu.beats_rem_q = (len_d == 0) ? 1 : len_d;
      g_tfu.beat_idx_q  = 0;
      for (int c = 0; c < 8; c++) g_tfu.acc_tile_q[c] = 0;
      g_tfu.state_q     = 1;
    }
  } else if (g_tfu.state_q == 1) {
    if (stream_valid) {
      if (block_is_zero) {
        g_tfu.zero_skip_cnt_q++;
      } else {
        g_tfu.acc_tile_q[0] += dot_prod;
        uint8_t b_low3 = g_tfu.beat_idx_q & 0x07U;
        if (b_low3 != 0) {
          g_tfu.acc_tile_q[b_low3] += dot_prod;
        }
        g_tfu.total_mac_ops_q += mac_ops;
      }
      g_tfu.beat_idx_q = (g_tfu.beat_idx_q + 1) & 0x0FU;
      if (g_tfu.beats_rem_q <= 1) {
        g_tfu.state_q = 2;
      } else {
        g_tfu.beats_rem_q--;
      }
    }
  } else if (g_tfu.state_q == 2) {
    g_tfu.state_q = 0;
  } else {
    g_tfu.state_q = 0;
  }
}

extern "C" uint32_t dpi_tfu_exp_cmd_ready()     { return g_tfu.exp_cmd_ready; }
extern "C" uint32_t dpi_tfu_exp_stream_ready()  { return g_tfu.exp_stream_ready; }
extern "C" uint32_t dpi_tfu_exp_tfu_busy()      { return g_tfu.exp_tfu_busy; }
extern "C" uint32_t dpi_tfu_exp_result_valid()  { return g_tfu.exp_result_valid; }
extern "C" uint32_t dpi_tfu_exp_done_valid()    { return g_tfu.exp_done_valid; }
extern "C" uint32_t dpi_tfu_exp_done_tag()      { return g_tfu.exp_done_tag; }
extern "C" uint64_t dpi_tfu_exp_res_word(int w) { return g_tfu.exp_res_w[w & 3]; }
extern "C" uint32_t dpi_tfu_exp_zero_skip_cnt() { return g_tfu.exp_zero_skip_cnt; }
extern "C" uint32_t dpi_tfu_exp_total_mac_ops() { return g_tfu.exp_total_mac_ops; }
