//      // verilator_coverage annotation
        // =============================================================================
        // File: rtl/mlu_c2c_serdes_pcs.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: Cambricon MLU-Link 512 GB/s Chiplet-to-Chiplet (C2C) &
        //              Card-to-Card High-Speed SerDes Physical Coding Sublayer (PCS)
        //              with Hardware CRC-16-CCITT (0x1021, init 0xFFFF) Framing and
        //              Go-Back-N Link-Layer Replay Buffer (REPLAY_DEPTH=8).
        // =============================================================================
        `include "mlu_pkg.sv"
        
        module mlu_c2c_serdes_pcs #(
          parameter int unsigned REPLAY_DEPTH = 8
        ) (
 004540   input  logic         clk,
%000004   input  logic         rst_n,
        
          // Upstream NoC TX Interface
~000705   input  logic         tx_valid_i,
~000041   output logic         tx_ready_o,
~001907   input  logic [127:0] tx_flit_i,
        
          // High-Speed C2C SerDes TX Link
~000705   output logic         link_tx_valid_o,
~001931   output logic [127:0] link_tx_flit_o,
        
          // High-Speed C2C SerDes RX Link & Fault Injection
~000705   input  logic         link_rx_valid_i,
~001931   input  logic [127:0] link_rx_flit_i,
~000048   input  logic         err_inject_crc_i,
        
          // Downstream NoC RX Interface
~000739   output logic         rx_valid_o,
~001994   output logic [127:0] rx_flit_o,
        
          // Link-Layer ACK / NACK Handshake Outputs
~000739   output logic         ack_valid_o,
~000945   output logic [4:0]   ack_seq_o,
~000040   output logic         nack_valid_o,
~000945   output logic [4:0]   nack_seq_o,
        
          // Go-Back-N Replay Trigger Interface (from Remote/Local NACK)
~000040   input  logic         replay_trigger_i,
~000945   input  logic [4:0]   replay_seq_i,
        
          // Link Reliability & RAS Telemetry Counters
~000020   output logic [31:0]  crc_err_cnt_o,
~000020   output logic [31:0]  retransmit_cnt_o
        );
        
          localparam int unsigned BUF_IDX_W = $clog2(REPLAY_DEPTH);
        
          // ---------------------------------------------------------------------------
          // 1. Hardware Parallel CRC-16-CCITT (Poly = 0x1021, Init = 0xFFFF) over 112b
          // ---------------------------------------------------------------------------
 010264   function automatic logic [15:0] calc_crc16_ccitt(input logic [111:0] data_in);
 010264     logic [15:0] crc;
 010264     logic        fb;
 010264     crc = 16'hFFFF;
 1149568     for (int i = 111; i >= 0; i--) begin
 1149568       fb  = data_in[i] ^ crc[15];
 1149568       crc = {crc[14:0], 1'b0} ^ (fb ? 16'h1021 : 16'h0000);
            end
 010264     calc_crc16_ccitt = crc;
          endfunction
        
          // ---------------------------------------------------------------------------
          // 2. TX Sequence State & 8-Entry Go-Back-N Replay Buffer
          // ---------------------------------------------------------------------------
~000945   logic [4:0]             tx_seq_q;
~000040   logic                   replay_active_q;
~000020   logic [4:0]             replay_curr_seq_q;
          logic [127:0]           replay_buf_q [0:REPLAY_DEPTH-1];
        
~000945   mlu_pkg::mlu_noc_flit_t tx_flit_formed;
~000832   logic [15:0]            tx_crc16;
~000945   logic [BUF_IDX_W-1:0]   tx_buf_wr_idx;
~000020   logic [BUF_IDX_W-1:0]   replay_rd_idx;
        
          assign tx_ready_o    = !replay_active_q;
          assign tx_buf_wr_idx = tx_seq_q[BUF_IDX_W-1:0];
          assign replay_rd_idx = replay_curr_seq_q[BUF_IDX_W-1:0];
        
 004556   always_comb begin
 004556     tx_flit_formed              = tx_flit_i;
 004556     tx_flit_formed.pkt_seq      = tx_seq_q;
 004556     tx_crc16                    = calc_crc16_ccitt({tx_flit_formed[127:112], tx_flit_formed[95:0]});
 004556     tx_flit_formed.crc16_or_cmd = tx_crc16;
        
~000160     if (replay_active_q) begin
~000160       link_tx_valid_o = 1'b1;
~000160       link_tx_flit_o  = replay_buf_q[replay_rd_idx];
~002880     end else if (tx_valid_i && tx_ready_o) begin
~002880       link_tx_valid_o = 1'b1;
~002880       link_tx_flit_o  = tx_flit_formed;
 002633     end else begin
 002633       link_tx_valid_o = 1'b0;
 002633       link_tx_flit_o  = '0;
            end
          end
        
          // ---------------------------------------------------------------------------
          // 3. RX Framing, CRC-16-CCITT Verification & Sequence Continuity Check
          // ---------------------------------------------------------------------------
~000945   logic [4:0]             rx_exp_seq_q;
~001931   logic [127:0]           rx_flit_corrupted;
~000944   mlu_pkg::mlu_noc_flit_t rx_flit_s;
~000834   logic [15:0]            rx_calc_crc16;
~000739   logic                   rx_crc_ok;
~000684   logic                   rx_seq_ok;
        
 005708   always_comb begin
            // Optional transient bit-flip error injection on bit 0 of received flit
 005708     rx_flit_corrupted = link_rx_flit_i ^ {127'd0, err_inject_crc_i};
 005708     rx_flit_s         = rx_flit_corrupted;
 005708     rx_calc_crc16     = calc_crc16_ccitt({rx_flit_corrupted[127:112], rx_flit_corrupted[95:0]});
 005708     rx_crc_ok         = (rx_calc_crc16 == rx_flit_s.crc16_or_cmd);
 005708     rx_seq_ok         = (rx_flit_s.pkt_seq == rx_exp_seq_q);
        
 005708     rx_valid_o   = 1'b0;
 005708     rx_flit_o    = '0;
 005708     ack_valid_o  = 1'b0;
 005708     ack_seq_o    = rx_exp_seq_q;
 005708     nack_valid_o = 1'b0;
 005708     nack_seq_o   = rx_exp_seq_q;
        
~003040     if (link_rx_valid_i) begin
~002880       if (rx_crc_ok && rx_seq_ok) begin
~002880         rx_valid_o  = 1'b1;
~002880         rx_flit_o   = rx_flit_s;
~002880         ack_valid_o = 1'b1;
~002880         ack_seq_o   = rx_exp_seq_q;
~000160       end else begin
~000160         nack_valid_o = 1'b1;
~000160         nack_seq_o   = rx_exp_seq_q;
              end
            end
          end
        
          // ---------------------------------------------------------------------------
          // 4. Sequential State: Replay Buffer, Go-Back-N FSM & Telemetry Counters
          // ---------------------------------------------------------------------------
 004540   always_ff @(posedge clk or negedge rst_n) begin
~004524     if (!rst_n) begin
~000016       tx_seq_q          <= 5'd0;
~000016       replay_active_q   <= 1'b0;
~000016       replay_curr_seq_q <= 5'd0;
~000016       rx_exp_seq_q      <= 5'd0;
~000016       crc_err_cnt_o     <= 32'd0;
~000016       retransmit_cnt_o  <= 32'd0;
~000128       for (int i = 0; i < REPLAY_DEPTH; i++) begin
 000128         replay_buf_q[i] <= '0;
              end
 004524     end else begin
              // Normal TX Storage into Circular Replay Buffer
~002635       if (!replay_active_q && tx_valid_i && tx_ready_o) begin
~001889         replay_buf_q[tx_buf_wr_idx] <= tx_flit_formed;
~001889         tx_seq_q                    <= tx_seq_q + 5'd1;
              end
        
              // Go-Back-N Replay State Machine
~000040       if (replay_active_q) begin
~000040         retransmit_cnt_o <= retransmit_cnt_o + 32'd1;
~000040         if ((replay_curr_seq_q + 5'd1) == tx_seq_q) begin
~000040           replay_active_q <= 1'b0;
%000000         end else begin
%000000           replay_curr_seq_q <= replay_curr_seq_q + 5'd1;
                end
~004456       end else if (replay_trigger_i) begin
~000040         replay_active_q   <= 1'b1;
~000040         replay_curr_seq_q <= replay_seq_i;
              end
        
              // RX Expected Sequence & Error Counter Updates
~002601       if (link_rx_valid_i) begin
~001889         if (rx_crc_ok && rx_seq_ok) begin
~001889           rx_exp_seq_q <= rx_exp_seq_q + 5'd1;
~000040         end else begin
~000040           crc_err_cnt_o <= crc_err_cnt_o + 32'd1;
                end
              end
            end
          end
        
        endmodule : mlu_c2c_serdes_pcs
        
