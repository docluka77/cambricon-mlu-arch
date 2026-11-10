// =============================================================================
// File: uvm_tb/uvm_vfu_llm_ops/tb_vfu_uvm_top.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Top-level Accellera IEEE 1800.2-2020 UVM Testbench Module for
//              Suite 4: mlu_vfu_sfu_pipe (Vector & LLM SFU Pipeline).
// =============================================================================
`timescale 1ns/1ps
`include "mlu_pkg.sv"
`include "mlu_vfu_if.sv"
`include "mlu_vfu_uvm_pkg.sv"

module tb_vfu_uvm_top;
  import uvm_pkg::*;
  import mlu_pkg::*;
  import mlu_vfu_uvm_pkg::*;

  bit clk = 1'b0;
  always #5ns clk = ~clk;

  mlu_vfu_if bus(clk);
  mlu_vfu_dut_wrap u_dut(bus);

  initial begin
    uvm_config_db#(virtual mlu_vfu_if)::set(null, "uvm_test_top.env.*", "vif", bus);
    run_test("vfu_llm_ops_test");
  end

  initial begin
    #2000us;
    $fatal(1, "UVM_VFU_LLM_OPS_TIMEOUT: simulation exceeded watchdog");
  end
endmodule : tb_vfu_uvm_top
