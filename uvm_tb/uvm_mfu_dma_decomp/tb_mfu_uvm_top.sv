// =============================================================================
// File: uvm_tb/uvm_mfu_dma_decomp/tb_mfu_uvm_top.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Top-level Accellera IEEE 1800.2-2020 UVM Testbench Module for
//              Suite 5: mlu_mfu_dma_engine.
// =============================================================================
`timescale 1ns/1ps
`include "mlu_pkg.sv"
`include "mlu_mfu_if.sv"
`include "mlu_mfu_uvm_pkg.sv"

module tb_mfu_uvm_top;
  import uvm_pkg::*;
  import mlu_pkg::*;
  import mlu_mfu_uvm_pkg::*;

  bit clk = 1'b0;
  always #5ns clk = ~clk;

  mlu_mfu_if bus(clk);
  mlu_mfu_dut_wrap u_dut(bus);

  initial begin
    uvm_config_db#(virtual mlu_mfu_if)::set(null, "uvm_test_top.env.*", "vif", bus);
    run_test("mfu_dma_decomp_test");
  end

  initial begin
    #4000us;
    $fatal(1, "UVM_MFU_DMA_DECOMP_TIMEOUT: simulation exceeded watchdog");
  end
endmodule : tb_mfu_uvm_top
