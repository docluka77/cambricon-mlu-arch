// =============================================================================
// File: uvm_tb/uvm_sram_nram_wram/tb_sram_nram_wram_top.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Top-level Accellera IEEE 1800.2-2020 UVM Testbench Module for
//              Suite 1: mlu_sram_secded_ecc, mlu_sram_sp_macro,
//              mlu_nram_banked_scratchpad, mlu_wram_weight_buffer,
//              and mlu_mpu_shared_sram.
// =============================================================================
`timescale 1ns/1ps
`include "mlu_pkg.sv"
`include "mlu_sram_nram_wram_if.sv"
`include "mlu_sram_nram_wram_uvm_pkg.sv"

module tb_sram_nram_wram_top;
  import uvm_pkg::*;
  import mlu_pkg::*;
  import mlu_sram_nram_wram_uvm_pkg::*;

  bit clk = 1'b0;
  always #5ns clk = ~clk;

  mlu_sram_nram_wram_if       bus(clk);
  mlu_sram_nram_wram_dut_wrap u_dut(bus);

  initial begin
    uvm_config_db#(virtual mlu_sram_nram_wram_if)::set(null, "uvm_test_top.env.agent.*", "vif", bus);
    run_test("mlu_sram_nram_wram_test");
  end

  initial begin
    #1000us;
    $fatal(1, "UVM_SRAM_NRAM_WRAM_TIMEOUT: bounded simulation expired");
  end
endmodule : tb_sram_nram_wram_top
