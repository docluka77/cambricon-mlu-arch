// =============================================================================
// File: uvm_tb/uvm_4chip_allreduce/dpi_4chip_ref.cpp
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: C++17 DPI-C Golden Reference Model for Suite 9
//              (4-Chip OAM Node Ring/Butterfly AllReduce & Unicast Routing).
// =============================================================================
#include <cstdint>

static int      g_uvm_status   = 0;
static uint32_t g_dpi_calls    = 0;
static uint32_t g_ar_checked   = 0;
static uint32_t g_flit_checked = 0;

extern "C" {

void dpi_4chip_set_status(int status) {
  g_uvm_status = status;
}

int dpi_4chip_get_status() {
  return g_uvm_status;
}

uint32_t dpi_4chip_get_calls() {
  return g_dpi_calls;
}

uint64_t dpi_4chip_calc_allreduce_sum(
    uint64_t g0, uint64_t g1, uint64_t g2, uint64_t g3, uint32_t mode) {
  g_dpi_calls++;
  g_ar_checked++;
  if (mode == 0u) {
    // 3-Hop Ring Reduction Order: ((g0 + g3) + g2) + g1
    return ((g0 + g3) + g2) + g1;
  } else {
    // 2-Hop Butterfly Reduction Order: (g0 + g1) + (g2 + g3)
    return (g0 + g1) + (g2 + g3);
  }
}

uint32_t dpi_4chip_expected_hops(uint32_t mode) {
  g_dpi_calls++;
  return (mode == 0u) ? 3u : 2u;
}

void dpi_4chip_record_unicast_check() {
  g_dpi_calls++;
  g_flit_checked++;
}

} // extern "C"
