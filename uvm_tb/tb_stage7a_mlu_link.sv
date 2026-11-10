// =============================================================================
// File: uvm_tb/tb_stage7a_mlu_link.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Stage 7A Verification Testbench for MLU-Link 5-Port Coherent NoC
//              Router (Dual-VC, Wormhole Lock, In-Router AllReduce) and 512 GB/s
//              C2C SerDes PCS (CRC-16-CCITT Framing & Go-Back-N Replay Buffer).
// =============================================================================
`include "mlu_pkg.sv"

module tb_stage7a_mlu_link (
  input  logic clk,
  input  logic rst_n,
  output logic test_done_o,
  output logic test_pass_o
);

  // ---------------------------------------------------------------------------
  // 1. DUT Signals: 5-Port MLU-Link NoC Router (ROUTER_ID = 4'd0)
  // ---------------------------------------------------------------------------
  logic              rtr_allreduce_en;
  logic [4:0]        rtr_in_valid;
  logic [4:0]        rtr_in_ready;
  logic [4:0][127:0] rtr_in_flit;
  logic [4:0]        rtr_out_valid;
  logic [4:0]        rtr_out_ready;
  logic [4:0][127:0] rtr_out_flit;
  logic [31:0]       rtr_routed_cnt;
  logic [31:0]       rtr_vc1_prio_cnt;

  mlu_link_noc_router #(
    .ROUTER_ID (4'd0)
  ) u_noc_router (
    .clk                (clk),
    .rst_n              (rst_n),
    .allreduce_en_i     (rtr_allreduce_en),
    .in_valid_i         (rtr_in_valid),
    .in_ready_o         (rtr_in_ready),
    .in_flit_i          (rtr_in_flit),
    .out_valid_o        (rtr_out_valid),
    .out_ready_i        (rtr_out_ready),
    .out_flit_o         (rtr_out_flit),
    .routed_flit_cnt_o  (rtr_routed_cnt),
    .vc1_priority_cnt_o (rtr_vc1_prio_cnt)
  );

  // ---------------------------------------------------------------------------
  // 2. DUT Signals: MLU-Link C2C SerDes PCS (REPLAY_DEPTH = 8)
  // ---------------------------------------------------------------------------
  logic         pcs_tx_valid;
  logic         pcs_tx_ready;
  logic [127:0] pcs_tx_flit;
  logic         c2c_link_valid;
  logic [127:0] c2c_link_flit;
  logic         pcs_err_inject;
  logic         pcs_rx_valid;
  logic [127:0] pcs_rx_flit;
  logic         pcs_ack_valid;
  logic [4:0]   pcs_ack_seq;
  logic         pcs_nack_valid;
  logic [4:0]   pcs_nack_seq;
  logic [31:0]  pcs_crc_err_cnt;
  logic [31:0]  pcs_retransmit_cnt;

  mlu_c2c_serdes_pcs #(
    .REPLAY_DEPTH (8)
  ) u_c2c_pcs (
    .clk              (clk),
    .rst_n            (rst_n),
    .tx_valid_i       (pcs_tx_valid),
    .tx_ready_o       (pcs_tx_ready),
    .tx_flit_i        (pcs_tx_flit),
    .link_tx_valid_o  (c2c_link_valid),
    .link_tx_flit_o   (c2c_link_flit),
    .link_rx_valid_i  (c2c_link_valid),
    .link_rx_flit_i   (c2c_link_flit),
    .err_inject_crc_i (pcs_err_inject),
    .rx_valid_o       (pcs_rx_valid),
    .rx_flit_o        (pcs_rx_flit),
    .ack_valid_o      (pcs_ack_valid),
    .ack_seq_o        (pcs_ack_seq),
    .nack_valid_o     (pcs_nack_valid),
    .nack_seq_o       (pcs_nack_seq),
    .replay_trigger_i (pcs_nack_valid),
    .replay_seq_i     (pcs_nack_seq),
    .crc_err_cnt_o    (pcs_crc_err_cnt),
    .retransmit_cnt_o (pcs_retransmit_cnt)
  );

  // Helper to build a 128-bit mlu_noc_flit_t
  function automatic logic [127:0] make_flit(
    input mlu_pkg::mlu_flit_type_e ftype,
    input logic                    vc,
    input logic [3:0]              src,
    input logic [3:0]              dst,
    input logic [31:0]             addr,
    input logic [63:0]             payload
  );
    mlu_pkg::mlu_noc_flit_t f;
    f.flit_type    = ftype;
    f.vc_id        = vc;
    f.src_id       = src;
    f.dst_id       = dst;
    f.pkt_seq      = 5'd0;
    f.crc16_or_cmd = 16'd0;
    f.addr         = addr;
    f.payload      = payload;
    make_flit      = f;
  endfunction

  // ---------------------------------------------------------------------------
  // 3. Cycle-Accurate Test Sequencer & Scoreboard State
  // ---------------------------------------------------------------------------
  logic [31:0] cyc_q;
  logic [31:0] err_cnt_q;
  logic [31:0] wh_rx_step_q;
  logic [31:0] pcs_rx_cnt_q;
  logic [4:0]  pcs_last_ack_q;

  /* verilator lint_off UNUSEDSIGNAL */
  wire _unused_ok = &{1'b0, rtr_in_ready, rtr_out_flit, pcs_tx_ready,
                      pcs_rx_flit[127:64], pcs_ack_valid, pcs_ack_seq};
  /* verilator lint_on UNUSEDSIGNAL */

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cyc_q            <= 32'd0;
      err_cnt_q        <= 32'd0;
      wh_rx_step_q     <= 32'd0;
      pcs_rx_cnt_q     <= 32'd0;
      pcs_last_ack_q   <= 5'd0;
      rtr_allreduce_en <= 1'b0;
      rtr_in_valid     <= 5'b00000;
      rtr_in_flit      <= '0;
      rtr_out_ready    <= 5'b11111;
      pcs_tx_valid     <= 1'b0;
      pcs_tx_flit      <= '0;
      pcs_err_inject   <= 1'b0;
      test_done_o      <= 1'b0;
      test_pass_o      <= 1'b0;
    end else begin
      cyc_q          <= cyc_q + 32'd1;
      rtr_in_valid   <= 5'b00000;
      rtr_in_flit    <= '0;
      pcs_tx_valid   <= 1'b0;
      pcs_err_inject <= 1'b0;

      // -----------------------------------------------------------------------
      // Phase 1 (Cycles 1..6): 5-Port Deterministic Routing Verification
      //   dst=0->P0(Local), dst=2->P1(N), dst=5->P2(S), dst=9->P3(E), dst=13->P4(W)
      // -----------------------------------------------------------------------
      if (cyc_q == 32'd1) begin
        rtr_in_valid[0] <= 1'b1;
        rtr_in_flit[0]  <= make_flit(mlu_pkg::FLIT_HEAD_TAIL, 1'b0, 4'd0, 4'd2, 32'h1000, 64'hA1);
        rtr_in_valid[1] <= 1'b1;
        rtr_in_flit[1]  <= make_flit(mlu_pkg::FLIT_HEAD_TAIL, 1'b0, 4'd1, 4'd5, 32'h2000, 64'hA2);
        rtr_in_valid[2] <= 1'b1;
        rtr_in_flit[2]  <= make_flit(mlu_pkg::FLIT_HEAD_TAIL, 1'b0, 4'd2, 4'd9, 32'h3000, 64'hA3);
        rtr_in_valid[3] <= 1'b1;
        rtr_in_flit[3]  <= make_flit(mlu_pkg::FLIT_HEAD_TAIL, 1'b0, 4'd3, 4'd13, 32'h4000, 64'hA4);
        rtr_in_valid[4] <= 1'b1;
        rtr_in_flit[4]  <= make_flit(mlu_pkg::FLIT_HEAD_TAIL, 1'b0, 4'd4, 4'd0, 32'h5000, 64'hA0);
      end
      if (cyc_q == 32'd3) begin
        if (!(rtr_out_valid == 5'b11111 &&
              rtr_out_flit[0][63:0] == 64'hA0 &&
              rtr_out_flit[1][63:0] == 64'hA1 &&
              rtr_out_flit[2][63:0] == 64'hA2 &&
              rtr_out_flit[3][63:0] == 64'hA3 &&
              rtr_out_flit[4][63:0] == 64'hA4)) begin
          $display("[FAIL] Phase 1: 5-Port routing mismatch out_valid=%b", rtr_out_valid);
          err_cnt_q <= err_cnt_q + 32'd1;
        end else begin
          $display("[PASS] Phase 1: All 5 NoC Ports (Local/N/S/E/W) routed deterministically in parallel.");
        end
      end

      // -----------------------------------------------------------------------
      // Phase 2 (Cycles 6..14): Multi-Flit Wormhole Packet Lock Under Contention
      //   InPort 0 sends 3-flit wormhole packet (HEAD, BODY, TAIL) on VC0 -> P3 (dst=9)
      //   InPort 1 injects competing VC1 packet -> P3 (dst=9) during BODY cycle
      //   Verify P3 stays locked to InPort 0 until TAIL, then services InPort 1
      // -----------------------------------------------------------------------
      if (cyc_q == 32'd6) begin
        rtr_in_valid[0] <= 1'b1;
        rtr_in_flit[0]  <= make_flit(mlu_pkg::FLIT_HEAD, 1'b0, 4'd0, 4'd9, 32'h8000, 64'hB001);
      end
      if (cyc_q == 32'd7) begin
        rtr_in_valid[0] <= 1'b1;
        rtr_in_flit[0]  <= make_flit(mlu_pkg::FLIT_BODY, 1'b0, 4'd0, 4'd9, 32'h8008, 64'hB002);
        // Competing VC1 packet on InPort 1 targeting same Output Port 3 (dst=9)
        rtr_in_valid[1] <= 1'b1;
        rtr_in_flit[1]  <= make_flit(mlu_pkg::FLIT_HEAD_TAIL, 1'b1, 4'd1, 4'd9, 32'h9000, 64'hC999);
      end
      if (cyc_q == 32'd8) begin
        rtr_in_valid[0] <= 1'b1;
        rtr_in_flit[0]  <= make_flit(mlu_pkg::FLIT_TAIL, 1'b0, 4'd0, 4'd9, 32'h8010, 64'hB003);
      end
      if ((cyc_q >= 32'd7) && (cyc_q <= 32'd13) && rtr_out_valid[3]) begin
        wh_rx_step_q <= wh_rx_step_q + 32'd1;
        if (wh_rx_step_q == 32'd0 && rtr_out_flit[3][63:0] != 64'hB001) err_cnt_q <= err_cnt_q + 32'd1;
        if (wh_rx_step_q == 32'd1 && rtr_out_flit[3][63:0] != 64'hB002) err_cnt_q <= err_cnt_q + 32'd1;
        if (wh_rx_step_q == 32'd2 && rtr_out_flit[3][63:0] != 64'hB003) err_cnt_q <= err_cnt_q + 32'd1;
        if (wh_rx_step_q == 32'd3 && rtr_out_flit[3][63:0] != 64'hC999) err_cnt_q <= err_cnt_q + 32'd1;
      end
      if (cyc_q == 32'd14) begin
        if (wh_rx_step_q != 32'd4) begin
          $display("[FAIL] Phase 2: Wormhole lock step=%0d (expected 4)", wh_rx_step_q);
          err_cnt_q <= err_cnt_q + 32'd1;
        end else begin
          $display("[PASS] Phase 2: 3-Flit Wormhole Lock (HEAD->BODY->TAIL) prevented VC1 interleaving.");
        end
      end

      // -----------------------------------------------------------------------
      // Phase 3 (Cycles 15..21): VC0/VC1 Priority + In-Router AllReduce Combiner
      //   1) Cycle 15: InPort 0 sends VC0->P0, InPort 1 sends VC1->P0 (allreduce=0)
      //      Verify VC1 wins on Cycle 17, VC0 follows on Cycle 18
      //   2) Cycle 18: Enable allreduce_en_i=1, InPort 1 & InPort 2 both send
      //      VC1 AllReduce flits (0x100 + 0x250) -> P0; verify combined 0x350!
      // -----------------------------------------------------------------------
      if (cyc_q == 32'd15) begin
        rtr_allreduce_en <= 1'b0;
        rtr_in_valid[0]  <= 1'b1;
        rtr_in_flit[0]   <= make_flit(mlu_pkg::FLIT_HEAD_TAIL, 1'b0, 4'd0, 4'd0, 32'hA000, 64'hD000);
        rtr_in_valid[1]  <= 1'b1;
        rtr_in_flit[1]   <= make_flit(mlu_pkg::FLIT_HEAD_TAIL, 1'b1, 4'd1, 4'd0, 32'hA000, 64'hD111);
      end
      if (cyc_q == 32'd17) begin
        if (!(rtr_out_valid[0] && rtr_out_flit[0][63:0] == 64'hD111)) begin
          $display("[FAIL] Phase 3a: VC1 did not preempt VC0! got=%h", rtr_out_flit[0][63:0]);
          err_cnt_q <= err_cnt_q + 32'd1;
        end
      end
      if (cyc_q == 32'd18) begin
        if (!(rtr_out_valid[0] && rtr_out_flit[0][63:0] == 64'hD000)) begin
          $display("[FAIL] Phase 3b: VC0 did not follow VC1! got=%h", rtr_out_flit[0][63:0]);
          err_cnt_q <= err_cnt_q + 32'd1;
        end
        // Now test In-Router Hardware AllReduce Combiner
        rtr_allreduce_en <= 1'b1;
        rtr_in_valid[1]  <= 1'b1;
        rtr_in_flit[1]   <= make_flit(mlu_pkg::FLIT_HEAD_TAIL, 1'b1, 4'd1, 4'd0, 32'hB000, 64'h0000_0010_0000_0100);
        rtr_in_valid[2]  <= 1'b1;
        rtr_in_flit[2]   <= make_flit(mlu_pkg::FLIT_HEAD_TAIL, 1'b1, 4'd2, 4'd0, 32'hB000, 64'h0000_0025_0000_0250);
      end
      if (cyc_q == 32'd20) begin
        if (!(rtr_out_valid[0] && rtr_out_flit[0][63:0] == 64'h0000_0035_0000_0350)) begin
          $display("[FAIL] Phase 3c: In-Router AllReduce sum mismatch! got=%h", rtr_out_flit[0][63:0]);
          err_cnt_q <= err_cnt_q + 32'd1;
        end else begin
          $display("[PASS] Phase 3: VC1 Priority & In-Router AllReduce Combiner (0x10_0100 + 0x25_0250 = 0x35_0350) verified.");
        end
      end

      // -----------------------------------------------------------------------
      // Phase 4 (Cycles 22..40): C2C SerDes PCS CRC-16-CCITT & Go-Back-N Replay
      //   Send 6 flits (seq 0..5). On cycle 24 (seq 2), inject transient CRC bit-flip!
      //   Verify NACK triggers Go-Back-N replay of seq 2 and all 6 flits arrive
      //   in exact order (0, 1, 2, 3, 4, 5) with 0 data loss.
      // -----------------------------------------------------------------------
      if (cyc_q == 32'd22) begin
        pcs_tx_valid <= 1'b1;
        pcs_tx_flit  <= make_flit(mlu_pkg::FLIT_HEAD_TAIL, 1'b0, 4'd0, 4'd12, 32'hC000, 64'hF000);
      end
      if (cyc_q == 32'd23) begin
        pcs_tx_valid <= 1'b1;
        pcs_tx_flit  <= make_flit(mlu_pkg::FLIT_HEAD_TAIL, 1'b0, 4'd0, 4'd12, 32'hC008, 64'hF001);
      end
      if (cyc_q == 32'd24) begin
        pcs_tx_valid   <= 1'b1;
        pcs_tx_flit    <= make_flit(mlu_pkg::FLIT_HEAD_TAIL, 1'b0, 4'd0, 4'd12, 32'hC010, 64'hF002);
        pcs_err_inject <= 1'b1; // Inject transient C2C link bit-flip on seq=2!
      end
      // Note: Cycle 25 is automatically occupied by Go-Back-N Replay of seq=2!
      if (cyc_q == 32'd26) begin
        pcs_tx_valid <= 1'b1;
        pcs_tx_flit  <= make_flit(mlu_pkg::FLIT_HEAD_TAIL, 1'b0, 4'd0, 4'd12, 32'hC018, 64'hF003);
      end
      if (cyc_q == 32'd27) begin
        pcs_tx_valid <= 1'b1;
        pcs_tx_flit  <= make_flit(mlu_pkg::FLIT_HEAD_TAIL, 1'b0, 4'd0, 4'd12, 32'hC020, 64'hF004);
      end
      if (cyc_q == 32'd28) begin
        pcs_tx_valid <= 1'b1;
        pcs_tx_flit  <= make_flit(mlu_pkg::FLIT_HEAD_TAIL, 1'b0, 4'd0, 4'd12, 32'hC028, 64'hF005);
      end

      if (pcs_rx_valid) begin
        pcs_rx_cnt_q   <= pcs_rx_cnt_q + 32'd1;
        pcs_last_ack_q <= pcs_ack_seq;
        if (pcs_rx_flit[63:0] != (64'hF000 + {32'd0, pcs_rx_cnt_q})) begin
          $display("[FAIL] Phase 4: PCS RX ordering/payload mismatch! idx=%0d got=%h",
                   pcs_rx_cnt_q, pcs_rx_flit[63:0]);
          err_cnt_q <= err_cnt_q + 32'd1;
        end
      end

      // Final Summary Check at Cycle 34
      if (cyc_q == 32'd34) begin
        if (pcs_rx_cnt_q != 32'd6 || pcs_crc_err_cnt != 32'd1 ||
            pcs_retransmit_cnt != 32'd1 || pcs_last_ack_q != 5'd5) begin
          $display("[FAIL] Phase 4: PCS stats rx_cnt=%0d crc_err=%0d retx=%0d last_ack=%0d",
                   pcs_rx_cnt_q, pcs_crc_err_cnt, pcs_retransmit_cnt, pcs_last_ack_q);
          err_cnt_q <= err_cnt_q + 32'd1;
        end else begin
          $display("[PASS] Phase 4: C2C SerDes PCS CRC-16-CCITT error detected (crc_err=%0d) & Go-Back-N Replay recovered all %0d/6 flits losslessly (retx=%0d).",
                   pcs_crc_err_cnt, pcs_rx_cnt_q, pcs_retransmit_cnt);
        end
      end

      if (cyc_q == 32'd36) begin
        $display("==================================================================");
        $display("[STAGE 7A SUMMARY] routed_flits=%0d vc1_prio=%0d crc_err=%0d retx=%0d errors=%0d",
                 rtr_routed_cnt, rtr_vc1_prio_cnt, pcs_crc_err_cnt, pcs_retransmit_cnt, err_cnt_q);
        $display("==================================================================");
        test_done_o <= 1'b1;
        test_pass_o <= (err_cnt_q == 32'd0) && (rtr_routed_cnt >= 32'd12) && (rtr_vc1_prio_cnt >= 32'd3);
      end
    end
  end

endmodule : tb_stage7a_mlu_link
