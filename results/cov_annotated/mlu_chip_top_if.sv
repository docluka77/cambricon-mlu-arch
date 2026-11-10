//      // verilator_coverage annotation
        // =============================================================================
        // File: uvm_tb/uvm_mlu_chip_top/mlu_chip_top_if.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: SystemVerilog Interface & DUT Wrapper for Accellera UVM 2020.3.1
        //              Suite 8: mlu_chip_top (MTP Cluster + NoC Router + C2C SerDes PCS)
        // =============================================================================
        `ifndef MLU_CHIP_TOP_IF_SV
        `define MLU_CHIP_TOP_IF_SV
        
        `timescale 1ns/1ps
        `include "mlu_pkg.sv"
        
 000603 interface mlu_chip_top_if (input logic clk);
          import mlu_pkg::*;
        
%000001   logic               rst_n                  = 1'b0;
~000600   logic               cycle_valid            = 1'b0;
%000001   int unsigned        cycle_id               = 0;
%000001   int unsigned        subtest_id             = 0;
        
          // 4-IPU BANG ISA Instruction Streams
%000009   logic [3:0]         ipu_inst_valid         = 4'b0000;
%000008   logic [3:0]         ipu_inst_ready;
%000001   logic [3:0][127:0]  ipu_inst               = '0;
        
          // MPU Command Stream
%000004   logic               mpu_cmd_valid          = 1'b0;
%000005   logic               mpu_cmd_ready;
%000007   logic [127:0]       mpu_cmd_inst           = 128'd0;
%000004   logic               mpu_done_valid;
%000002   logic [7:0]         mpu_done_tag;
        
          // Cluster & Router Controls
%000001   logic [3:0]         union_task_mask        = 4'b1111;
%000001   logic               wram_ping_pong_sel     = 1'b0;
%000001   logic [63:0]        mfu_idx_offset         = {16'd24, 16'd16, 16'd8, 16'd0};
%000001   logic [7:0]         mfu_decomp_bitmap      = 8'b1010_0101;
%000004   logic [127:0]       vfu_cos_sin_lut        = {4{16'h0080, 16'h00DF}};
%000001   logic               noc_allreduce_en       = 1'b1;
        
          // External Host Access to Cluster Shared SRAM
%000002   logic               ext_sram_valid         = 1'b0;
%000001   logic               ext_sram_we            = 1'b0;
~000012   logic [10:0]        ext_sram_addr          = 11'd0;
%000009   logic [63:0]        ext_sram_wdata         = 64'd0;
%000002   logic               ext_sram_grant;
~000012   logic [63:0]        ext_sram_rdata;
%000003   logic               ext_sram_rvalid;
        
          // Aggregated HBM2e GDRAM Interface (Monitored)
%000009   logic               gdram_req_valid;
%000004   logic               gdram_req_we;
%000006   logic [31:0]        gdram_req_addr;
%000008   logic [63:0]        gdram_req_wdata;
%000008   logic               gdram_resp_valid;
%000004   logic [63:0]        gdram_resp_rdata;
        
          // MLU-Link C2C High-Speed SerDes TX / RX Lanes & Replay Controls
%000003   logic               c2c_tx_valid;
%000008   logic [127:0]       c2c_tx_flit;
%000003   logic               c2c_rx_valid;
%000008   logic [127:0]       c2c_rx_flit;
%000001   logic               c2c_err_inject_crc     = 1'b0;
%000002   logic               c2c_ack_valid;
%000003   logic [4:0]         c2c_ack_seq;
%000001   logic               c2c_nack_valid;
%000003   logic [4:0]         c2c_nack_seq;
%000001   logic               c2c_replay_trigger     = 1'b0;
%000001   logic [4:0]         c2c_replay_seq         = 5'd0;
        
          // ECC Fault Injection & Chip-Level RAS / Performance Telemetry
%000001   logic [2:0]         err_inject_bank        = 3'd0;
%000001   logic [71:0]        err_inject_mask        = 72'd0;
%000001   logic               chip_sec_err;
%000001   logic               chip_ded_err;
 000014   logic               chip_busy;
%000003   logic [31:0]        total_retired_insts;
%000006   logic [31:0]        total_active_mac_cycles;
~000248   logic [31:0]        total_gated_saved_cycles;
%000005   logic [31:0]        total_mac_ops;
%000001   logic [31:0]        union_barrier_cnt;
%000005   logic [31:0]        routed_flit_cnt;
%000001   logic [31:0]        c2c_crc_err_cnt;
%000001   logic [31:0]        c2c_retransmit_cnt;
        endinterface : mlu_chip_top_if
        
        module mlu_chip_top_dut_wrap (mlu_chip_top_if bus);
          import mlu_pkg::*;
        
          mlu_chip_top #(
            .CHIP_CLUSTER_ID (4'd0),
            .NUM_IPUS        (4)
          ) u_chip_top (
            .clk_i                      (bus.clk),
            .rst_ni                     (bus.rst_n),
            .ipu_inst_valid_i           (bus.ipu_inst_valid),
            .ipu_inst_ready_o           (bus.ipu_inst_ready),
            .ipu_inst_i                 (bus.ipu_inst),
            .mpu_cmd_valid_i            (bus.mpu_cmd_valid),
            .mpu_cmd_ready_o            (bus.mpu_cmd_ready),
            .mpu_cmd_inst_i             (bus.mpu_cmd_inst),
            .mpu_done_valid_o           (bus.mpu_done_valid),
            .mpu_done_tag_o             (bus.mpu_done_tag),
            .union_task_mask_i          (bus.union_task_mask),
            .wram_ping_pong_sel_i       (bus.wram_ping_pong_sel),
            .mfu_idx_offset_i           (bus.mfu_idx_offset),
            .mfu_decomp_bitmap_i        (bus.mfu_decomp_bitmap),
            .vfu_cos_sin_lut_i          (bus.vfu_cos_sin_lut),
            .noc_allreduce_en_i         (bus.noc_allreduce_en),
            .ext_sram_valid_i           (bus.ext_sram_valid),
            .ext_sram_we_i              (bus.ext_sram_we),
            .ext_sram_addr_i            (bus.ext_sram_addr),
            .ext_sram_wdata_i           (bus.ext_sram_wdata),
            .ext_sram_grant_o           (bus.ext_sram_grant),
            .ext_sram_rdata_o           (bus.ext_sram_rdata),
            .ext_sram_rvalid_o          (bus.ext_sram_rvalid),
            .gdram_req_valid_o          (bus.gdram_req_valid),
            .gdram_req_we_o             (bus.gdram_req_we),
            .gdram_req_addr_o           (bus.gdram_req_addr),
            .gdram_req_wdata_o          (bus.gdram_req_wdata),
            .gdram_resp_valid_i         (bus.gdram_resp_valid),
            .gdram_resp_rdata_i         (bus.gdram_resp_rdata),
            .c2c_tx_valid_o             (bus.c2c_tx_valid),
            .c2c_tx_flit_o              (bus.c2c_tx_flit),
            .c2c_rx_valid_i             (bus.c2c_rx_valid),
            .c2c_rx_flit_i              (bus.c2c_rx_flit),
            .c2c_err_inject_crc_i       (bus.c2c_err_inject_crc),
            .c2c_ack_valid_o            (bus.c2c_ack_valid),
            .c2c_ack_seq_o              (bus.c2c_ack_seq),
            .c2c_nack_valid_o           (bus.c2c_nack_valid),
            .c2c_nack_seq_o             (bus.c2c_nack_seq),
            .c2c_replay_trigger_i       (bus.c2c_replay_trigger),
            .c2c_replay_seq_i           (bus.c2c_replay_seq),
            .err_inject_bank_i          (bus.err_inject_bank),
            .err_inject_mask_i          (bus.err_inject_mask),
            .chip_sec_err_o             (bus.chip_sec_err),
            .chip_ded_err_o             (bus.chip_ded_err),
            .chip_busy_o                (bus.chip_busy),
            .total_retired_insts_o      (bus.total_retired_insts),
            .total_active_mac_cycles_o  (bus.total_active_mac_cycles),
            .total_gated_saved_cycles_o (bus.total_gated_saved_cycles),
            .total_mac_ops_o            (bus.total_mac_ops),
            .union_barrier_cnt_o        (bus.union_barrier_cnt),
            .routed_flit_cnt_o          (bus.routed_flit_cnt),
            .c2c_crc_err_cnt_o          (bus.c2c_crc_err_cnt),
            .c2c_retransmit_cnt_o       (bus.c2c_retransmit_cnt)
          );
        
          // Behavioral HBM2e GDRAM Responder (256 x 64-bit words)
          logic [63:0] gdram_mem [0:256-1];
 000603   always_ff @(posedge bus.clk or negedge bus.rst_n) begin
~000600     if (!bus.rst_n) begin
%000003       bus.gdram_resp_valid <= 1'b0;
%000003       bus.gdram_resp_rdata <= 64'd0;
~000768       for (int i = 0; i < 256; i++) begin
 000768         gdram_mem[i] <= {16'(i + 1), 16'(i + 2), 16'(i + 3), 16'(i + 4)};
              end
 000600     end else begin
 000600       bus.gdram_resp_valid <= bus.gdram_req_valid && !bus.gdram_req_we;
 000588       if (bus.gdram_req_valid) begin
%000008         if (bus.gdram_req_we) begin
%000004           gdram_mem[bus.gdram_req_addr[10:3]] <= bus.gdram_req_wdata;
%000008         end else begin
%000008           bus.gdram_resp_rdata <= gdram_mem[bus.gdram_req_addr[10:3]];
                end
              end
            end
          end
        
          // C2C SerDes Peer Responder: rewrites dst_id -> 4'd0, updates CRC-16-CCITT,
          // and delays by 4 cycles so AllReduce flits return after MPU read burst completes
 000604   function automatic logic [15:0] peer_crc16(input logic [111:0] d);
 000604     logic [15:0] crc = 16'hFFFF;
 067648     for (int i = 111; i >= 0; i--) begin
 067648       logic fb = d[i] ^ crc[15];
 067648       crc = {crc[14:0], 1'b0} ^ (fb ? 16'h1021 : 16'h0000);
            end
 000604     return crc;
          endfunction
        
%000008   logic [127:0] c2c_peer_flit;
 000604   always_comb begin
 000604     c2c_peer_flit          = bus.c2c_tx_flit;
 000604     c2c_peer_flit[120:117] = 4'd0; // Route back to Local Cluster 0
 000604     c2c_peer_flit[111:96]  = peer_crc16({c2c_peer_flit[127:112], c2c_peer_flit[95:0]});
          end
        
%000003   logic [3:0]        c2c_pipe_v;
          logic [3:0][127:0] c2c_pipe_f;
 000603   always_ff @(posedge bus.clk or negedge bus.rst_n) begin
~000600     if (!bus.rst_n) begin
%000003       c2c_pipe_v <= '0;
%000003       c2c_pipe_f <= '0;
 000600     end else begin
 000600       c2c_pipe_v[0] <= bus.c2c_tx_valid;
 000600       c2c_pipe_f[0] <= c2c_peer_flit;
 001800       for (int s = 1; s < 4; s++) begin
 001800         c2c_pipe_v[s] <= c2c_pipe_v[s-1];
 001800         c2c_pipe_f[s] <= c2c_pipe_f[s-1];
              end
            end
          end
          assign bus.c2c_rx_valid = c2c_pipe_v[3];
          assign bus.c2c_rx_flit  = c2c_pipe_f[3];
        
        endmodule : mlu_chip_top_dut_wrap
        
        `endif // MLU_CHIP_TOP_IF_SV
        
