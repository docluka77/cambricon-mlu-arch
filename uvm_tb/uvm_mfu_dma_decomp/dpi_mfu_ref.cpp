// =============================================================================
// File: uvm_tb/uvm_mfu_dma_decomp/dpi_mfu_ref.cpp
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Bit-Exact C++17 DPI-C Reference Model for mlu_mfu_dma_engine
//              across all 6 BANG DMA opcodes and Zero-Bitmap Decompression.
// =============================================================================
#include <cstdint>

namespace {

int      g_status       = 1;
uint32_t g_dpi_calls    = 0;
uint32_t g_comp_bytes   = 0;
uint32_t g_uncomp_bytes = 0;
uint32_t g_exp_rd_addr  = 0;
uint32_t g_exp_wr_addr  = 0;
uint64_t g_exp_wr_data  = 0;
uint32_t g_exp_tr_mode  = 0;

inline uint32_t popcnt8(uint8_t bmp) {
  uint32_t cnt = 0;
  for (int i = 0; i < 8; i++) cnt += (bmp >> i) & 1u;
  return cnt;
}

inline uint64_t expand_zero_bitmap(uint64_t comp_word, uint8_t bmp) {
  uint64_t dense_word = 0ULL;
  uint32_t nz_idx     = 0u;
  for (int k = 0; k < 8; k++) {
    if ((bmp >> k) & 1u) {
      uint64_t byte_val = (comp_word >> (nz_idx * 8u)) & 0xFFULL;
      dense_word |= (byte_val << (k * 8));
      nz_idx     = (nz_idx + 1u) & 0x7u;
    }
  }
  return dense_word;
}

} // namespace

extern "C" {

void dpi_mfu_set_status(int status) { g_status = status; }
int  dpi_mfu_get_status()           { return g_status; }
uint32_t dpi_mfu_get_calls()        { return g_dpi_calls; }

void dpi_mfu_ref_reset() {
  g_comp_bytes   = 0u;
  g_uncomp_bytes = 0u;
  g_exp_rd_addr  = 0u;
  g_exp_wr_addr  = 0u;
  g_exp_wr_data  = 0ULL;
  g_exp_tr_mode  = 0u;
}

void dpi_mfu_ref_eval_beat(
  uint32_t opcode,
  uint32_t src_base,
  uint32_t dst_base,
  uint32_t src1_or_strd,
  uint32_t len_or_dims,
  uint32_t beat_idx,
  uint64_t idx_offset,
  uint32_t decomp_bitmap,
  uint64_t raw_rd_data
) {
  g_dpi_calls++;
  uint16_t b16 = static_cast<uint16_t>(beat_idx & 0xFFFFu);
  uint32_t init_rows = ((len_or_dims >> 8) & 0xFFu) == 0u ? 1u : ((len_or_dims >> 8) & 0xFFu);
  uint32_t init_cols = (len_or_dims & 0xFFu) == 0u ? 1u : (len_or_dims & 0xFFu);
  uint32_t src_stride = ((src1_or_strd >> 8) & 0xFFu) == 0u ? init_cols : ((src1_or_strd >> 8) & 0xFFu);
  uint32_t dst_stride = (src1_or_strd & 0xFFu) == 0u ? init_cols : (src1_or_strd & 0xFFu);

  uint32_t row_idx = (b16 / init_cols);
  if (row_idx >= init_rows) row_idx = init_rows - 1u;
  uint32_t col_idx = (b16 % init_cols);

  uint32_t curr_idx_off = static_cast<uint32_t>((idx_offset >> ((b16 & 3u) * 16u)) & 0xFFFFULL);

  switch (opcode) {
    case 0x30: // OP_BANG_MEMCPY_1D
    case 0x34: // OP_BANG_DECOMP_DMA
      g_exp_rd_addr = src_base + (static_cast<uint32_t>(b16) << 3);
      g_exp_wr_addr = dst_base + (static_cast<uint32_t>(b16) << 3);
      break;
    case 0x31: // OP_BANG_MEMCPY_2D
      g_exp_rd_addr = src_base + (((row_idx * src_stride) + col_idx) << 3);
      g_exp_wr_addr = dst_base + (((row_idx * dst_stride) + col_idx) << 3);
      break;
    case 0x32: // OP_BANG_GATHER
      g_exp_rd_addr = src_base + curr_idx_off;
      g_exp_wr_addr = dst_base + (static_cast<uint32_t>(b16) << 3);
      break;
    case 0x33: // OP_BANG_SCATTER
      g_exp_rd_addr = src_base + (static_cast<uint32_t>(b16) << 3);
      g_exp_wr_addr = dst_base + curr_idx_off;
      break;
    case 0x35: { // OP_BANG_TRANSPOSE
      uint32_t tr_idx = ((static_cast<uint32_t>(b16) & 0x7u) << 13) | (static_cast<uint32_t>(b16) >> 3);
      g_exp_rd_addr = src_base + (static_cast<uint32_t>(b16) << 3);
      g_exp_wr_addr = dst_base + (tr_idx << 3);
      break;
    }
    default:
      g_exp_rd_addr = src_base + (static_cast<uint32_t>(b16) << 3);
      g_exp_wr_addr = dst_base + (static_cast<uint32_t>(b16) << 3);
      break;
  }

  uint8_t bmp8 = static_cast<uint8_t>(decomp_bitmap & 0xFFu);
  if (opcode == 0x34) {
    g_exp_wr_data  = expand_zero_bitmap(raw_rd_data, bmp8);
    g_comp_bytes   += popcnt8(bmp8);
    g_uncomp_bytes += 8u;
  } else {
    g_exp_wr_data = raw_rd_data;
  }
  g_exp_tr_mode = (opcode == 0x35) ? 1u : 0u;
}

uint32_t dpi_mfu_exp_rd_addr()      { return g_exp_rd_addr; }
uint32_t dpi_mfu_exp_wr_addr()      { return g_exp_wr_addr; }
uint64_t dpi_mfu_exp_wr_data()      { return g_exp_wr_data; }
uint32_t dpi_mfu_exp_comp_bytes()   { return g_comp_bytes; }
uint32_t dpi_mfu_exp_uncomp_bytes() { return g_uncomp_bytes; }
uint32_t dpi_mfu_exp_tr_mode()      { return g_exp_tr_mode; }

} // extern "C"
