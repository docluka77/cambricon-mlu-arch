//      // verilator_coverage annotation
        // =============================================================================
        // File: uvm_tb/uvm_4chip_allreduce/mlu_4chip_allreduce_if.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: SystemVerilog Interface for Accellera UVM Suite 9:
        //              mlu_4chip_oam_node (4-Chip MLU-Link Ring & Butterfly AllReduce).
        // =============================================================================
        `ifndef MLU_4CHIP_ALLREDUCE_IF_SV
        `define MLU_4CHIP_ALLREDUCE_IF_SV
        
 001135 interface mlu_4chip_allreduce_if (input logic clk);
%000001   logic                rst_n;
        
          // Collective Ring / Butterfly AllReduce Controls & Outputs
 000160   logic                allreduce_start;
 000080   logic                allreduce_mode;
 000051   logic [3:0][63:0]    local_grad;
 000160   logic [3:0]          allreduce_done;
 000049   logic [3:0][63:0]    final_allreduce_sum;
 000160   logic                allreduce_busy;
~000080   logic [2:0]          allreduce_hops_taken;
        
          // Per-Chip Local MLU-Link Flit Injection & Ejection
 000025   logic [3:0]          chip_tx_valid;
%000001   logic [3:0]          chip_tx_ready;
          logic [3:0][127:0]   chip_tx_flit;
        
 000028   logic [3:0]          chip_rx_valid;
%000001   logic [3:0]          chip_rx_ready;
          logic [3:0][127:0]   chip_rx_flit;
        
          // Inter-Chip C2C SerDes Link Fault Injection & Handshake
 000012   logic [3:0]          link_err_inject;
 000193   logic [3:0]          link_ack_valid;
%000009   logic [3:0]          link_nack_valid;
        
          // Node-Wide Telemetry Counters
~000092   logic [31:0]         total_routed_flits;
~000017   logic [31:0]         total_crc_errs;
~000017   logic [31:0]         total_retransmits;
~000080   logic [31:0]         collective_completed_cnt;
        endinterface : mlu_4chip_allreduce_if
        
        `endif // MLU_4CHIP_ALLREDUCE_IF_SV
        
