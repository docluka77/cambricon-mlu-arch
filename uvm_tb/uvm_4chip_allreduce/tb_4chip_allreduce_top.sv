// =============================================================================
// File: uvm_tb/uvm_4chip_allreduce/tb_4chip_allreduce_top.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Top-Level UVM Testbench Module for Suite 9:
//              mlu_4chip_oam_node (4-Chip OAM Ring/Butterfly AllReduce).
// =============================================================================
`timescale 1ns/1ps
`include "uvm_macros.svh"
`include "mlu_pkg.sv"
`include "mlu_4chip_allreduce_if.sv"
`include "mlu_4chip_allreduce_uvm_pkg.sv"

module tb_4chip_allreduce_top;
  import uvm_pkg::*;
  import mlu_4chip_allreduce_uvm_pkg::*;

  logic clk = 1'b0;
  always #2.5 clk = ~clk;

  mlu_4chip_allreduce_if vif(clk);

  mlu_4chip_oam_node #(
    .NUM_CHIPS        (4),
    .PCS_REPLAY_DEPTH (8)
  ) u_dut (
    .clk_i                      (clk),
    .rst_ni                     (vif.rst_n),
    .allreduce_start_i          (vif.allreduce_start),
    .allreduce_mode_i           (vif.allreduce_mode),
    .local_grad_i               (vif.local_grad),
    .allreduce_done_o           (vif.allreduce_done),
    .final_allreduce_sum_o      (vif.final_allreduce_sum),
    .allreduce_busy_o           (vif.allreduce_busy),
    .allreduce_hops_taken_o     (vif.allreduce_hops_taken),
    .chip_tx_valid_i            (vif.chip_tx_valid),
    .chip_tx_ready_o            (vif.chip_tx_ready),
    .chip_tx_flit_i             (vif.chip_tx_flit),
    .chip_rx_valid_o            (vif.chip_rx_valid),
    .chip_rx_ready_i            (vif.chip_rx_ready),
    .chip_rx_flit_o             (vif.chip_rx_flit),
    .link_err_inject_i          (vif.link_err_inject),
    .link_ack_valid_o           (vif.link_ack_valid),
    .link_nack_valid_o          (vif.link_nack_valid),
    .total_routed_flits_o       (vif.total_routed_flits),
    .total_crc_errs_o           (vif.total_crc_errs),
    .total_retransmits_o        (vif.total_retransmits),
    .collective_completed_cnt_o (vif.collective_completed_cnt)
  );

  initial begin
    vif.rst_n = 1'b0;
    #20;
    vif.rst_n = 1'b1;
  end

  initial begin
    uvm_config_db #(virtual mlu_4chip_allreduce_if)::set(null, "*", "vif", vif);
    run_test("oam_4chip_test");
  end

endmodule : tb_4chip_allreduce_top
