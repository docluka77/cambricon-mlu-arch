// =============================================================================
// File: formal/mlu_4chip_oam_node_formal.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Yosys 0.60 Formal Verification Harness for mlu_4chip_oam_node:
//              1. Ring AllReduce (3-Hop) & Butterfly AllReduce (2-Hop) 4-Chip
//                 Mathematical Consensus (final_allreduce_sum_o[0..3] == sum(grad0..3))
//              2. C2C SerDes PCS CRC-16-CCITT Fault Detection, NACK Handshake,
//                 & Go-Back-N Replay Stall Integrity without Sum Corruption.
// =============================================================================
`include "mlu_pkg.sv"

module mlu_4chip_oam_node_formal (
  input logic         clk_i,
  input logic         allreduce_start_i,
  input logic         allreduce_mode_i,
  input logic [63:0]  grad0_i,
  input logic [63:0]  grad1_i,
  input logic [63:0]  grad2_i,
  input logic [63:0]  grad3_i,
  input logic [3:0]   link_err_inject_i
);

  logic [3:0]        cyc_q = 4'd0;
  logic              rst_ni;
  assign rst_ni = (cyc_q > 4'd0);

  always_ff @(posedge clk_i) begin
    if (cyc_q < 4'd15)
      cyc_q <= cyc_q + 4'd1;
  end

  logic [3:0][63:0]  local_grad;
  assign local_grad[0] = grad0_i;
  assign local_grad[1] = grad1_i;
  assign local_grad[2] = grad2_i;
  assign local_grad[3] = grad3_i;

  logic [3:0]        allreduce_done;
  logic [3:0][63:0]  final_allreduce_sum;
  logic              allreduce_busy;
  logic [2:0]        allreduce_hops_taken;
  logic [3:0]        chip_tx_ready;
  logic [3:0]        chip_rx_valid;
  logic [3:0][127:0] chip_rx_flit;
  logic [3:0]        link_ack_valid;
  logic [3:0]        link_nack_valid;
  logic [31:0]       total_routed_flits;
  logic [31:0]       total_crc_errs;
  logic [31:0]       total_retransmits;
  logic [31:0]       collective_completed_cnt;

  mlu_4chip_oam_node #(
    .NUM_CHIPS        (4),
    .PCS_REPLAY_DEPTH (2)
  ) u_dut (
    .clk_i                      (clk_i),
    .rst_ni                     (rst_ni),
    .allreduce_start_i          (allreduce_start_i),
    .allreduce_mode_i           (allreduce_mode_i),
    .local_grad_i               (local_grad),
    .allreduce_done_o           (allreduce_done),
    .final_allreduce_sum_o      (final_allreduce_sum),
    .allreduce_busy_o           (allreduce_busy),
    .allreduce_hops_taken_o     (allreduce_hops_taken),
    .chip_tx_valid_i            (4'b0000),
    .chip_tx_ready_o            (chip_tx_ready),
    .chip_tx_flit_i             ('0),
    .chip_rx_valid_o            (chip_rx_valid),
    .chip_rx_ready_i            (4'b1111),
    .chip_rx_flit_o             (chip_rx_flit),
    .link_err_inject_i          (link_err_inject_i),
    .link_ack_valid_o           (link_ack_valid),
    .link_nack_valid_o          (link_nack_valid),
    .total_routed_flits_o       (total_routed_flits),
    .total_crc_errs_o           (total_crc_errs),
    .total_retransmits_o        (total_retransmits),
    .collective_completed_cnt_o (collective_completed_cnt)
  );

  // Reference Golden Mathematical Tracker
  logic [63:0] ref_expected_sum_q;
  logic        ref_mode_q;
  logic        ref_started_q;
  logic [31:0] prev_crc_errs_q;
  logic        had_err_inject_q;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      ref_expected_sum_q <= 64'd0;
      ref_mode_q         <= 1'b0;
      ref_started_q      <= 1'b0;
      prev_crc_errs_q    <= 32'd0;
      had_err_inject_q   <= 1'b0;
    end else begin
      prev_crc_errs_q  <= total_crc_errs;
      had_err_inject_q <= allreduce_busy && (|link_err_inject_i);

      if (allreduce_start_i && !allreduce_busy) begin
        ref_expected_sum_q <= grad0_i + grad1_i + grad2_i + grad3_i;
        ref_mode_q         <= allreduce_mode_i;
        ref_started_q      <= 1'b1;
      end

      // Property 1: 4-Chip Ring & Butterfly AllReduce Mathematical Consensus
      if (ref_started_q && (allreduce_done == 4'b1111) && !(allreduce_start_i && !allreduce_busy)) begin
        assert(final_allreduce_sum[0] == ref_expected_sum_q);
        assert(final_allreduce_sum[1] == ref_expected_sum_q);
        assert(final_allreduce_sum[2] == ref_expected_sum_q);
        assert(final_allreduce_sum[3] == ref_expected_sum_q);
        assert(final_allreduce_sum[0] == final_allreduce_sum[1]);
        assert(final_allreduce_sum[1] == final_allreduce_sum[2]);
        assert(final_allreduce_sum[2] == final_allreduce_sum[3]);
        assert(allreduce_hops_taken == (ref_mode_q ? 3'd2 : 3'd3));
      end

      // Property 2: C2C SerDes PCS Link CRC Fault Detection & Counter Increment
      if (allreduce_busy) begin
        for (int c = 0; c < 4; c++) begin
          if (link_err_inject_i[c]) begin
            assert(link_nack_valid[c] == 1'b1);
          end
        end
      end
      if (had_err_inject_q) begin
        assert(total_crc_errs > prev_crc_errs_q);
      end
    end
  end

endmodule : mlu_4chip_oam_node_formal
