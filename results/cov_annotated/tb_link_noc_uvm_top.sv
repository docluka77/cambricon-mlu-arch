//      // verilator_coverage annotation
        // =============================================================================
        // File: uvm_tb/uvm_mlu_link_noc/tb_link_noc_uvm_top.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: Top-level Accellera IEEE 1800.2-2020 UVM Testbench Module for
        //              Suite 6: mlu_link_noc_router + mlu_c2c_serdes_pcs.
        // =============================================================================
        `timescale 1ns/1ps
        `include "mlu_pkg.sv"
        `include "mlu_link_noc_if.sv"
        `include "mlu_link_noc_uvm_pkg.sv"
        
        module tb_link_noc_uvm_top;
          import uvm_pkg::*;
          import mlu_pkg::*;
          import mlu_link_noc_uvm_pkg::*;
        
~000804   bit clk = 1'b0;
 001607   always #5ns clk = ~clk;
        
          mlu_link_noc_if bus(clk);
          mlu_link_noc_dut_wrap u_dut(bus);
        
%000001   initial begin
%000001     uvm_config_db#(virtual mlu_link_noc_if)::set(null, "uvm_test_top.env.*", "vif", bus);
%000001     run_test("mlu_link_noc_test");
          end
        
          initial begin
            #4000us;
            $fatal(1, "UVM_MLU_LINK_NOC_TIMEOUT: simulation exceeded watchdog");
          end
        endmodule : tb_link_noc_uvm_top
        
