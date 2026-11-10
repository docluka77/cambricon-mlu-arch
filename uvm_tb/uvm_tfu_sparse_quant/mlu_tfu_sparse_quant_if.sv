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

interface mlu_tfu_sparse_quant_if (input logic clk);
  import mlu_pkg::*;

  logic        rst_n       = 1'b0;
  logic        cycle_valid = 1'b0;
  int unsigned cycle_id    = 0;

  // Dispatched TFU Command Interface
  logic         cmd_valid_i        = 1'b0;
  logic         cmd_ready_o;
  logic [127:0] cmd_inst_i         = 128'd0;

  // NRAM Activation & WRAM Weight + Sparsity Metadata Stream
  logic         stream_valid_i     = 1'b0;
  logic         stream_ready_o;
  logic [255:0] nram_act_i         = 256'd0;
  logic [255:0] wram_wt_i          = 256'd0;
  logic [31:0]  wram_sparse_meta_i = 32'd0;

  // Cambricon-Q Dynamic Quantization Parameters
  logic [15:0]  quant_scale_i      = 16'h0080;
  logic [7:0]   quant_zp_i         = 8'd0;

  // Status, Output Tile Result, and Telemetry
  logic         tfu_busy_o;
  logic [255:0] result_data_o;
  logic         result_valid_o;
  logic         done_valid_o;
  logic [7:0]   done_tag_o;
  logic [31:0]  zero_skip_cnt_o;
  logic [31:0]  total_mac_ops_o;
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
