// =============================================================================
// File: uvm_tb/uvm_mtp_cluster/tb_mtp_cluster_top.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Top-level Accellera IEEE 1800.2-2020 UVM Testbench Module for
//              Suite 7: mlu_mtp_cluster.
// =============================================================================
`timescale 1ns/1ps
`include "mlu_pkg.sv"
`include "mlu_mtp_cluster_if.sv"
`include "mlu_mtp_cluster_uvm_pkg.sv"

module tb_mtp_cluster_top;
  import uvm_pkg::*;
  import mlu_pkg::*;
  import mlu_mtp_cluster_uvm_pkg::*;

  bit clk = 1'b0;
  always #5ns clk = ~clk;

  mlu_mtp_cluster_if       bus(clk);
  mlu_mtp_cluster_dut_wrap u_dut(bus);

  initial begin
    uvm_config_db#(virtual mlu_mtp_cluster_if)::set(null, "uvm_test_top.env.agent.*", "vif", bus);
    run_test("mlu_mtp_cluster_test");
  end

  initial begin
    #1000us;
    $fatal(1, "UVM_MTP_CLUSTER_TIMEOUT: bounded simulation expired");
  end
endmodule : tb_mtp_cluster_top
