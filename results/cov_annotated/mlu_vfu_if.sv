//      // verilator_coverage annotation
        // =============================================================================
        // File: uvm_tb/uvm_vfu_llm_ops/mlu_vfu_if.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: SystemVerilog Interface & DUT Wrapper for Accellera IEEE 1800.2-2020
        //              UVM Verification of mlu_vfu_sfu_pipe (All 7 BANG Vector/LLM Ops).
        // =============================================================================
        `ifndef MLU_VFU_IF_SV
        `define MLU_VFU_IF_SV
        
        `include "mlu_pkg.sv"
        
 001685 interface mlu_vfu_if (input logic clk);
%000001   logic         rst_ni;
 000560   logic         cmd_valid_i;
 000561   logic         cmd_ready_o;
~000280   logic [127:0] cmd_inst_i;
 000494   logic [127:0] vec_a_i;
 000428   logic [127:0] vec_b_i;
 000423   logic [127:0] cos_sin_lut_i;
        
 000565   logic [127:0] vec_out_o;
 000560   logic         vec_out_valid_o;
~000031   logic [31:0]  softmax_sum_o;
~000019   logic [15:0]  softmax_max_o;
~000022   logic [15:0]  absmax_o;
~000021   logic [15:0]  min_val_o;
~000022   logic [15:0]  max_val_o;
~000025   logic [15:0]  dyn_scale_o;
 000560   logic         vfu_busy_o;
 000560   logic         done_valid_o;
~000280   logic [7:0]   done_tag_o;
        
          // Latched command context at issue time for monitor correlation
~000280   logic [127:0] mon_cmd_inst;
 000494   logic [127:0] mon_vec_a;
 000428   logic [127:0] mon_vec_b;
 000423   logic [127:0] mon_cos_sin_lut;
        endinterface : mlu_vfu_if
        
        module mlu_vfu_dut_wrap (mlu_vfu_if bus);
          mlu_vfu_sfu_pipe u_dut (
            .clk_i           (bus.clk),
            .rst_ni          (bus.rst_ni),
            .cmd_valid_i     (bus.cmd_valid_i),
            .cmd_ready_o     (bus.cmd_ready_o),
            .cmd_inst_i      (bus.cmd_inst_i),
            .vec_a_i         (bus.vec_a_i),
            .vec_b_i         (bus.vec_b_i),
            .cos_sin_lut_i   (bus.cos_sin_lut_i),
            .vec_out_o       (bus.vec_out_o),
            .vec_out_valid_o (bus.vec_out_valid_o),
            .softmax_sum_o   (bus.softmax_sum_o),
            .softmax_max_o   (bus.softmax_max_o),
            .absmax_o        (bus.absmax_o),
            .min_val_o       (bus.min_val_o),
            .max_val_o       (bus.max_val_o),
            .dyn_scale_o     (bus.dyn_scale_o),
            .vfu_busy_o      (bus.vfu_busy_o),
            .done_valid_o    (bus.done_valid_o),
            .done_tag_o      (bus.done_tag_o)
          );
        endmodule : mlu_vfu_dut_wrap
        
        `endif // MLU_VFU_IF_SV
        
