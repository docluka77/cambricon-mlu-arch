// =============================================================================
// File: uvm_tb/uvm_cambricon_llm_kv/dpi_cambricon_llm_ref.cpp
// Description: Bit-Exact C++17 DPI-C Reference Model for Cambricon-LLM
//              Flash-Assisted KV-Cache Quant-Pack & Speculative Tree Engine.
// =============================================================================
#include <cstdint>
#include <cstdio>
#include <algorithm>
#include "svdpi.h"

static int g_Checked = 0;
static int g_Errors  = 0;

extern "C" void dpi_cambricon_llm_kv_pack_ref(
    int prec_int4,
    uint64_t kv_lo,
    uint64_t kv_hi,
    uint64_t* exp_packed_out,
    uint64_t* exp_dequant_lo,
    uint64_t* exp_dequant_hi) {
  int16_t x[8];
  for (int k = 0; k < 4; ++k) {
    x[k]     = static_cast<int16_t>((kv_lo >> (k * 16)) & 0xFFFFULL);
    x[k + 4] = static_cast<int16_t>((kv_hi >> (k * 16)) & 0xFFFFULL);
  }

  int16_t min_val = x[0], max_val = x[0];
  for (int k = 1; k < 8; ++k) {
    if (x[k] < min_val) min_val = x[k];
    if (x[k] > max_val) max_val = x[k];
  }

  uint32_t span_u = static_cast<uint32_t>(
      static_cast<int32_t>(max_val) - static_cast<int32_t>(min_val)) & 0x1FFFFu;
  uint32_t shift_amt = 0;
  if      ((span_u >> 15) & 0x3u) shift_amt = 13;
  else if ((span_u >> 14) & 0x1u) shift_amt = 11;
  else if ((span_u >> 13) & 0x1u) shift_amt = 10;
  else if ((span_u >> 12) & 0x1u) shift_amt = 9;
  else if ((span_u >> 11) & 0x1u) shift_amt = 8;
  else if ((span_u >> 10) & 0x1u) shift_amt = 7;
  else if ((span_u >> 9)  & 0x1u) shift_amt = 6;
  else if ((span_u >> 8)  & 0x1u) shift_amt = 5;
  else if ((span_u >> 7)  & 0x1u) shift_amt = 4;
  else if ((span_u >> 6)  & 0x1u) shift_amt = 3;
  else if ((span_u >> 5)  & 0x1u) shift_amt = 2;
  else if ((span_u >> 4)  & 0x1u) shift_amt = 1;
  else                            shift_amt = 0;

  uint64_t packed = 0ULL;
  uint64_t deq_lo = 0ULL, deq_hi = 0ULL;

  if (prec_int4) {
    packed |= (static_cast<uint64_t>(shift_amt & 0xFu) << 48);
    packed |= (static_cast<uint64_t>(static_cast<uint16_t>(min_val)) << 32);
    for (int k = 0; k < 8; ++k) {
      uint32_t diff_u = static_cast<uint32_t>(
          static_cast<int32_t>(x[k]) - static_cast<int32_t>(min_val)) & 0x1FFFFu;
      uint32_t scaled_u = diff_u >> shift_amt;
      uint32_t q4 = (scaled_u > 15u) ? 15u : (scaled_u & 0xFu);
      packed |= (static_cast<uint64_t>(q4) << (k * 4));
      uint16_t deq_k = static_cast<uint16_t>(
          (static_cast<uint32_t>(static_cast<int32_t>(min_val)) + (q4 << shift_amt)) & 0xFFFFu);
      if (k < 4) deq_lo |= (static_cast<uint64_t>(deq_k) << (k * 16));
      else       deq_hi |= (static_cast<uint64_t>(deq_k) << ((k - 4) * 16));
    }
  } else {
    for (int k = 0; k < 8; ++k) {
      uint8_t fp8_b = static_cast<uint8_t>((static_cast<uint16_t>(x[k]) >> 8) & 0xFFu);
      packed |= (static_cast<uint64_t>(fp8_b) << (k * 8));
      uint16_t deq_k = static_cast<uint16_t>(fp8_b) << 8;
      if (k < 4) deq_lo |= (static_cast<uint64_t>(deq_k) << (k * 16));
      else       deq_hi |= (static_cast<uint64_t>(deq_k) << ((k - 4) * 16));
    }
  }

  *exp_packed_out = packed;
  *exp_dequant_lo = deq_lo;
  *exp_dequant_hi = deq_hi;
}

extern "C" void dpi_cambricon_llm_spec_verify_ref(
    uint64_t draft_lo,
    uint64_t draft_hi,
    uint64_t target_lo,
    uint64_t target_hi,
    int tree_mask,
    int accept_thresh,
    int* exp_bitmap,
    int* exp_len,
    int* exp_bonus_idx) {
  int16_t thresh_s = static_cast<int16_t>(accept_thresh & 0xFFFF);
  int prefix_ok = 1;
  int bitmap = 0;
  int len = 0;
  for (int k = 0; k < 8; ++k) {
    int16_t d_k = (k < 4) ? static_cast<int16_t>((draft_lo >> (k * 16)) & 0xFFFFULL)
                          : static_cast<int16_t>((draft_hi >> ((k - 4) * 16)) & 0xFFFFULL);
    int16_t t_k = (k < 4) ? static_cast<int16_t>((target_lo >> (k * 16)) & 0xFFFFULL)
                          : static_cast<int16_t>((target_hi >> ((k - 4) * 16)) & 0xFFFFULL);
    bool mask_k = ((tree_mask >> k) & 1) != 0;
    bool tok_ok = mask_k && ((static_cast<int32_t>(t_k) + static_cast<int32_t>(thresh_s)) >= static_cast<int32_t>(d_k));
    if (prefix_ok && tok_ok) {
      bitmap |= (1 << k);
      len++;
    } else {
      prefix_ok = 0;
    }
  }
  *exp_bitmap    = bitmap;
  *exp_len       = len;
  *exp_bonus_idx = (len == 8) ? 7 : (len & 0x7);
}

extern "C" void dpi_cambricon_llm_record_result(int pass) {
  g_Checked++;
  if (!pass) g_Errors++;
}

extern "C" int dpi_cambricon_llm_get_status() {
  return (g_Checked >= 250 && g_Errors == 0) ? 0 : 1;
}
