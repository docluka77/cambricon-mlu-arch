//      // verilator_coverage annotation
        // =============================================================================
        // File: rtl/mlu_chip_top.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: Stage 7B — Cambricon Siyuan 590 / 690 Full-Chip Top-Level
        //              Processor Hierarchy integrating:
        //              - mlu_mtp_cluster (4x IPU Tensor Cores + 1x MPU Shared SRAM Core
        //                + Hardware Union-Task Sync Barrier Controller)
        //              - mlu_link_noc_router (5-Port Dual-VC Coherent Packetized Router
        //                with In-Router AllReduce Combiner)
        //              - mlu_c2c_serdes_pcs (512 GB/s Chiplet-to-Chiplet High-Speed SerDes
        //                PCS with CRC-16-CCITT & Go-Back-N Link-Layer Replay Buffer)
        // =============================================================================
        `include "mlu_pkg.sv"
        
        module mlu_chip_top #(
          parameter logic [3:0]  CHIP_CLUSTER_ID = 4'd0,
          parameter int unsigned NUM_IPUS        = 4
        ) (
 000603   input  logic                         clk_i,
%000001   input  logic                         rst_ni,
        
          // Per-IPU BANG ISA 128-bit Instruction Dispatch Streams
%000009   input  logic [NUM_IPUS-1:0]          ipu_inst_valid_i,
%000008   output logic [NUM_IPUS-1:0]          ipu_inst_ready_o,
          input  logic [NUM_IPUS-1:0][127:0]   ipu_inst_i,
        
          // MPU Collective / Multi-Cast Broadcast Command Stream
%000004   input  logic                         mpu_cmd_valid_i,
%000005   output logic                         mpu_cmd_ready_o,
%000007   input  logic [127:0]                 mpu_cmd_inst_i,
%000004   output logic                         mpu_done_valid_o,
%000002   output logic [7:0]                   mpu_done_tag_o,
        
          // Cluster & Engine Configuration Controls
%000001   input  logic [NUM_IPUS-1:0]          union_task_mask_i,
%000001   input  logic                         wram_ping_pong_sel_i,
%000001   input  logic [63:0]                  mfu_idx_offset_i,
%000001   input  logic [7:0]                   mfu_decomp_bitmap_i,
%000004   input  logic [127:0]                 vfu_cos_sin_lut_i,
%000001   input  logic                         noc_allreduce_en_i,
        
          // Host / Direct Access to Cluster Shared SRAM
%000002   input  logic                         ext_sram_valid_i,
%000001   input  logic                         ext_sram_we_i,
~000012   input  logic [10:0]                  ext_sram_addr_i,
%000009   input  logic [63:0]                  ext_sram_wdata_i,
%000002   output logic                         ext_sram_grant_o,
~000012   output logic [63:0]                  ext_sram_rdata_o,
%000003   output logic                         ext_sram_rvalid_o,
        
          // HBM2e / HBM3e Global Memory (GDRAM) Channel Interface
%000009   output logic                         gdram_req_valid_o,
%000004   output logic                         gdram_req_we_o,
%000006   output logic [31:0]                  gdram_req_addr_o,
%000008   output logic [63:0]                  gdram_req_wdata_o,
%000008   input  logic                         gdram_resp_valid_i,
%000004   input  logic [63:0]                  gdram_resp_rdata_i,
        
          // MLU-Link 512 GB/s C2C High-Speed SerDes TX / RX Lanes
%000003   output logic                         c2c_tx_valid_o,
%000008   output logic [127:0]                 c2c_tx_flit_o,
%000003   input  logic                         c2c_rx_valid_i,
%000008   input  logic [127:0]                 c2c_rx_flit_i,
%000001   input  logic                         c2c_err_inject_crc_i,
%000002   output logic                         c2c_ack_valid_o,
%000003   output logic [4:0]                   c2c_ack_seq_o,
%000001   output logic                         c2c_nack_valid_o,
%000003   output logic [4:0]                   c2c_nack_seq_o,
%000001   input  logic                         c2c_replay_trigger_i,
%000001   input  logic [4:0]                   c2c_replay_seq_i,
        
          // ECC Fault Injection & Chip-Level RAS Telemetry
%000000   input  logic [2:0]                   err_inject_bank_i,
%000001   input  logic [71:0]                  err_inject_mask_i,
%000001   output logic                         chip_sec_err_o,
%000001   output logic                         chip_ded_err_o,
 000014   output logic                         chip_busy_o,
        
          // Hardware Performance, Power, & Link Telemetry Counters
%000003   output logic [31:0]                  total_retired_insts_o,
%000006   output logic [31:0]                  total_active_mac_cycles_o,
~000248   output logic [31:0]                  total_gated_saved_cycles_o,
%000005   output logic [31:0]                  total_mac_ops_o,
%000001   output logic [31:0]                  union_barrier_cnt_o,
%000005   output logic [31:0]                  routed_flit_cnt_o,
%000001   output logic [31:0]                  c2c_crc_err_cnt_o,
%000001   output logic [31:0]                  c2c_retransmit_cnt_o
        );
          // ---------------------------------------------------------------------------
          // 1. Internal Cluster <-> NoC Router <-> C2C SerDes PCS Interconnect
          // ---------------------------------------------------------------------------
%000002   logic             cluster_noc_tx_valid;
%000001   logic             cluster_noc_tx_ready;
~000015   logic [127:0]     cluster_noc_tx_flit;
%000002   logic             cluster_noc_rx_valid;
%000001   logic             cluster_noc_rx_ready;
%000006   logic [127:0]     cluster_noc_rx_flit;
        
%000002   logic [4:0]       router_in_valid;
%000001   logic [4:0]       router_in_ready;
          logic [4:0][127:0] router_in_flit;
%000002   logic [4:0]       router_out_valid;
%000002   logic [4:0]       router_out_ready;
          logic [4:0][127:0] router_out_flit;
%000005   logic [31:0]      router_vc1_prio_cnt;
        
%000002   logic             pcs_tx_ready;
%000002   logic             pcs_rx_valid;
%000006   logic [127:0]     pcs_rx_flit;
        
          // ---------------------------------------------------------------------------
          // 2. MTP Multi-Tensor Processor Cluster (4x IPU + 1x MPU + Sync Barrier)
          // ---------------------------------------------------------------------------
          mlu_mtp_cluster #(
            .CLUSTER_ID (CHIP_CLUSTER_ID),
            .NUM_IPUS   (NUM_IPUS)
          ) u_mtp_cluster (
            .clk_i                        (clk_i),
            .rst_ni                       (rst_ni),
            .ipu_inst_valid_i             (ipu_inst_valid_i),
            .ipu_inst_ready_o             (ipu_inst_ready_o),
            .ipu_inst_i                   (ipu_inst_i),
            .mpu_cmd_valid_i              (mpu_cmd_valid_i),
            .mpu_cmd_ready_o              (mpu_cmd_ready_o),
            .mpu_cmd_inst_i               (mpu_cmd_inst_i),
            .mpu_done_valid_o             (mpu_done_valid_o),
            .mpu_done_tag_o               (mpu_done_tag_o),
            .union_task_mask_i            (union_task_mask_i),
            .wram_ping_pong_sel_i         (wram_ping_pong_sel_i),
            .mfu_idx_offset_i             (mfu_idx_offset_i),
            .mfu_decomp_bitmap_i          (mfu_decomp_bitmap_i),
            .vfu_cos_sin_lut_i            (vfu_cos_sin_lut_i),
            .ext_sram_valid_i             (ext_sram_valid_i),
            .ext_sram_we_i                (ext_sram_we_i),
            .ext_sram_addr_i              (ext_sram_addr_i),
            .ext_sram_wdata_i             (ext_sram_wdata_i),
            .ext_sram_grant_o             (ext_sram_grant_o),
            .ext_sram_rdata_o             (ext_sram_rdata_o),
            .ext_sram_rvalid_o            (ext_sram_rvalid_o),
            .gdram_req_valid_o            (gdram_req_valid_o),
            .gdram_req_we_o               (gdram_req_we_o),
            .gdram_req_addr_o             (gdram_req_addr_o),
            .gdram_req_wdata_o            (gdram_req_wdata_o),
            .gdram_resp_valid_i           (gdram_resp_valid_i),
            .gdram_resp_rdata_i           (gdram_resp_rdata_i),
            .noc_tx_valid_o               (cluster_noc_tx_valid),
            .noc_tx_ready_i               (cluster_noc_tx_ready),
            .noc_tx_flit_o                (cluster_noc_tx_flit),
            .noc_rx_valid_i               (cluster_noc_rx_valid),
            .noc_rx_ready_o               (cluster_noc_rx_ready),
            .noc_rx_flit_i                (cluster_noc_rx_flit),
            .err_inject_bank_i            (err_inject_bank_i),
            .err_inject_mask_i            (err_inject_mask_i),
            .cluster_sec_err_o            (chip_sec_err_o),
            .cluster_ded_err_o            (chip_ded_err_o),
            .cluster_busy_o               (chip_busy_o),
            .union_barrier_cnt_o          (union_barrier_cnt_o),
            .cluster_retired_insts_o      (total_retired_insts_o),
            .cluster_active_mac_cycles_o  (total_active_mac_cycles_o),
            .cluster_gated_saved_cycles_o (total_gated_saved_cycles_o),
            .cluster_total_mac_ops_o      (total_mac_ops_o)
          );
        
          // ---------------------------------------------------------------------------
          // 3. MLU-Link 5-Port Dual-VC Coherent NoC Router & C2C SerDes PCS
          // ---------------------------------------------------------------------------
          assign router_in_valid[0]   = cluster_noc_tx_valid;
          assign router_in_flit[0]    = cluster_noc_tx_flit;
          assign cluster_noc_tx_ready = router_in_ready[0];
        
          assign cluster_noc_rx_valid = router_out_valid[0];
          assign cluster_noc_rx_flit  = router_out_flit[0];
          assign router_out_ready[0]  = cluster_noc_rx_ready;
        
          // Tie unused mesh ports 1..3 cleanly; Port 4 connects to C2C SerDes PCS
          assign router_in_valid[3:1]  = 3'b000;
          assign router_in_flit[1]     = 128'd0;
          assign router_in_flit[2]     = 128'd0;
          assign router_in_flit[3]     = 128'd0;
          assign router_out_ready[3:1] = 3'b111;
        
          assign router_in_valid[4]   = pcs_rx_valid;
          assign router_in_flit[4]    = pcs_rx_flit;
          assign router_out_ready[4]  = pcs_tx_ready;
        
          mlu_link_noc_router #(
            .ROUTER_ID (CHIP_CLUSTER_ID)
          ) u_link_noc_router (
            .clk                (clk_i),
            .rst_n              (rst_ni),
            .allreduce_en_i     (noc_allreduce_en_i),
            .in_valid_i         (router_in_valid),
            .in_ready_o         (router_in_ready),
            .in_flit_i          (router_in_flit),
            .out_valid_o        (router_out_valid),
            .out_ready_i        (router_out_ready),
            .out_flit_o         (router_out_flit),
            .routed_flit_cnt_o  (routed_flit_cnt_o),
            .vc1_priority_cnt_o (router_vc1_prio_cnt)
          );
        
          mlu_c2c_serdes_pcs #(
            .REPLAY_DEPTH (8)
          ) u_c2c_serdes_pcs (
            .clk              (clk_i),
            .rst_n            (rst_ni),
            .tx_valid_i       (router_out_valid[4]),
            .tx_ready_o       (pcs_tx_ready),
            .tx_flit_i        (router_out_flit[4]),
            .link_tx_valid_o  (c2c_tx_valid_o),
            .link_tx_flit_o   (c2c_tx_flit_o),
            .link_rx_valid_i  (c2c_rx_valid_i),
            .link_rx_flit_i   (c2c_rx_flit_i),
            .err_inject_crc_i (c2c_err_inject_crc_i),
            .rx_valid_o       (pcs_rx_valid),
            .rx_flit_o        (pcs_rx_flit),
            .ack_valid_o      (c2c_ack_valid_o),
            .ack_seq_o        (c2c_ack_seq_o),
            .nack_valid_o     (c2c_nack_valid_o),
            .nack_seq_o       (c2c_nack_seq_o),
            .replay_trigger_i (c2c_replay_trigger_i),
            .replay_seq_i     (c2c_replay_seq_i),
            .crc_err_cnt_o    (c2c_crc_err_cnt_o),
            .retransmit_cnt_o (c2c_retransmit_cnt_o)
          );
        
          wire _unused_ok = &{1'b0, router_in_ready[4:1], router_out_valid[3:1],
                              router_out_flit[1], router_out_flit[2], router_out_flit[3],
                              router_vc1_prio_cnt};
        
        endmodule : mlu_chip_top
        
