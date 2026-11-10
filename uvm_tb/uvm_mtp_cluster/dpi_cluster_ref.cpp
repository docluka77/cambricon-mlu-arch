// =============================================================================
// File: uvm_tb/uvm_mtp_cluster/dpi_cluster_ref.cpp
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: C++17 Bit-Exact DPI-C Reference Model for Suite 7 (mlu_mtp_cluster)
//              In-SRAM Atomic AllReduce & Cluster Telemetry Qualification.
// =============================================================================
#include <cstdint>

static int g_cluster_status = 0;
static uint32_t g_cluster_dpi_calls = 0;

extern "C" void dpi_cluster_set_status(int status) {
  g_cluster_status = status;
}

extern "C" int dpi_cluster_get_status() {
  return g_cluster_status;
}

extern "C" uint32_t dpi_cluster_get_calls() {
  return g_cluster_dpi_calls;
}

extern "C" uint64_t dpi_cluster_ref_allreduce(uint64_t dst_init, uint64_t src_val) {
  g_cluster_dpi_calls++;
  uint64_t out = 0;
  for (int lane = 0; lane < 4; lane++) {
    uint16_t a = static_cast<uint16_t>((dst_init >> (lane * 16)) & 0xFFFFULL);
    uint16_t b = static_cast<uint16_t>((src_val >> (lane * 16)) & 0xFFFFULL);
    uint16_t sum = static_cast<uint16_t>(a + b);
    out |= (static_cast<uint64_t>(sum) << (lane * 16));
  }
  return out;
}
