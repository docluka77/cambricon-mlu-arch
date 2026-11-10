// =============================================================================
// File: formal/mlu_link_noc_pcs_formal.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Stage 10 Sequential SAT / BMC Formal Wrapper for mlu_link_noc_router
//              and mlu_c2c_serdes_pcs:
//              - Property 1: NoC VC1 Strict Priority & Deadlock-Free Local Routing
//              - Property 2: C2C SerDes PCS CRC-16 Error Detection & Replay Integrity
// =============================================================================
`include "mlu_pkg.sv"

module mlu_link_noc_pcs_formal (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        noc_inject_en_i,
  input  logic [63:0] vc0_payload_i,
  input  logic [63:0] vc1_payload_i,
  input  logic [63:0] pcs_tx_payload_i,
  input  logic [31:0] pcs_tx_addr_i,
  input  logic        err_inject_crc_i,
  output logic [4:0]  noc_out_valid_o,
  output logic [31:0] routed_flit_cnt_o,
  output logic [31:0] vc1_priority_cnt_o,
  output logic        pcs_rx_valid_o,
  output logic        pcs_ack_valid_o,
  output logic        pcs_nack_valid_o,
  output logic [31:0] crc_err_cnt_o,
  output logic [31:0] retransmit_cnt_o
);

  logic init_done_q;
  always_ff @(posedge clk) begin
    init_done_q <= 1'b1;
  end
  always_comb begin
    if (!init_done_q) assume (!rst_n);
    else              assume (rst_n);
  end

  // ---------------------------------------------------------------------------
  // 1. MLU-Link 5-Port Coherent NoC Router (ROUTER_ID = 4'd0)
  //    Simultaneous contention test on Port 1 (VC0 -> Local 0) & Port 2 (VC1 -> Local 0)
  // ---------------------------------------------------------------------------
  logic [4:0]        noc_in_valid;
  logic [4:0]        noc_in_ready;
  logic [4:0][127:0] noc_in_flit;
  logic [4:0][127:0] noc_out_flit;

  mlu_pkg::mlu_noc_flit_t flit_vc0_p1, flit_vc1_p2;
  always_comb begin
    flit_vc0_p1           = '0;
    flit_vc0_p1.flit_type = mlu_pkg::FLIT_HEAD_TAIL;
    flit_vc0_p1.vc_id     = 1'b0;
    flit_vc0_p1.src_id    = 4'd1;
    flit_vc0_p1.dst_id    = 4'd0; // Targets ROUTER_ID (Local Port 0)
    flit_vc0_p1.payload   = vc0_payload_i;

    flit_vc1_p2           = '0;
    flit_vc1_p2.flit_type = mlu_pkg::FLIT_HEAD_TAIL;
    flit_vc1_p2.vc_id     = 1'b1;
    flit_vc1_p2.src_id    = 4'd2;
    flit_vc1_p2.dst_id    = 4'd0; // Targets ROUTER_ID (Local Port 0)
    flit_vc1_p2.payload   = vc1_payload_i;

    noc_in_valid    = 5'b00000;
    noc_in_flit     = '0;
    if (noc_inject_en_i && noc_in_ready[1] && noc_in_ready[2] && (noc_out_valid_o == 5'b00000)) begin
      noc_in_valid[1] = 1'b1;
      noc_in_valid[2] = 1'b1;
      noc_in_flit[1]  = flit_vc0_p1;
      noc_in_flit[2]  = flit_vc1_p2;
    end
  end

  mlu_link_noc_router #(
    .ROUTER_ID (4'd0)
  ) u_noc_router (
    .clk                (clk),
    .rst_n              (rst_n),
    .allreduce_en_i     (1'b0),
    .in_valid_i         (noc_in_valid),
    .in_ready_o         (noc_in_ready),
    .in_flit_i          (noc_in_flit),
    .out_valid_o        (noc_out_valid_o),
    .out_ready_i        (5'b11111),
    .out_flit_o         (noc_out_flit),
    .routed_flit_cnt_o  (routed_flit_cnt_o),
    .vc1_priority_cnt_o (vc1_priority_cnt_o)
  );

  // ---------------------------------------------------------------------------
  // 2. MLU-Link C2C SerDes PCS Loopback (Algebraic CRC-16 Homomorphism Closure)
  // ---------------------------------------------------------------------------
  logic         pcs_tx_ready;
  logic [127:0] pcs_tx_flit;
  logic         link_tx_valid;
  logic [127:0] link_tx_flit;
  logic [127:0] pcs_rx_flit;
  logic [4:0]   pcs_ack_seq, pcs_nack_seq;
  logic         any_crc_err_seen_q;

  always_comb begin
    pcs_tx_flit          = '0;
    pcs_tx_flit[127:126] = mlu_pkg::FLIT_HEAD_TAIL;
    pcs_tx_flit[95:64]   = pcs_tx_addr_i;
    pcs_tx_flit[63:0]    = pcs_tx_payload_i;
  end

  mlu_c2c_serdes_pcs #(
    .REPLAY_DEPTH (2)
  ) u_pcs (
    .clk              (clk),
    .rst_n            (rst_n),
    .tx_valid_i       (1'b1),
    .tx_ready_o       (pcs_tx_ready),
    .tx_flit_i        (pcs_tx_flit),
    .link_tx_valid_o  (link_tx_valid),
    .link_tx_flit_o   (link_tx_flit),
    .link_rx_valid_i  (link_tx_valid),
    .link_rx_flit_i   (link_tx_flit),
    .err_inject_crc_i (err_inject_crc_i),
    .rx_valid_o       (pcs_rx_valid_o),
    .rx_flit_o        (pcs_rx_flit),
    .ack_valid_o      (pcs_ack_valid_o),
    .ack_seq_o        (pcs_ack_seq),
    .nack_valid_o     (pcs_nack_valid_o),
    .nack_seq_o       (pcs_nack_seq),
    .replay_trigger_i (1'b0),
    .replay_seq_i     (5'd0),
    .crc_err_cnt_o    (crc_err_cnt_o),
    .retransmit_cnt_o (retransmit_cnt_o)
  );

  logic        both_injected_d1_q;
  logic [63:0] exp_vc1_payload_q;
  logic [31:0] prev_vc1_cnt_q;
  logic        vc1_granted_d1_q;
  logic        crc_injected_d1_q;
  logic [31:0] prev_crc_err_cnt_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      both_injected_d1_q <= 1'b0;
      exp_vc1_payload_q  <= 64'd0;
      prev_vc1_cnt_q     <= 32'd0;
      vc1_granted_d1_q   <= 1'b0;
      any_crc_err_seen_q <= 1'b0;
      crc_injected_d1_q  <= 1'b0;
      prev_crc_err_cnt_q <= 32'd0;
    end else begin
      both_injected_d1_q <= noc_in_valid[1] && noc_in_valid[2];
      if (noc_in_valid[1] && noc_in_valid[2]) begin
        exp_vc1_payload_q <= vc1_payload_i;
      end
      prev_vc1_cnt_q     <= vc1_priority_cnt_o;
      vc1_granted_d1_q   <= both_injected_d1_q;

      if (err_inject_crc_i) begin
        any_crc_err_seen_q <= 1'b1;
      end
      crc_injected_d1_q  <= err_inject_crc_i;
      prev_crc_err_cnt_q <= crc_err_cnt_o;
    end
  end

  always_comb begin
    if (rst_n) begin
      // Property 1: NoC VC1 Strict Priority over VC0 & Local Port 0 Routing
      assert (noc_out_valid_o[4:1] == 4'b0000);
      if (both_injected_d1_q) begin
        assert (noc_out_valid_o[0] == 1'b1);
        assert (noc_out_flit[0][125] == 1'b1);
        assert (noc_out_flit[0][63:0] == exp_vc1_payload_q);
      end
      if (vc1_granted_d1_q) begin
        assert (vc1_priority_cnt_o == prev_vc1_cnt_q + 32'd1);
      end

      // Property 2: C2C SerDes PCS CRC-16 Error Detection & Replay Integrity
      if (!any_crc_err_seen_q && !err_inject_crc_i) begin
        assert (pcs_rx_valid_o == 1'b1);
        assert (pcs_ack_valid_o == 1'b1);
        assert (pcs_nack_valid_o == 1'b0);
        assert (pcs_rx_flit[63:0] == pcs_tx_payload_i);
        assert (pcs_rx_flit[95:64] == pcs_tx_addr_i);
      end
      if (err_inject_crc_i) begin
        assert (pcs_rx_valid_o == 1'b0);
        assert (pcs_ack_valid_o == 1'b0);
        assert (pcs_nack_valid_o == 1'b1);
      end
      if (crc_injected_d1_q) begin
        assert (crc_err_cnt_o == prev_crc_err_cnt_q + 32'd1);
      end
    end
  end

endmodule : mlu_link_noc_pcs_formal
