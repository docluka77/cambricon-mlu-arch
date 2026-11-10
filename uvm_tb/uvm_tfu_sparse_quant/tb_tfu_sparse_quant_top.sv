// =============================================================================
// File: uvm_tb/uvm_tfu_sparse_quant/tb_tfu_sparse_quant_top.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Top-level Accellera IEEE 1800.2-2020 UVM Testbench Module for
//              Suite 3: mlu_tfu_fractal_mac.
// =============================================================================
`timescale 1ns/1ps
`include "mlu_pkg.sv"
`include "mlu_tfu_sparse_quant_if.sv"
`include "mlu_tfu_sparse_quant_uvm_pkg.sv"

module tb_tfu_sparse_quant_top;
  import uvm_pkg::*;
  import mlu_pkg::*;
  import mlu_tfu_sparse_quant_uvm_pkg::*;

  bit clk = 1'b0;
  always #5ns clk = ~clk;

  mlu_tfu_sparse_quant_if       bus(clk);
  mlu_tfu_sparse_quant_dut_wrap u_dut(bus);

  initial begin
    uvm_config_db#(virtual mlu_tfu_sparse_quant_if)::set(null, "uvm_test_top.env.agent.*", "vif", bus);
    run_test("mlu_tfu_sparse_quant_test");
  end

  initial begin
    #1000us;
    $fatal(1, "UVM_TFU_SPARSE_QUANT_TIMEOUT: bounded simulation expired");
  end
endmodule : tb_tfu_sparse_quant_top
