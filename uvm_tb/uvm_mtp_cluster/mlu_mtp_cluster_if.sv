// =============================================================================
// File: uvm_tb/uvm_mtp_cluster/mlu_mtp_cluster_if.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: SystemVerilog Interface & DUT Wrapper for Accellera UVM 2020.3.1
//              Suite 7: mlu_mtp_cluster (4x IPU + 1x MPU + Sync Barrier + GDRAM)
// =============================================================================
`ifndef MLU_MTP_CLUSTER_IF_SV
`define MLU_MTP_CLUSTER_IF_SV

`timescale 1ns/1ps
`include "mlu_pkg.sv"

interface mlu_mtp_cluster_if (input logic clk);
  import mlu_pkg::*;

  logic               rst_n                  = 1'b0;
  logic               cycle_valid            = 1'b0;
  int unsigned        cycle_id               = 0;
  int unsigned        subtest_id             = 0;

  // 4-IPU BANG ISA Instruction Streams
  logic [3:0]         ipu_inst_valid         = 4'b0000;
  logic [3:0]         ipu_inst_ready;
  logic [3:0][127:0]  ipu_inst               = '0;

  // MPU Command Stream
  logic               mpu_cmd_valid          = 1'b0;
  logic               mpu_cmd_ready;
  logic [127:0]       mpu_cmd_inst           = 128'd0;
  logic               mpu_done_valid;
  logic [7:0]         mpu_done_tag;

  // Cluster Controls
  logic [3:0]         union_task_mask        = 4'b1111;
  logic               wram_ping_pong_sel     = 1'b0;
  logic [63:0]        mfu_idx_offset         = {16'd24, 16'd16, 16'd8, 16'd0};
  logic [7:0]         mfu_decomp_bitmap      = 8'b1010_0101;
  logic [127:0]       vfu_cos_sin_lut        = {4{16'h0080, 16'h00DF}};

  // External Host Access to Cluster Shared SRAM
  logic               ext_sram_valid         = 1'b0;
  logic               ext_sram_we            = 1'b0;
  logic [10:0]        ext_sram_addr          = 11'd0;
  logic [63:0]        ext_sram_wdata         = 64'd0;
  logic               ext_sram_grant;
  logic [63:0]        ext_sram_rdata;
  logic               ext_sram_rvalid;

  // Aggregated GDRAM Interface (Monitored)
  logic               gdram_req_valid;
  logic               gdram_req_we;
  logic [31:0]        gdram_req_addr;
  logic [63:0]        gdram_req_wdata;
  logic               gdram_resp_valid;
  logic [63:0]        gdram_resp_rdata;

  // Cluster MLU-Link NoC Flit TX / RX Interface
  logic               noc_tx_valid;
  logic               noc_tx_ready           = 1'b1;
  logic [127:0]       noc_tx_flit;
  logic               noc_rx_valid;
  logic               noc_rx_ready;
  logic [127:0]       noc_rx_flit;

  // ECC Fault Injection & Cluster Telemetry
  logic [2:0]         err_inject_bank        = 3'd0;
  logic [71:0]        err_inject_mask        = 72'd0;
  logic               cluster_sec_err;
  logic               cluster_ded_err;
  logic               cluster_busy;
  logic [31:0]        union_barrier_cnt;
  logic [31:0]        cluster_retired_insts;
  logic [31:0]        cluster_active_mac_cycles;
  logic [31:0]        cluster_gated_saved_cycles;
  logic [31:0]        cluster_total_mac_ops;
endinterface : mlu_mtp_cluster_if

module mlu_mtp_cluster_dut_wrap (mlu_mtp_cluster_if bus);
  import mlu_pkg::*;

  mlu_mtp_cluster #(
    .CLUSTER_ID (4'd0),
    .NUM_IPUS   (4)
  ) u_mtp_cluster (
    .clk_i                        (bus.clk),
    .rst_ni                       (bus.rst_n),
    .ipu_inst_valid_i             (bus.ipu_inst_valid),
    .ipu_inst_ready_o             (bus.ipu_inst_ready),
    .ipu_inst_i                   (bus.ipu_inst),
    .mpu_cmd_valid_i              (bus.mpu_cmd_valid),
    .mpu_cmd_ready_o              (bus.mpu_cmd_ready),
    .mpu_cmd_inst_i               (bus.mpu_cmd_inst),
    .mpu_done_valid_o             (bus.mpu_done_valid),
    .mpu_done_tag_o               (bus.mpu_done_tag),
    .union_task_mask_i            (bus.union_task_mask),
    .wram_ping_pong_sel_i         (bus.wram_ping_pong_sel),
    .mfu_idx_offset_i             (bus.mfu_idx_offset),
    .mfu_decomp_bitmap_i          (bus.mfu_decomp_bitmap),
    .vfu_cos_sin_lut_i            (bus.vfu_cos_sin_lut),
    .ext_sram_valid_i             (bus.ext_sram_valid),
    .ext_sram_we_i                (bus.ext_sram_we),
    .ext_sram_addr_i              (bus.ext_sram_addr),
    .ext_sram_wdata_i             (bus.ext_sram_wdata),
    .ext_sram_grant_o             (bus.ext_sram_grant),
    .ext_sram_rdata_o             (bus.ext_sram_rdata),
    .ext_sram_rvalid_o            (bus.ext_sram_rvalid),
    .gdram_req_valid_o            (bus.gdram_req_valid),
    .gdram_req_we_o               (bus.gdram_req_we),
    .gdram_req_addr_o             (bus.gdram_req_addr),
    .gdram_req_wdata_o            (bus.gdram_req_wdata),
    .gdram_resp_valid_i           (bus.gdram_resp_valid),
    .gdram_resp_rdata_i           (bus.gdram_resp_rdata),
    .noc_tx_valid_o               (bus.noc_tx_valid),
    .noc_tx_ready_i               (bus.noc_tx_ready),
    .noc_tx_flit_o                (bus.noc_tx_flit),
    .noc_rx_valid_i               (bus.noc_rx_valid),
    .noc_rx_ready_o               (bus.noc_rx_ready),
    .noc_rx_flit_i                (bus.noc_rx_flit),
    .err_inject_bank_i            (bus.err_inject_bank),
    .err_inject_mask_i            (bus.err_inject_mask),
    .cluster_sec_err_o            (bus.cluster_sec_err),
    .cluster_ded_err_o            (bus.cluster_ded_err),
    .cluster_busy_o               (bus.cluster_busy),
    .union_barrier_cnt_o          (bus.union_barrier_cnt),
    .cluster_retired_insts_o      (bus.cluster_retired_insts),
    .cluster_active_mac_cycles_o  (bus.cluster_active_mac_cycles),
    .cluster_gated_saved_cycles_o (bus.cluster_gated_saved_cycles),
    .cluster_total_mac_ops_o      (bus.cluster_total_mac_ops)
  );

  // Behavioral HBM2e GDRAM Responder (256 x 64-bit words)
  logic [63:0] gdram_mem [0:255];
  always_ff @(posedge bus.clk or negedge bus.rst_n) begin
    if (!bus.rst_n) begin
      bus.gdram_resp_valid <= 1'b0;
      bus.gdram_resp_rdata <= 64'd0;
      for (int i = 0; i < 256; i++) begin
        gdram_mem[i] <= {16'(i + 1), 16'(i + 2), 16'(i + 3), 16'(i + 4)};
      end
    end else begin
      bus.gdram_resp_valid <= bus.gdram_req_valid && !bus.gdram_req_we;
      if (bus.gdram_req_valid) begin
        if (bus.gdram_req_we) begin
          gdram_mem[bus.gdram_req_addr[10:3]] <= bus.gdram_req_wdata;
        end else begin
          bus.gdram_resp_rdata <= gdram_mem[bus.gdram_req_addr[10:3]];
        end
      end
    end
  end

  // 6-Stage Registered Loopback Pipeline for NoC AllReduce Flits
  logic [5:0]        noc_pipe_v;
  logic [5:0][127:0] noc_pipe_f;
  always_ff @(posedge bus.clk or negedge bus.rst_n) begin
    if (!bus.rst_n) begin
      noc_pipe_v <= '0;
      noc_pipe_f <= '0;
    end else begin
      noc_pipe_v[0] <= bus.noc_tx_valid;
      noc_pipe_f[0] <= bus.noc_tx_flit;
      for (int s = 1; s < 6; s++) begin
        noc_pipe_v[s] <= noc_pipe_v[s-1];
        noc_pipe_f[s] <= noc_pipe_f[s-1];
      end
    end
  end
  assign bus.noc_rx_valid = noc_pipe_v[5];
  assign bus.noc_rx_flit  = noc_pipe_f[5];

endmodule : mlu_mtp_cluster_dut_wrap

`endif // MLU_MTP_CLUSTER_IF_SV
