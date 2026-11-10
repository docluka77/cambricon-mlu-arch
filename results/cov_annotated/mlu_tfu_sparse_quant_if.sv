//      // verilator_coverage annotation
        // =============================================================================
        // File: uvm_tb/uvm_tfu_sparse_quant/mlu_tfu_sparse_quant_if.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: SystemVerilog Interface & DUT Wrapper for Accellera UVM 2020.3.1
        //              Suite 3: mlu_tfu_fractal_mac.
        // =============================================================================
        `ifndef MLU_TFU_SPARSE_QUANT_IF_SV
        `define MLU_TFU_SPARSE_QUANT_IF_SV
        
        `timescale 1ns/1ps
        `include "mlu_pkg.sv"
        
 001203 interface mlu_tfu_sparse_quant_if (input logic clk);
          import mlu_pkg::*;
        
%000001   logic        rst_n       = 1'b0;
~001200   logic        cycle_valid = 1'b0;
%000001   int unsigned cycle_id    = 0;
        
          // Dispatched TFU Command Interface
~000200   logic         cmd_valid_i        = 1'b0;
 000201   logic         cmd_ready_o;
~000100   logic [127:0] cmd_inst_i         = 128'd0;
        
          // NRAM Activation & WRAM Weight + Sparsity Metadata Stream
~000200   logic         stream_valid_i     = 1'b0;
 000200   logic         stream_ready_o;
~002448   logic [255:0] nram_act_i         = 256'd0;
~002466   logic [255:0] wram_wt_i          = 256'd0;
~000247   logic [31:0]  wram_sparse_meta_i = 32'd0;
        
          // Cambricon-Q Dynamic Quantization Parameters
~000100   logic [15:0]  quant_scale_i      = 16'h0080;
~000100   logic [7:0]   quant_zp_i         = 8'd0;
        
          // Status, Output Tile Result, and Telemetry
 000200   logic         tfu_busy_o;
 000617   logic [255:0] result_data_o;
 000200   logic         result_valid_o;
 000200   logic         done_valid_o;
~000100   logic [7:0]   done_tag_o;
~000050   logic [31:0]  zero_skip_cnt_o;
~000195   logic [31:0]  total_mac_ops_o;
        endinterface : mlu_tfu_sparse_quant_if
        
        module mlu_tfu_sparse_quant_dut_wrap (
          mlu_tfu_sparse_quant_if bus
        );
          mlu_tfu_fractal_mac u_dut_tfu (
            .clk_i              (bus.clk),
            .rst_ni             (bus.rst_n),
            .cmd_valid_i        (bus.cmd_valid_i),
            .cmd_ready_o        (bus.cmd_ready_o),
            .cmd_inst_i         (bus.cmd_inst_i),
            .stream_valid_i     (bus.stream_valid_i),
            .stream_ready_o     (bus.stream_ready_o),
            .nram_act_i         (bus.nram_act_i),
            .wram_wt_i          (bus.wram_wt_i),
            .wram_sparse_meta_i (bus.wram_sparse_meta_i),
            .quant_scale_i      (bus.quant_scale_i),
            .quant_zp_i         (bus.quant_zp_i),
            .tfu_busy_o         (bus.tfu_busy_o),
            .result_data_o      (bus.result_data_o),
            .result_valid_o     (bus.result_valid_o),
            .done_valid_o       (bus.done_valid_o),
            .done_tag_o         (bus.done_tag_o),
            .zero_skip_cnt_o    (bus.zero_skip_cnt_o),
            .total_mac_ops_o    (bus.total_mac_ops_o)
          );
        endmodule : mlu_tfu_sparse_quant_dut_wrap
        
        `endif // MLU_TFU_SPARSE_QUANT_IF_SV
        
