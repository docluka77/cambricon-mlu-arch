//      // verilator_coverage annotation
        // =============================================================================
        // File: uvm_tb/uvm_bang_icu_pmu/mlu_bang_icu_pmu_if.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: SystemVerilog Interface & DUT Wrapper for Accellera UVM 2020.3.1
        //              Suite 2: mlu_bang_icu and mlu_pmu_clock_gate.
        // =============================================================================
        `ifndef MLU_BANG_ICU_PMU_IF_SV
        `define MLU_BANG_ICU_PMU_IF_SV
        
        `timescale 1ns/1ps
        `include "mlu_pkg.sv"
        
 001203 interface mlu_bang_icu_pmu_if (input logic clk);
          import mlu_pkg::*;
        
%000001   logic        rst_n       = 1'b0;
~001200   logic        cycle_valid = 1'b0;
%000001   int unsigned cycle_id    = 0;
        
          // Upstream BANG Instruction Fetch Interface
~000294   logic             inst_valid_i       = 1'b0;
 000322   logic             inst_ready_o;
~000493   logic [127:0]     inst_i             = 128'd0;
        
          // 5 Execution Queue Dispatch & Completion Interfaces
 000069   logic [4:0]       eng_cmd_valid_o;
%000001   logic [4:0]       eng_cmd_ready_i    = 5'b11111;
~000493   logic [127:0]     eng_cmd_inst_o;
 000069   logic [4:0]       icu_dispatch_mask_o;
        
%000001   logic             pwr_gate_cfg_valid_o;
%000001   logic [7:0]       idle_threshold_o;
        
 000010   logic             cluster_sync_req_o;
~000010   logic             cluster_sync_ack_i = 1'b0;
        
~000069   logic [4:0]       eng_done_valid_i   = 5'b00000;
~000050   logic [4:0][7:0]  eng_done_tag_i     = '0;
        
          // ICU Telemetry Outputs
 000069   logic [4:0]       queue_busy_o;
 000311   logic             hazard_stall_o;
~000161   logic [31:0]      inst_retired_cnt_o;
~000106   logic [31:0]      hazard_stall_cnt_o;
        
          // PMU Outputs
 000045   logic [4:0]       eng_clk_en_o;
 000078   logic [2:0]       sram_slp_o;
 000077   logic [2:0]       sram_dslp_o;
 000078   logic [2:0]       sram_wake_ready_o;
~000045   logic [31:0]      active_mac_cycles_o;
~000543   logic [31:0]      gated_saved_cycles_o;
~000381   logic [31:0]      sram_sleep_cycles_o;
        endinterface : mlu_bang_icu_pmu_if
        
        module mlu_bang_icu_pmu_dut_wrap (
          mlu_bang_icu_pmu_if bus
        );
          mlu_bang_icu #(
            .SCOREBOARD_SLOTS (8)
          ) u_dut_icu (
            .clk_i                (bus.clk),
            .rst_ni               (bus.rst_n),
            .inst_valid_i         (bus.inst_valid_i),
            .inst_ready_o         (bus.inst_ready_o),
            .inst_i               (bus.inst_i),
            .eng_cmd_valid_o      (bus.eng_cmd_valid_o),
            .eng_cmd_ready_i      (bus.eng_cmd_ready_i),
            .eng_cmd_inst_o       (bus.eng_cmd_inst_o),
            .icu_dispatch_mask_o  (bus.icu_dispatch_mask_o),
            .pwr_gate_cfg_valid_o (bus.pwr_gate_cfg_valid_o),
            .idle_threshold_o     (bus.idle_threshold_o),
            .cluster_sync_req_o   (bus.cluster_sync_req_o),
            .cluster_sync_ack_i   (bus.cluster_sync_ack_i),
            .eng_done_valid_i     (bus.eng_done_valid_i),
            .eng_done_tag_i       (bus.eng_done_tag_i),
            .queue_busy_o         (bus.queue_busy_o),
            .hazard_stall_o       (bus.hazard_stall_o),
            .inst_retired_cnt_o   (bus.inst_retired_cnt_o),
            .hazard_stall_cnt_o   (bus.hazard_stall_cnt_o)
          );
        
          mlu_pmu_clock_gate #(
            .DEFAULT_IDLE_THRESH (8'd4)
          ) u_dut_pmu (
            .clk_i                (bus.clk),
            .rst_ni               (bus.rst_n),
            .eng_busy_i           (bus.queue_busy_o),
            .icu_dispatch_mask_i  (bus.icu_dispatch_mask_o),
            .mem_active_i         ({bus.queue_busy_o[3], bus.queue_busy_o[0], bus.queue_busy_o[0] | bus.queue_busy_o[2]}),
            .pwr_gate_cfg_valid_i (bus.pwr_gate_cfg_valid_o),
            .idle_threshold_i     (bus.idle_threshold_o),
            .eng_clk_en_o         (bus.eng_clk_en_o),
            .sram_slp_o           (bus.sram_slp_o),
            .sram_dslp_o          (bus.sram_dslp_o),
            .sram_wake_ready_o    (bus.sram_wake_ready_o),
            .active_mac_cycles_o  (bus.active_mac_cycles_o),
            .gated_saved_cycles_o (bus.gated_saved_cycles_o),
            .sram_sleep_cycles_o  (bus.sram_sleep_cycles_o)
          );
        endmodule : mlu_bang_icu_pmu_dut_wrap
        
        `endif // MLU_BANG_ICU_PMU_IF_SV
        
