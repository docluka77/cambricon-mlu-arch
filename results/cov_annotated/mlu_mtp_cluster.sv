//      // verilator_coverage annotation
        // =============================================================================
        // File: rtl/mlu_mtp_cluster.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: Stage 7B — Cambricon MTP (Multi-Tensor Processor) Cluster:
        //              - Instantiates 4x mlu_ipu_core (CORE_ID = 0..3)
        //              - Instantiates 1x mlu_mpu_core (Cluster Shared SRAM + Bcast/AllReduce)
        //              - Hardware Union-Task Barrier Controller (OP_SYNC_CLUSTER)
        //              - 4-to-1 HBM2e/HBM3e GDRAM Channel Arbiter & Telemetry Aggregator
        // =============================================================================
        `include "mlu_pkg.sv"
        
        module mlu_mtp_cluster #(
          parameter logic [3:0]  CLUSTER_ID = 4'd0,
          parameter int unsigned NUM_IPUS   = 4
        ) (
 000603   input  logic                         clk_i,
%000001   input  logic                         rst_ni,
        
          // Per-IPU BANG ISA Instruction Streams (4 IPU Cores)
~000010   input  logic [NUM_IPUS-1:0]          ipu_inst_valid_i,
%000009   output logic [NUM_IPUS-1:0]          ipu_inst_ready_o,
          input  logic [NUM_IPUS-1:0][127:0]   ipu_inst_i,
        
          // MPU Collective / Broadcast Command Stream
%000004   input  logic                         mpu_cmd_valid_i,
%000005   output logic                         mpu_cmd_ready_o,
%000007   input  logic [127:0]                 mpu_cmd_inst_i,
%000004   output logic                         mpu_done_valid_o,
%000002   output logic [7:0]                   mpu_done_tag_o,
        
          // Cluster-Wide Configuration & Union-Task Mask
%000002   input  logic [NUM_IPUS-1:0]          union_task_mask_i,
%000001   input  logic                         wram_ping_pong_sel_i,
%000001   input  logic [63:0]                  mfu_idx_offset_i,
%000001   input  logic [7:0]                   mfu_decomp_bitmap_i,
%000004   input  logic [127:0]                 vfu_cos_sin_lut_i,
        
          // External / Host Direct Access to Cluster Shared SRAM
%000002   input  logic                         ext_sram_valid_i,
%000001   input  logic                         ext_sram_we_i,
~000012   input  logic [10:0]                  ext_sram_addr_i,
%000009   input  logic [63:0]                  ext_sram_wdata_i,
%000002   output logic                         ext_sram_grant_o,
~000012   output logic [63:0]                  ext_sram_rdata_o,
%000003   output logic                         ext_sram_rvalid_o,
        
          // Aggregated HBM2e/HBM3e GDRAM Memory Interface
%000009   output logic                         gdram_req_valid_o,
%000004   output logic                         gdram_req_we_o,
%000006   output logic [31:0]                  gdram_req_addr_o,
%000008   output logic [63:0]                  gdram_req_wdata_o,
%000008   input  logic                         gdram_resp_valid_i,
%000004   input  logic [63:0]                  gdram_resp_rdata_i,
        
          // Cluster MLU-Link NoC Flit TX / RX Interface
%000002   output logic                         noc_tx_valid_o,
%000001   input  logic                         noc_tx_ready_i,
~000015   output logic [127:0]                 noc_tx_flit_o,
%000002   input  logic                         noc_rx_valid_i,
%000001   output logic                         noc_rx_ready_o,
~000014   input  logic [127:0]                 noc_rx_flit_i,
        
          // ECC Fault Injection & Cluster RAS / Performance Telemetry
%000000   input  logic [2:0]                   err_inject_bank_i,
%000001   input  logic [71:0]                  err_inject_mask_i,
%000001   output logic                         cluster_sec_err_o,
%000001   output logic                         cluster_ded_err_o,
 000014   output logic                         cluster_busy_o,
%000001   output logic [31:0]                  union_barrier_cnt_o,
%000003   output logic [31:0]                  cluster_retired_insts_o,
%000006   output logic [31:0]                  cluster_active_mac_cycles_o,
~000248   output logic [31:0]                  cluster_gated_saved_cycles_o,
%000005   output logic [31:0]                  cluster_total_mac_ops_o
        );
        
          // ---------------------------------------------------------------------------
          // 1. Internal Cluster Interconnect Signals
          // ---------------------------------------------------------------------------
%000000   logic [NUM_IPUS-1:0]        ipu_sram_req_valid;
%000000   logic [NUM_IPUS-1:0]        ipu_sram_req_we;
%000004   logic [NUM_IPUS-1:0][10:0]  ipu_sram_req_addr;
%000004   logic [NUM_IPUS-1:0][63:0]  ipu_sram_req_wdata;
%000000   logic [NUM_IPUS-1:0]        ipu_sram_req_grant;
%000000   logic [NUM_IPUS-1:0]        ipu_sram_resp_valid;
~000012   logic [NUM_IPUS-1:0][63:0]  ipu_sram_resp_rdata;
        
%000002   logic [NUM_IPUS-1:0]        mpu_bcast_valid;
%000006   logic [10:0]                mpu_bcast_addr;
~000012   logic [255:0]               mpu_bcast_data;
        
%000008   logic [NUM_IPUS-1:0]        ipu_gdram_req_valid;
%000004   logic [NUM_IPUS-1:0]        ipu_gdram_req_we;
%000004   logic [NUM_IPUS-1:0][31:0]  ipu_gdram_req_addr;
%000004   logic [NUM_IPUS-1:0][63:0]  ipu_gdram_req_wdata;
%000008   logic [NUM_IPUS-1:0]        ipu_gdram_resp_valid;
%000004   logic [NUM_IPUS-1:0][63:0]  ipu_gdram_resp_rdata;
%000003   logic [NUM_IPUS-1:0]        ipu_sync_req;
%000002   logic [NUM_IPUS-1:0]        ipu_sync_ack;
%000001   logic [NUM_IPUS-1:0]        ipu_sec_err;
%000001   logic [NUM_IPUS-1:0]        ipu_ded_err;
~000010   logic [NUM_IPUS-1:0]        ipu_busy;
%000004   logic [NUM_IPUS-1:0][31:0]  ipu_retired_cnt;
%000008   logic [NUM_IPUS-1:0][31:0]  ipu_active_mac_cycles;
~000250   logic [NUM_IPUS-1:0][31:0]  ipu_gated_saved_cycles;
%000006   logic [NUM_IPUS-1:0][31:0]  ipu_total_mac_ops;
%000002   logic [NUM_IPUS-1:0][31:0]  ipu_zero_skip_cnt;
        
%000004   logic                       mpu_busy;
%000000   logic                       mpu_sec_err;
%000000   logic                       mpu_ded_err;
%000006   logic [31:0]                mpu_bcast_beats_cnt;
%000003   logic [31:0]                mpu_allreduce_flit_cnt;
        
          // ---------------------------------------------------------------------------
          // 2. Instantiate 4x Cambricon IPU Tensor Processor Cores (CORE_ID = 0..3)
          // ---------------------------------------------------------------------------
          genvar g;
          generate
            for (g = 0; g < NUM_IPUS; g++) begin : gen_ipu_cores
              mlu_ipu_core #(
                .CORE_ID    (g[1:0]),
                .CLUSTER_ID (CLUSTER_ID)
              ) u_ipu_core (
                .clk_i                (clk_i),
                .rst_ni               (rst_ni),
                .inst_valid_i         (ipu_inst_valid_i[g]),
                .inst_ready_o         (ipu_inst_ready_o[g]),
                .inst_i               (ipu_inst_i[g]),
                .wram_ping_pong_sel_i (wram_ping_pong_sel_i),
                .mfu_idx_offset_i     (mfu_idx_offset_i),
                .mfu_decomp_bitmap_i  (mfu_decomp_bitmap_i),
                .vfu_cos_sin_lut_i    (vfu_cos_sin_lut_i),
                .sram_req_valid_o     (ipu_sram_req_valid[g]),
                .sram_req_we_o        (ipu_sram_req_we[g]),
                .sram_req_addr_o      (ipu_sram_req_addr[g]),
                .sram_req_wdata_o     (ipu_sram_req_wdata[g]),
                .sram_req_grant_i     (ipu_sram_req_grant[g]),
                .sram_resp_valid_i    (ipu_sram_resp_valid[g]),
                .sram_resp_rdata_i    (ipu_sram_resp_rdata[g]),
                .mpu_bcast_valid_i    (mpu_bcast_valid[g]),
                .mpu_bcast_addr_i     (mpu_bcast_addr),
                .mpu_bcast_data_i     (mpu_bcast_data),
                .gdram_req_valid_o    (ipu_gdram_req_valid[g]),
                .gdram_req_we_o       (ipu_gdram_req_we[g]),
                .gdram_req_addr_o     (ipu_gdram_req_addr[g]),
                .gdram_req_wdata_o    (ipu_gdram_req_wdata[g]),
                .gdram_resp_valid_i   (ipu_gdram_resp_valid[g]),
                .gdram_resp_rdata_i   (ipu_gdram_resp_rdata[g]),
                .cluster_sync_req_o   (ipu_sync_req[g]),
                .cluster_sync_ack_i   (ipu_sync_ack[g]),
                .err_inject_bank_i    (err_inject_bank_i),
                .err_inject_mask_i    ((g == 0) ? err_inject_mask_i : 72'd0),
                .core_sec_err_o       (ipu_sec_err[g]),
                .core_ded_err_o       (ipu_ded_err[g]),
                .core_busy_o          (ipu_busy[g]),
                .inst_retired_cnt_o   (ipu_retired_cnt[g]),
                .active_mac_cycles_o  (ipu_active_mac_cycles[g]),
                .gated_saved_cycles_o (ipu_gated_saved_cycles[g]),
                .total_mac_ops_o      (ipu_total_mac_ops[g]),
                .zero_skip_cnt_o      (ipu_zero_skip_cnt[g])
              );
            end
          endgenerate
        
          // ---------------------------------------------------------------------------
          // 3. Instantiate 1x Cambricon MPU Memory Processing Unit Core
          // ---------------------------------------------------------------------------
          mlu_mpu_core #(
            .CLUSTER_ID (CLUSTER_ID),
            .NUM_IPUS   (NUM_IPUS)
          ) u_mpu_core (
            .clk_i                (clk_i),
            .rst_ni               (rst_ni),
            .mpu_cmd_valid_i      (mpu_cmd_valid_i),
            .mpu_cmd_ready_o      (mpu_cmd_ready_o),
            .mpu_cmd_inst_i       (mpu_cmd_inst_i),
            .mpu_busy_o           (mpu_busy),
            .mpu_done_valid_o     (mpu_done_valid_o),
            .mpu_done_tag_o       (mpu_done_tag_o),
            .ipu_req_valid_i      (ipu_sram_req_valid),
            .ipu_req_we_i         (ipu_sram_req_we),
            .ipu_req_addr_i       (ipu_sram_req_addr),
            .ipu_req_wdata_i      (ipu_sram_req_wdata),
            .ipu_req_grant_o      (ipu_sram_req_grant),
            .ipu_resp_rdata_o     (ipu_sram_resp_rdata),
            .ipu_resp_valid_o     (ipu_sram_resp_valid),
            .ext_dma_valid_i      (ext_sram_valid_i),
            .ext_dma_we_i         (ext_sram_we_i),
            .ext_dma_addr_i       (ext_sram_addr_i),
            .ext_dma_wdata_i      (ext_sram_wdata_i),
            .ext_dma_grant_o      (ext_sram_grant_o),
            .ext_dma_rdata_o      (ext_sram_rdata_o),
            .ext_dma_rvalid_o     (ext_sram_rvalid_o),
            .bcast_valid_o        (mpu_bcast_valid),
            .bcast_dst_addr_o     (mpu_bcast_addr),
            .bcast_data_o         (mpu_bcast_data),
            .noc_tx_valid_o       (noc_tx_valid_o),
            .noc_tx_ready_i       (noc_tx_ready_i),
            .noc_tx_flit_o        (noc_tx_flit_o),
            .noc_rx_valid_i       (noc_rx_valid_i),
            .noc_rx_ready_o       (noc_rx_ready_o),
            .noc_rx_flit_i        (noc_rx_flit_i),
            .err_inject_bank_i    (err_inject_bank_i),
            .err_inject_mask_i    (72'd0),
            .mpu_sec_err_o        (mpu_sec_err),
            .mpu_ded_err_o        (mpu_ded_err),
            .bcast_beats_cnt_o    (mpu_bcast_beats_cnt),
            .allreduce_flit_cnt_o (mpu_allreduce_flit_cnt)
          );
          // ---------------------------------------------------------------------------
          // 4. Hardware Union-Task Barrier Controller (OP_SYNC_CLUSTER)
          // ---------------------------------------------------------------------------
%000002   logic [NUM_IPUS-1:0] eff_union_mask;
%000002   logic                all_sync_ready;
%000002   logic                sync_ack_pulse_q;
        
          assign eff_union_mask = (union_task_mask_i == {NUM_IPUS{1'b0}}) ?
                                  {NUM_IPUS{1'b1}} : union_task_mask_i;
          assign all_sync_ready = ((ipu_sync_req & eff_union_mask) == eff_union_mask) &&
                                  (|eff_union_mask) && !sync_ack_pulse_q;
          assign ipu_sync_ack   = {NUM_IPUS{sync_ack_pulse_q}};
        
 000603   always_ff @(posedge clk_i or negedge rst_ni) begin
~000600     if (!rst_ni) begin
%000003       sync_ack_pulse_q    <= 1'b0;
%000003       union_barrier_cnt_o <= 32'd0;
 000600     end else begin
 000600       sync_ack_pulse_q <= all_sync_ready;
~000599       if (all_sync_ready) begin
%000002         union_barrier_cnt_o <= union_barrier_cnt_o + 32'd1;
              end
            end
          end
        
          // ---------------------------------------------------------------------------
          // 5. 4-to-1 HBM2e/HBM3e GDRAM Request Arbiter & Lockstep Response Demux
          // ---------------------------------------------------------------------------
%000008   logic [NUM_IPUS-1:0] gdram_rd_pend_q;
        
 000604   always_comb begin
 000604     gdram_req_valid_o = 1'b0;
 000604     gdram_req_we_o    = 1'b0;
 000604     gdram_req_addr_o  = 32'd0;
 000604     gdram_req_wdata_o = 64'd0;
 002416     for (int i = 0; i < NUM_IPUS; i++) begin
 002404       if (ipu_gdram_req_valid[i] && !gdram_req_valid_o) begin
 000012         gdram_req_valid_o = 1'b1;
 000012         gdram_req_we_o    = ipu_gdram_req_we[i];
 000012         gdram_req_addr_o  = ipu_gdram_req_addr[i];
 000012         gdram_req_wdata_o = ipu_gdram_req_wdata[i];
              end
            end
          end
        
 000603   always_ff @(posedge clk_i or negedge rst_ni) begin
~000600     if (!rst_ni) begin
%000003       gdram_rd_pend_q <= '0;
 000600     end else begin
 002400       for (int i = 0; i < NUM_IPUS; i++) begin
 000028         if (ipu_gdram_req_valid[i] && !ipu_gdram_req_we[i]) begin
 000028           gdram_rd_pend_q[i] <= 1'b1;
 002340         end else if (gdram_resp_valid_i) begin
 000032           gdram_rd_pend_q[i] <= 1'b0;
                end
              end
            end
          end
        
%000001   always_comb begin
%000004     for (int i = 0; i < NUM_IPUS; i++) begin
%000004       ipu_gdram_resp_valid[i] = gdram_resp_valid_i && gdram_rd_pend_q[i];
%000004       ipu_gdram_resp_rdata[i] = gdram_resp_rdata_i;
            end
          end
        
          // ---------------------------------------------------------------------------
          // 6. Cluster-Wide RAS & Performance Telemetry Aggregation
          // ---------------------------------------------------------------------------
          assign cluster_sec_err_o = (|ipu_sec_err) | mpu_sec_err;
          assign cluster_ded_err_o = (|ipu_ded_err) | mpu_ded_err;
          assign cluster_busy_o    = (|ipu_busy) | mpu_busy;
        
          assign cluster_retired_insts_o      = ipu_retired_cnt[0] + ipu_retired_cnt[1] +
                                                ipu_retired_cnt[2] + ipu_retired_cnt[3];
          assign cluster_active_mac_cycles_o  = ipu_active_mac_cycles[0] + ipu_active_mac_cycles[1] +
                                                ipu_active_mac_cycles[2] + ipu_active_mac_cycles[3];
          assign cluster_gated_saved_cycles_o = ipu_gated_saved_cycles[0] + ipu_gated_saved_cycles[1] +
                                                ipu_gated_saved_cycles[2] + ipu_gated_saved_cycles[3];
          assign cluster_total_mac_ops_o      = ipu_total_mac_ops[0] + ipu_total_mac_ops[1] +
                                                ipu_total_mac_ops[2] + ipu_total_mac_ops[3];
        
          wire _unused_ok = &{1'b0, ipu_zero_skip_cnt, mpu_bcast_beats_cnt, mpu_allreduce_flit_cnt};
        
        endmodule : mlu_mtp_cluster
        
