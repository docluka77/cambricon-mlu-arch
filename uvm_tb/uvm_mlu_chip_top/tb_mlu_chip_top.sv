// =============================================================================
// File: uvm_tb/uvm_mlu_chip_top/tb_mlu_chip_top.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Top-level Accellera IEEE 1800.2-2020 UVM Testbench Module for
//              Suite 8: mlu_chip_top.
// =============================================================================
`timescale 1ns/1ps
`include "mlu_pkg.sv"
`include "mlu_chip_top_if.sv"
`include "mlu_chip_top_uvm_pkg.sv"

module tb_mlu_chip_top;
  import uvm_pkg::*;
  import mlu_pkg::*;
  import mlu_chip_top_uvm_pkg::*;

  bit clk = 1'b0;
  always #5ns clk = ~clk;

  mlu_chip_top_if       bus(clk);
  mlu_chip_top_dut_wrap u_dut(bus);

  initial begin
    uvm_config_db#(virtual mlu_chip_top_if)::set(null, "uvm_test_top.env.agent.*", "vif", bus);
    run_test("mlu_chip_top_test");
  end

  initial begin
    #1000us;
    $fatal(1, "UVM_MLU_CHIP_TOP_TIMEOUT: bounded simulation expired");
  end
endmodule : tb_mlu_chip_top
