//      // verilator_coverage annotation
        // =============================================================================
        // File: uvm_tb/uvm_bang_icu_pmu/tb_bang_icu_pmu_top.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: Top-level Accellera IEEE 1800.2-2020 UVM Testbench Module for
        //              Suite 2: mlu_bang_icu and mlu_pmu_clock_gate.
        // =============================================================================
        `timescale 1ns/1ps
        `include "mlu_pkg.sv"
        `include "mlu_bang_icu_pmu_if.sv"
        `include "mlu_bang_icu_pmu_uvm_pkg.sv"
        
        module tb_bang_icu_pmu_top;
          import uvm_pkg::*;
          import mlu_pkg::*;
          import mlu_bang_icu_pmu_uvm_pkg::*;
        
~001203   bit clk = 1'b0;
 002406   always #5ns clk = ~clk;
        
          mlu_bang_icu_pmu_if       bus(clk);
          mlu_bang_icu_pmu_dut_wrap u_dut(bus);
        
%000001   initial begin
%000001     uvm_config_db#(virtual mlu_bang_icu_pmu_if)::set(null, "uvm_test_top.env.agent.*", "vif", bus);
%000001     run_test("mlu_bang_icu_pmu_test");
          end
        
          initial begin
            #1000us;
            $fatal(1, "UVM_BANG_ICU_PMU_TIMEOUT: bounded simulation expired");
          end
        endmodule : tb_bang_icu_pmu_top
        
