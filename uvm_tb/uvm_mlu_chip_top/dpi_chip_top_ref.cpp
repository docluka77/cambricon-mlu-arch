// =============================================================================
// File: uvm_tb/uvm_mlu_chip_top/dpi_chip_top_ref.cpp
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: C++17 Bit-Exact DPI-C Reference Model for Suite 8 (mlu_chip_top)
//              In-SRAM Atomic AllReduce & C2C SerDes CRC-16-CCITT Verification.
// =============================================================================
#include <cstdint>

static int      g_chip_top_status    = 0;
static uint32_t g_chip_top_dpi_calls = 0;

extern "C" void dpi_chip_top_set_status(int status) {
  g_chip_top_status = status;
}

extern "C" int dpi_chip_top_get_status() {
  return g_chip_top_status;
}

extern "C" uint32_t dpi_chip_top_get_calls() {
  return g_chip_top_dpi_calls;
}

extern "C" uint64_t dpi_chip_top_ref_allreduce(uint64_t dst_init, uint64_t src_val) {
  g_chip_top_dpi_calls++;
  uint64_t out = 0;
  for (int lane = 0; lane < 4; lane++) {
    uint16_t a   = static_cast<uint16_t>((dst_init >> (lane * 16)) & 0xFFFFULL);
    uint16_t b   = static_cast<uint16_t>((src_val >> (lane * 16)) & 0xFFFFULL);
    uint16_t sum = static_cast<uint16_t>(a + b);
    out |= (static_cast<uint64_t>(sum) << (lane * 16));
  }
  return out;
}

extern "C" uint32_t dpi_chip_top_ref_crc16(uint64_t flit_hi, uint64_t flit_lo) {
  g_chip_top_dpi_calls++;
  uint16_t crc   = 0xFFFFu;
  uint16_t top16 = static_cast<uint16_t>((flit_hi >> 48) & 0xFFFFULL);
  uint32_t mid32 = static_cast<uint32_t>(flit_hi & 0xFFFFFFFFULL);
  for (int i = 111; i >= 0; i--) {
    uint32_t bit_i = 0u;
    if (i >= 96)      bit_i = (top16 >> (i - 96)) & 1u;
    else if (i >= 64) bit_i = (mid32 >> (i - 64)) & 1u;
    else              bit_i = static_cast<uint32_t>((flit_lo >> i) & 1ULL);
    uint32_t fb = bit_i ^ ((crc >> 15) & 1u);
    crc = static_cast<uint16_t>(((crc << 1) & 0xFFFFu) ^ (fb ? 0x1021u : 0x0000u));
  }
  return static_cast<uint32_t>(crc);
}
