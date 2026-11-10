// =============================================================================
// File: uvm_tb/uvm_sram_nram_wram/dpi_sram_ref.cpp
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: C++17 Bit-Exact DPI-C Reference Model for (72,64) Hsiao SECDED
//              ECC Codec and On-Chip Memory Hierarchy Scoreboard Qualification.
// =============================================================================
#include <cstdint>

static int g_sim_status = 0;
static uint32_t g_dpi_calls = 0;

static const uint8_t HSIAO_H[64] = {
  // Indices 0..55: 56 weight-3 columns (matching RTL indices 0..55)
  0x07, 0x0B, 0x13, 0x23, 0x43, 0x83, 0x0D, 0x15,
  0x25, 0x45, 0x85, 0x19, 0x29, 0x49, 0x89, 0x31,
  0x51, 0x91, 0x61, 0xA1, 0xC1, 0x0E, 0x16, 0x26,
  0x46, 0x86, 0x1A, 0x2A, 0x4A, 0x8A, 0x32, 0x52,
  0x92, 0x62, 0xA2, 0xC2, 0x1C, 0x2C, 0x4C, 0x8C,
  0x34, 0x54, 0x94, 0x64, 0xA4, 0xC4, 0x38, 0x58,
  0x98, 0x68, 0xA8, 0xC8, 0x70, 0xB0, 0xD0, 0xE0,
  // Indices 56..63: 8 weight-5 columns (matching RTL indices 56..63)
  0xF8, 0xF1, 0xE3, 0xC7, 0x8F, 0x1F, 0x3E, 0x7C
};

static uint8_t calc_hsiao_parity(uint64_t d) {
  uint8_t p = 0;
  for (int b = 0; b < 64; b++) {
    if ((d >> b) & 1ULL) {
      p ^= HSIAO_H[b];
    }
  }
  return p;
}

extern "C" void dpi_sram_set_status(int status) {
  g_sim_status = status;
}

extern "C" int dpi_sram_get_status() {
  return g_sim_status;
}

extern "C" uint32_t dpi_sram_get_calls() {
  return g_dpi_calls;
}

extern "C" uint32_t dpi_ecc_ref_syndrome(uint64_t err_lo64, uint32_t err_hi8) {
  g_dpi_calls++;
  uint8_t syn = (uint8_t)(err_hi8 & 0xFFU) ^ calc_hsiao_parity(err_lo64);
  return (uint32_t)syn;
}

extern "C" uint32_t dpi_ecc_ref_sec(uint64_t err_lo64, uint32_t err_hi8) {
  uint8_t syn = (uint8_t)(err_hi8 & 0xFFU) ^ calc_hsiao_parity(err_lo64);
  if (syn == 0) return 0U;
  uint32_t pop = __builtin_popcount((unsigned int)syn);
  return (pop & 1U) ? 1U : 0U;
}

extern "C" uint32_t dpi_ecc_ref_ded(uint64_t err_lo64, uint32_t err_hi8) {
  uint8_t syn = (uint8_t)(err_hi8 & 0xFFU) ^ calc_hsiao_parity(err_lo64);
  if (syn == 0) return 0U;
  uint32_t pop = __builtin_popcount((unsigned int)syn);
  return ((pop & 1U) == 0U) ? 1U : 0U;
}

extern "C" uint64_t dpi_ecc_ref_dout(uint64_t din, uint64_t err_lo64, uint32_t err_hi8) {
  uint64_t rx_data = din ^ err_lo64;
  uint8_t syn = (uint8_t)(err_hi8 & 0xFFU) ^ calc_hsiao_parity(err_lo64);
  uint32_t pop = __builtin_popcount((unsigned int)syn);
  if (syn != 0 && (pop & 1U)) {
    for (int b = 0; b < 64; b++) {
      if (syn == HSIAO_H[b]) {
        rx_data ^= (1ULL << b);
      }
    }
  }
  return rx_data;
}
