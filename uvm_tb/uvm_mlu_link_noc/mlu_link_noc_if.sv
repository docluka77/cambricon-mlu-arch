// =============================================================================
// File: uvm_tb/uvm_mlu_link_noc/mlu_link_noc_if.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: SystemVerilog Interface & DUT Wrapper for Accellera IEEE 1800.2-2020
//              UVM Verification of mlu_link_noc_router + mlu_c2c_serdes_pcs.
// =============================================================================
`ifndef MLU_LINK_NOC_IF_SV
`define MLU_LINK_NOC_IF_SV

`include "mlu_pkg.sv"

interface mlu_link_noc_if (input logic clk);
  logic             rst_n;
  int unsigned      cycle_id;

  // NoC Router Interface (ROUTER_ID = 4'd1)
  logic             allreduce_en_i;
  logic [4:0]        in_valid_i;
  logic [4:0]        in_ready_o;
  logic [4:0][127:0] in_flit_i;
  logic [4:0]        out_valid_o;
  logic [4:0]        out_ready_i;
  logic [4:0][127:0] out_flit_o;
  logic [31:0]       routed_flit_cnt_o;
  logic [31:0]       vc1_priority_cnt_o;

  // C2C SerDes PCS Interface (Loopback Link TX -> RX)
  logic             tx_valid_i;
  logic             tx_ready_o;
  logic [127:0]     tx_flit_i;
  logic             link_tx_valid_o;
  logic [127:0]     link_tx_flit_o;
  logic             err_inject_crc_i;
  logic             rx_valid_o;
  logic [127:0]     rx_flit_o;
  logic             ack_valid_o;
  logic [4:0]       ack_seq_o;
  logic             nack_valid_o;
  logic [4:0]       nack_seq_o;
  logic             replay_trigger_i;
  logic [4:0]       replay_seq_i;
  logic [31:0]      crc_err_cnt_o;
  logic [31:0]      retransmit_cnt_o;
endinterface : mlu_link_noc_if

module mlu_link_noc_dut_wrap (mlu_link_noc_if bus);
  mlu_link_noc_router #(
    .ROUTER_ID (4'd1)
  ) u_router (
    .clk                (bus.clk),
    .rst_n              (bus.rst_n),
    .allreduce_en_i     (bus.allreduce_en_i),
    .in_valid_i         (bus.in_valid_i),
    .in_ready_o         (bus.in_ready_o),
    .in_flit_i          (bus.in_flit_i),
    .out_valid_o        (bus.out_valid_o),
    .out_ready_i        (bus.out_ready_i),
    .out_flit_o         (bus.out_flit_o),
    .routed_flit_cnt_o  (bus.routed_flit_cnt_o),
    .vc1_priority_cnt_o (bus.vc1_priority_cnt_o)
  );

  mlu_c2c_serdes_pcs #(
    .REPLAY_DEPTH (8)
  ) u_serdes (
    .clk              (bus.clk),
    .rst_n            (bus.rst_n),
    .tx_valid_i       (bus.tx_valid_i),
    .tx_ready_o       (bus.tx_ready_o),
    .tx_flit_i        (bus.tx_flit_i),
    .link_tx_valid_o  (bus.link_tx_valid_o),
    .link_tx_flit_o   (bus.link_tx_flit_o),
    .link_rx_valid_i  (bus.link_tx_valid_o),
    .link_rx_flit_i   (bus.link_tx_flit_o),
    .err_inject_crc_i (bus.err_inject_crc_i),
    .rx_valid_o       (bus.rx_valid_o),
    .rx_flit_o        (bus.rx_flit_o),
    .ack_valid_o      (bus.ack_valid_o),
    .ack_seq_o        (bus.ack_seq_o),
    .nack_valid_o     (bus.nack_valid_o),
    .nack_seq_o       (bus.nack_seq_o),
    .replay_trigger_i (bus.replay_trigger_i),
    .replay_seq_i     (bus.replay_seq_i),
    .crc_err_cnt_o    (bus.crc_err_cnt_o),
    .retransmit_cnt_o (bus.retransmit_cnt_o)
  );
endmodule : mlu_link_noc_dut_wrap

`endif // MLU_LINK_NOC_IF_SV
