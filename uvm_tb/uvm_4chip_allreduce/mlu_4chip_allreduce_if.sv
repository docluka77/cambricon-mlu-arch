// =============================================================================
// File: uvm_tb/uvm_4chip_allreduce/mlu_4chip_allreduce_if.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: SystemVerilog Interface for Accellera UVM Suite 9:
//              mlu_4chip_oam_node (4-Chip MLU-Link Ring & Butterfly AllReduce).
// =============================================================================
`ifndef MLU_4CHIP_ALLREDUCE_IF_SV
`define MLU_4CHIP_ALLREDUCE_IF_SV

interface mlu_4chip_allreduce_if (input logic clk);
  logic                rst_n;

  // Collective Ring / Butterfly AllReduce Controls & Outputs
  logic                allreduce_start;
  logic                allreduce_mode;
  logic [3:0][63:0]    local_grad;
  logic [3:0]          allreduce_done;
  logic [3:0][63:0]    final_allreduce_sum;
  logic                allreduce_busy;
  logic [2:0]          allreduce_hops_taken;

  // Per-Chip Local MLU-Link Flit Injection & Ejection
  logic [3:0]          chip_tx_valid;
  logic [3:0]          chip_tx_ready;
  logic [3:0][127:0]   chip_tx_flit;

  logic [3:0]          chip_rx_valid;
  logic [3:0]          chip_rx_ready;
  logic [3:0][127:0]   chip_rx_flit;

  // Inter-Chip C2C SerDes Link Fault Injection & Handshake
  logic [3:0]          link_err_inject;
  logic [3:0]          link_ack_valid;
  logic [3:0]          link_nack_valid;

  // Node-Wide Telemetry Counters
  logic [31:0]         total_routed_flits;
  logic [31:0]         total_crc_errs;
  logic [31:0]         total_retransmits;
  logic [31:0]         collective_completed_cnt;
endinterface : mlu_4chip_allreduce_if

`endif // MLU_4CHIP_ALLREDUCE_IF_SV
