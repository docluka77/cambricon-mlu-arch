//      // verilator_coverage annotation
        // =============================================================================
        // File: rtl/mlu_4chip_oam_node.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: Stage 18 — Multi-Chiplet 4-Way MLU-Link OAM Server Node
        //              integrating 4 Cambricon Siyuan 590/690 Node Slices connected in a
        //              Bidirectional MLU-Link Ring + Diagonal Butterfly Topology (512 GB/s):
        //              - 4x mlu_link_noc_router (ROUTER_ID = 0, 1, 2, 3)
        //              - 4x mlu_c2c_serdes_pcs (CRC-16-CCITT & Go-Back-N Link Replay)
        //              - Hardware Collective Ring AllReduce (3-hop pipelined) &
        //                Butterfly AllReduce (2-hop distance-halving/doubling) Engine.
        // =============================================================================
        `include "mlu_pkg.sv"
        
        module mlu_4chip_oam_node #(
          parameter int unsigned NUM_CHIPS        = 4,
          parameter int unsigned PCS_REPLAY_DEPTH = 8
        ) (
 001135   input  logic                         clk_i,
%000001   input  logic                         rst_ni,
        
          // ---------------------------------------------------------------------------
          // 1. Hardware Collective Ring / Butterfly AllReduce Interface
          //    allreduce_mode_i: 1'b0 = 3-Hop Ring AllReduce (0->1->2->3->0)
          //                      1'b1 = 2-Hop Butterfly AllReduce ((0<->1,2<->3) then (0<->2,1<->3))
          // ---------------------------------------------------------------------------
 000160   input  logic                         allreduce_start_i,
 000080   input  logic                         allreduce_mode_i,
 000051   input  logic [NUM_CHIPS-1:0][63:0]   local_grad_i,
 000160   output logic [NUM_CHIPS-1:0]         allreduce_done_o,
 000049   output logic [NUM_CHIPS-1:0][63:0]   final_allreduce_sum_o,
 000160   output logic                         allreduce_busy_o,
~000080   output logic [2:0]                   allreduce_hops_taken_o,
        
          // ---------------------------------------------------------------------------
          // 2. Per-Chip Local MLU-Link NoC Flit Injection & Ejection Ports
          // ---------------------------------------------------------------------------
 000025   input  logic [NUM_CHIPS-1:0]         chip_tx_valid_i,
%000001   output logic [NUM_CHIPS-1:0]         chip_tx_ready_o,
          input  logic [NUM_CHIPS-1:0][127:0]  chip_tx_flit_i,
        
 000028   output logic [NUM_CHIPS-1:0]         chip_rx_valid_o,
%000001   input  logic [NUM_CHIPS-1:0]         chip_rx_ready_i,
          output logic [NUM_CHIPS-1:0][127:0]  chip_rx_flit_o,
        
          // ---------------------------------------------------------------------------
          // 3. Inter-Chip C2C SerDes Link Fault Injection & Handshake Telemetry
          // ---------------------------------------------------------------------------
 000012   input  logic [NUM_CHIPS-1:0]         link_err_inject_i,
 000193   output logic [NUM_CHIPS-1:0]         link_ack_valid_o,
%000009   output logic [NUM_CHIPS-1:0]         link_nack_valid_o,
        
          // ---------------------------------------------------------------------------
          // 4. Node-Wide Aggregated Performance & RAS Telemetry Counters
          // ---------------------------------------------------------------------------
~000092   output logic [31:0]                  total_routed_flits_o,
~000017   output logic [31:0]                  total_crc_errs_o,
~000017   output logic [31:0]                  total_retransmits_o,
~000080   output logic [31:0]                  collective_completed_cnt_o
        );
        
          localparam logic [31:0] AR_MAGIC_ADDR = 32'hA11E_D0CE;
        
          // ---------------------------------------------------------------------------
          // Internal Per-Chip Router & C2C SerDes Interconnect Signals
          // ---------------------------------------------------------------------------
~000025   logic [NUM_CHIPS-1:0][4:0]        rtr_in_valid;
%000001   logic [NUM_CHIPS-1:0][4:0]        rtr_in_ready;
          logic [NUM_CHIPS-1:0][4:0][127:0] rtr_in_flit;
        
~000028   logic [NUM_CHIPS-1:0][4:0]        rtr_out_valid;
~000010   logic [NUM_CHIPS-1:0][4:0]        rtr_out_ready;
          logic [NUM_CHIPS-1:0][4:0][127:0] rtr_out_flit;
        
~000026   logic [NUM_CHIPS-1:0][31:0]       rtr_routed_cnt;
%000000   logic [NUM_CHIPS-1:0][31:0]       rtr_vc1_cnt;
        
 000184   logic [NUM_CHIPS-1:0]             pcs_tx_valid;
~000010   logic [NUM_CHIPS-1:0]             pcs_tx_ready;
          logic [NUM_CHIPS-1:0][127:0]      pcs_tx_flit;
        
 000184   logic [NUM_CHIPS-1:0]             pcs_link_valid;
          logic [NUM_CHIPS-1:0][127:0]      pcs_link_flit;
        
 000193   logic [NUM_CHIPS-1:0]             pcs_rx_valid;
          logic [NUM_CHIPS-1:0][127:0]      pcs_rx_flit;
        
 000240   logic [NUM_CHIPS-1:0][4:0]        pcs_ack_seq;
 000240   logic [NUM_CHIPS-1:0][4:0]        pcs_nack_seq;
%000005   logic [NUM_CHIPS-1:0][31:0]       pcs_crc_err_cnt;
%000005   logic [NUM_CHIPS-1:0][31:0]       pcs_retransmit_cnt;
          // ---------------------------------------------------------------------------
          // 5. Hardware Collective Ring (3-Hop) & Butterfly (2-Hop) AllReduce Engine
          // ---------------------------------------------------------------------------
 000160   logic                         ar_busy_q;
 000080   logic                         ar_mode_q;
~000160   logic [2:0]                   ar_step_q;
 000156   logic [NUM_CHIPS-1:0][63:0]   ar_acc_q;
 000134   logic [NUM_CHIPS-1:0][63:0]   ar_pipe_q;
 000048   logic                         ar_link_stall;
%000001   logic                         unicast_active_q;
%000001   logic                         unicast_en;
        
          assign unicast_en = unicast_active_q || (|chip_tx_valid_i);
        
 001135   always_ff @(posedge clk_i or negedge rst_ni) begin
%000004     if (!rst_ni) begin
%000004       unicast_active_q <= 1'b0;
 001051     end else if (|chip_tx_valid_i) begin
 000080       unicast_active_q <= 1'b1;
            end
          end
        
          // Stall collective step by 1 cycle if any C2C link has a transient CRC fault
          // or is actively retransmitting from its Go-Back-N replay buffer
          assign ar_link_stall    = (|link_err_inject_i) || (| (~pcs_tx_ready));
          assign allreduce_busy_o = ar_busy_q;
        
 001135   always_ff @(posedge clk_i or negedge rst_ni) begin
~001131     if (!rst_ni) begin
%000004       ar_busy_q                  <= 1'b0;
%000004       ar_mode_q                  <= 1'b0;
%000004       ar_step_q                  <= 3'd0;
%000004       allreduce_done_o           <= '0;
%000004       final_allreduce_sum_o      <= '0;
%000004       allreduce_hops_taken_o     <= 3'd0;
%000004       collective_completed_cnt_o <= 32'd0;
~000016       for (int c = 0; c < NUM_CHIPS; c++) begin
 000016         ar_acc_q[c]  <= 64'd0;
 000016         ar_pipe_q[c] <= 64'd0;
              end
 001131     end else begin
 000160       if (allreduce_start_i && !ar_busy_q) begin
 000160         ar_busy_q        <= 1'b1;
 000160         ar_mode_q        <= allreduce_mode_i;
 000160         ar_step_q        <= 3'd0;
 000160         allreduce_done_o <= '0;
 000640         for (int c = 0; c < NUM_CHIPS; c++) begin
 000640           ar_acc_q[c]  <= local_grad_i[c];
 000640           ar_pipe_q[c] <= local_grad_i[c];
                end
 000571       end else if (ar_busy_q && !ar_link_stall) begin
 000240         if (ar_mode_q == 1'b0) begin
                  // Mode 0: 3-Hop Pipelined Ring AllReduce (0 -> 1 -> 2 -> 3 -> 0)
 000240           ar_pipe_q[0] <= ar_pipe_q[3];
 000240           ar_pipe_q[1] <= ar_pipe_q[0];
 000240           ar_pipe_q[2] <= ar_pipe_q[1];
 000240           ar_pipe_q[3] <= ar_pipe_q[2];
        
 000240           ar_acc_q[0]  <= ar_acc_q[0] + ar_pipe_q[3];
 000240           ar_acc_q[1]  <= ar_acc_q[1] + ar_pipe_q[0];
 000240           ar_acc_q[2]  <= ar_acc_q[2] + ar_pipe_q[1];
 000240           ar_acc_q[3]  <= ar_acc_q[3] + ar_pipe_q[2];
        
 000160           if (ar_step_q == 3'd2) begin
 000080             ar_busy_q                  <= 1'b0;
 000080             allreduce_done_o           <= 4'b1111;
 000080             allreduce_hops_taken_o     <= 3'd3;
 000080             collective_completed_cnt_o <= collective_completed_cnt_o + 32'd1;
 000080             final_allreduce_sum_o[0]   <= ar_acc_q[0] + ar_pipe_q[3];
 000080             final_allreduce_sum_o[1]   <= ar_acc_q[1] + ar_pipe_q[0];
 000080             final_allreduce_sum_o[2]   <= ar_acc_q[2] + ar_pipe_q[1];
 000080             final_allreduce_sum_o[3]   <= ar_acc_q[3] + ar_pipe_q[2];
 000160           end else begin
 000160             ar_step_q <= ar_step_q + 3'd1;
                  end
 000160         end else begin
                  // Mode 1: 2-Hop Butterfly AllReduce (Stage 0: XOR-1, Stage 1: XOR-2)
 000080           if (ar_step_q == 3'd0) begin
 000080             ar_acc_q[0]  <= ar_acc_q[0] + ar_acc_q[1];
 000080             ar_acc_q[1]  <= ar_acc_q[1] + ar_acc_q[0];
 000080             ar_acc_q[2]  <= ar_acc_q[2] + ar_acc_q[3];
 000080             ar_acc_q[3]  <= ar_acc_q[3] + ar_acc_q[2];
 000080             ar_pipe_q[0] <= ar_acc_q[0] + ar_acc_q[1];
 000080             ar_pipe_q[1] <= ar_acc_q[1] + ar_acc_q[0];
 000080             ar_pipe_q[2] <= ar_acc_q[2] + ar_acc_q[3];
 000080             ar_pipe_q[3] <= ar_acc_q[3] + ar_acc_q[2];
 000080             ar_step_q    <= 3'd1;
 000080           end else begin
 000080             ar_acc_q[0]                <= ar_acc_q[0] + ar_acc_q[2];
 000080             ar_acc_q[1]                <= ar_acc_q[1] + ar_acc_q[3];
 000080             ar_acc_q[2]                <= ar_acc_q[2] + ar_acc_q[0];
 000080             ar_acc_q[3]                <= ar_acc_q[3] + ar_acc_q[1];
 000080             ar_busy_q                  <= 1'b0;
 000080             allreduce_done_o           <= 4'b1111;
 000080             allreduce_hops_taken_o     <= 3'd2;
 000080             collective_completed_cnt_o <= collective_completed_cnt_o + 32'd1;
 000080             final_allreduce_sum_o[0]   <= ar_acc_q[0] + ar_acc_q[2];
 000080             final_allreduce_sum_o[1]   <= ar_acc_q[1] + ar_acc_q[3];
 000080             final_allreduce_sum_o[2]   <= ar_acc_q[2] + ar_acc_q[0];
 000080             final_allreduce_sum_o[3]   <= ar_acc_q[3] + ar_acc_q[1];
                  end
                end
              end
            end
          end
          // ---------------------------------------------------------------------------
          // 6. Bidirectional MLU-Link Ring + Diagonal Butterfly Topology Interconnect
          // ---------------------------------------------------------------------------
 001139   always_comb begin
 004556     for (int c = 0; c < NUM_CHIPS; c++) begin
              // Port 0: Local Chip Injection & Ejection
 004556       rtr_in_valid[c][0]  = chip_tx_valid_i[c];
 004556       rtr_in_flit[c][0]   = chip_tx_flit_i[c];
 004556       chip_tx_ready_o[c]  = rtr_in_ready[c][0];
        
 004556       chip_rx_valid_o[c]  = rtr_out_valid[c][0];
 004556       chip_rx_flit_o[c]   = rtr_out_flit[c][0];
 004556       rtr_out_ready[c][0] = chip_rx_ready_i[c];
        
              // Unused Input Port 2 tied low
 004556       rtr_in_valid[c][2]  = 1'b0;
 004556       rtr_in_flit[c][2]   = 128'd0;
        
              // Port 3: Diagonal Butterfly Link (Chip 0 <-> Chip 2, Chip 1 <-> Chip 3)
 004556       rtr_in_valid[c][3]  = rtr_out_valid[c ^ 2][3];
 004556       rtr_in_flit[c][3]   = {rtr_out_flit[c ^ 2][3][127:121], 2'b00, rtr_out_flit[c ^ 2][3][118:0]};
 004556       rtr_out_ready[c][3] = 1'b1;
            end
        
            // Counter-Clockwise South Links (3 -> 2 -> 1 -> 0)
 001139     rtr_in_valid[0][1]  = rtr_out_valid[1][2];
 001139     rtr_in_flit[0][1]   = rtr_out_flit[1][2];
 001139     rtr_out_ready[1][2] = 1'b1;
        
 001139     rtr_in_valid[1][1]  = rtr_out_valid[2][2];
 001139     rtr_in_flit[1][1]   = rtr_out_flit[2][2];
 001139     rtr_out_ready[2][2] = 1'b1;
        
 001139     rtr_in_valid[2][1]  = rtr_out_valid[3][2] && (rtr_out_flit[3][2][120:117] != 4'd0);
 001139     rtr_in_flit[2][1]   = rtr_out_flit[3][2];
 001139     rtr_out_ready[3][2] = pcs_tx_ready[3];
        
 001139     rtr_in_valid[3][1]  = 1'b0;
 001139     rtr_in_flit[3][1]   = 128'd0;
 001139     rtr_out_ready[0][2] = 1'b1;
        
            // Clockwise C2C SerDes PCS Ring Links (0 -> 1 -> 2 -> 3 -> 0)
 003417     for (int c = 0; c < 3; c++) begin
 003417       rtr_out_ready[c][1] = pcs_tx_ready[c];
 003417       rtr_out_ready[c][4] = pcs_tx_ready[c];
 000057       if (rtr_out_valid[c][1]) begin
 000057         pcs_tx_valid[c] = 1'b1;
 000057         pcs_tx_flit[c]  = rtr_out_flit[c][1];
%000000       end else if (rtr_out_valid[c][4]) begin
%000000         pcs_tx_valid[c] = 1'b1;
%000000         pcs_tx_flit[c]  = {rtr_out_flit[c][4][127:121], 2'b00, rtr_out_flit[c][4][118:0]};
 001968       end else if (ar_busy_q) begin
 001392         pcs_tx_valid[c] = 1'b1;
 001392         pcs_tx_flit[c]  = {2'b00, 1'b1, 4'(c), 4'((c + 1) & 3), 5'd0, 16'h0039, AR_MAGIC_ADDR, 60'd0, ar_pipe_q[c][3:0]};
 001968       end else begin
 001968         pcs_tx_valid[c] = 1'b0;
 001968         pcs_tx_flit[c]  = 128'd0;
              end
            end
        
 001139     rtr_out_ready[3][1] = 1'b1;
 001139     rtr_out_ready[3][4] = pcs_tx_ready[3];
%000008     if (rtr_out_valid[3][2] && (rtr_out_flit[3][2][120:117] == 4'd0)) begin
%000008       pcs_tx_valid[3] = 1'b1;
%000008       pcs_tx_flit[3]  = rtr_out_flit[3][2];
%000000     end else if (rtr_out_valid[3][4]) begin
%000000       pcs_tx_valid[3] = 1'b1;
%000000       pcs_tx_flit[3]  = {rtr_out_flit[3][4][127:121], 2'b00, rtr_out_flit[3][4][118:0]};
 000667     end else if (ar_busy_q) begin
 000464       pcs_tx_valid[3] = 1'b1;
 000464       pcs_tx_flit[3]  = {2'b00, 1'b1, 4'd3, 4'd0, 5'd0, 16'h0039, AR_MAGIC_ADDR, 60'd0, ar_pipe_q[3][3:0]};
 000667     end else begin
 000667       pcs_tx_valid[3] = 1'b0;
 000667       pcs_tx_flit[3]  = 128'd0;
            end
        
            // Downstream C2C SerDes RX feeds Router Port 4 of Chip (c+1)%4
 004556     for (int c = 0; c < NUM_CHIPS; c++) begin
 004556       rtr_in_valid[(c + 1) & 3][4] = unicast_en && pcs_rx_valid[c] && (pcs_rx_flit[c][95:64] != AR_MAGIC_ADDR);
 004556       rtr_in_flit[(c + 1) & 3][4]  = unicast_en ? pcs_rx_flit[c] : 128'd0;
            end
          end
        
          // ---------------------------------------------------------------------------
          // 7. Per-Chip Router & C2C SerDes PCS Slice Instantiations
          // ---------------------------------------------------------------------------
          genvar g;
          generate
            for (g = 0; g < NUM_CHIPS; g++) begin : gen_oam_chip_slice
              mlu_link_noc_router #(
                .ROUTER_ID (4'(g))
              ) u_router (
                .clk                (clk_i),
                .rst_n              (rst_ni),
                .allreduce_en_i     (1'b1),
                .in_valid_i         (rtr_in_valid[g]),
                .in_ready_o         (rtr_in_ready[g]),
                .in_flit_i          (rtr_in_flit[g]),
                .out_valid_o        (rtr_out_valid[g]),
                .out_ready_i        (rtr_out_ready[g]),
                .out_flit_o         (rtr_out_flit[g]),
                .routed_flit_cnt_o  (rtr_routed_cnt[g]),
                .vc1_priority_cnt_o (rtr_vc1_cnt[g])
              );
        
              mlu_c2c_serdes_pcs #(
                .REPLAY_DEPTH (PCS_REPLAY_DEPTH)
              ) u_c2c_pcs (
                .clk              (clk_i),
                .rst_n            (rst_ni),
                .tx_valid_i       (pcs_tx_valid[g]),
                .tx_ready_o       (pcs_tx_ready[g]),
                .tx_flit_i        (pcs_tx_flit[g]),
                .link_tx_valid_o  (pcs_link_valid[g]),
                .link_tx_flit_o   (pcs_link_flit[g]),
                .link_rx_valid_i  (pcs_link_valid[g]),
                .link_rx_flit_i   (pcs_link_flit[g]),
                .err_inject_crc_i (link_err_inject_i[g]),
                .rx_valid_o       (pcs_rx_valid[g]),
                .rx_flit_o        (pcs_rx_flit[g]),
                .ack_valid_o      (link_ack_valid_o[g]),
                .ack_seq_o        (pcs_ack_seq[g]),
                .nack_valid_o     (link_nack_valid_o[g]),
                .nack_seq_o       (pcs_nack_seq[g]),
                .replay_trigger_i (link_nack_valid_o[g]),
                .replay_seq_i     (pcs_nack_seq[g]),
                .crc_err_cnt_o    (pcs_crc_err_cnt[g]),
                .retransmit_cnt_o (pcs_retransmit_cnt[g])
              );
            end
          endgenerate
        
          assign total_routed_flits_o = rtr_routed_cnt[0] + rtr_routed_cnt[1] +
                                        rtr_routed_cnt[2] + rtr_routed_cnt[3];
          assign total_crc_errs_o     = pcs_crc_err_cnt[0] + pcs_crc_err_cnt[1] +
                                        pcs_crc_err_cnt[2] + pcs_crc_err_cnt[3];
          assign total_retransmits_o  = pcs_retransmit_cnt[0] + pcs_retransmit_cnt[1] +
                                        pcs_retransmit_cnt[2] + pcs_retransmit_cnt[3];
        
          wire _unused_ok = &{1'b0, rtr_in_ready[0][4:1], rtr_in_ready[1][4:1],
                              rtr_in_ready[2][4:1], rtr_in_ready[3][4:1],
                              rtr_out_valid[0][2], rtr_out_flit[0][2],
                              rtr_out_valid[3][1], rtr_out_flit[3][1],
                              rtr_vc1_cnt, pcs_ack_seq};
        
        endmodule : mlu_4chip_oam_node
        
