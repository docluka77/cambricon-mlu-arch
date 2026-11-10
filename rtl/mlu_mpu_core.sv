// =============================================================================
// File: rtl/mlu_mpu_core.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Stage 7B — Cambricon MPU (Memory Processing Unit) Core:
//              - Instantiates mlu_mpu_shared_sram (8-Bank 64b Cluster Shared SRAM
//                with (72,64) Hsiao SECDED ECC)
//              - Executes OP_MPU_BCAST_SRAM (Single-Cycle 256-bit 1-to-4 Multi-Cast
//                Broadcast from Shared SRAM to all 4 IPU Cores)
//              - Executes OP_MPU_ALLREDUCE (In-SRAM Atomic Accumulation across
//                IPU Cores + Outgoing/Incoming MLU-Link Coherent NoC Flit Engine)
// =============================================================================
`include "mlu_pkg.sv"

module mlu_mpu_core #(
  parameter logic [3:0]  CLUSTER_ID = 4'd0,
  parameter int unsigned NUM_IPUS   = 4
) (
  input  logic                         clk_i,
  input  logic                         rst_ni,

  // MPU Command Dispatch & Completion Interface
  input  logic                         mpu_cmd_valid_i,
  output logic                         mpu_cmd_ready_o,
  input  logic [127:0]                 mpu_cmd_inst_i,
  output logic                         mpu_busy_o,
  output logic                         mpu_done_valid_o,
  output logic [7:0]                   mpu_done_tag_o,

  // 4 IPU Core Shared SRAM Access Ports
  input  logic [NUM_IPUS-1:0]          ipu_req_valid_i,
  input  logic [NUM_IPUS-1:0]          ipu_req_we_i,
  input  logic [NUM_IPUS-1:0][10:0]    ipu_req_addr_i,
  input  logic [NUM_IPUS-1:0][63:0]    ipu_req_wdata_i,
  output logic [NUM_IPUS-1:0]          ipu_req_grant_o,
  output logic [NUM_IPUS-1:0][63:0]    ipu_resp_rdata_o,
  output logic [NUM_IPUS-1:0]          ipu_resp_valid_o,

  // External / Global DMA Shared SRAM Access Port
  input  logic                         ext_dma_valid_i,
  input  logic                         ext_dma_we_i,
  input  logic [10:0]                  ext_dma_addr_i,
  input  logic [63:0]                  ext_dma_wdata_i,
  output logic                         ext_dma_grant_o,
  output logic [63:0]                  ext_dma_rdata_o,
  output logic                         ext_dma_rvalid_o,

  // 1-to-4 Multi-Cast Broadcast Outputs to IPU Cores
  output logic [NUM_IPUS-1:0]          bcast_valid_o,
  output logic [10:0]                  bcast_dst_addr_o,
  output logic [255:0]                 bcast_data_o,

  // MLU-Link Cluster NoC Flit TX / RX Interface
  output logic                         noc_tx_valid_o,
  input  logic                         noc_tx_ready_i,
  output logic [127:0]                 noc_tx_flit_o,
  input  logic                         noc_rx_valid_i,
  output logic                         noc_rx_ready_o,
  input  logic [127:0]                 noc_rx_flit_i,

  // ECC Fault Injection & Telemetry
  input  logic [2:0]                   err_inject_bank_i,
  input  logic [71:0]                  err_inject_mask_i,
  output logic                         mpu_sec_err_o,
  output logic                         mpu_ded_err_o,
  output logic [31:0]                  bcast_beats_cnt_o,
  output logic [31:0]                  allreduce_flit_cnt_o
);

  typedef enum logic [1:0] {
    MPU_IDLE      = 2'b00,
    MPU_BCAST     = 2'b01,
    MPU_ALLREDUCE = 2'b10,
    MPU_DONE      = 2'b11
  } mpu_state_e;

  mpu_state_e state_q;
  logic [7:0] tag_q;
  logic [10:0] src_addr_q;
  logic [10:0] dst_addr_q;
  logic [15:0] beats_rem_q;
  logic [3:0]  target_node_q;
  logic [4:0]  pkt_seq_q;

  // Shared SRAM DMA & Broadcast Wires
  logic        sram_dma_valid;
  logic        sram_dma_we;
  logic [10:0] sram_dma_addr;
  logic [63:0] sram_dma_wdata;
  logic        sram_dma_grant;
  logic [63:0] sram_dma_rdata;
  logic        sram_dma_rvalid;
  logic        sram_bcast_en;
  logic [10:0] sram_bcast_addr;
  logic        sram_atomic_add_en;
  // ---------------------------------------------------------------------------
  // 1. Cluster Shared 8-Bank SECDED ECC SRAM Instance
  // ---------------------------------------------------------------------------
  mlu_mpu_shared_sram #(
    .NUM_IPUS   (NUM_IPUS),
    .NUM_BANKS  (8),
    .BANK_DEPTH (256),
    .DATA_W     (64),
    .ECC_W      (72)
  ) u_mpu_shared_sram (
    .clk               (clk_i),
    .rst_n             (rst_ni),
    .ipu_req_valid_i   (ipu_req_valid_i),
    .ipu_req_we_i      (ipu_req_we_i),
    .ipu_req_addr_i    (ipu_req_addr_i),
    .ipu_req_wdata_i   (ipu_req_wdata_i),
    .ipu_req_grant_o   (ipu_req_grant_o),
    .ipu_resp_rdata_o  (ipu_resp_rdata_o),
    .ipu_resp_valid_o  (ipu_resp_valid_o),
    .dma_req_valid_i   (sram_dma_valid),
    .dma_req_we_i      (sram_dma_we),
    .dma_req_addr_i    (sram_dma_addr),
    .dma_req_wdata_i   (sram_dma_wdata),
    .dma_req_grant_o   (sram_dma_grant),
    .dma_resp_rdata_o  (sram_dma_rdata),
    .dma_resp_valid_o  (sram_dma_rvalid),
    .bcast_en_i        (sram_bcast_en),
    .bcast_addr_i      (sram_bcast_addr),
    .bcast_data_o      (bcast_data_o),
    .bcast_valid_o     (bcast_valid_o),
    .atomic_add_en_i   (sram_atomic_add_en),
    .err_inject_bank_i (err_inject_bank_i),
    .err_inject_mask_i (err_inject_mask_i),
    .sec_err_o         (mpu_sec_err_o),
    .ded_err_o         (mpu_ded_err_o)
  );

  // ---------------------------------------------------------------------------
  // 2. Shared SRAM DMA Multiplexer (NoC RX / AllReduce Read / External DMA)
  // ---------------------------------------------------------------------------
  assign noc_rx_ready_o = 1'b1;
  assign sram_dma_valid = noc_rx_valid_i |
                          (state_q == MPU_ALLREDUCE) |
                          ext_dma_valid_i;
  assign sram_dma_we    = noc_rx_valid_i ? 1'b1 :
                          ((state_q == MPU_ALLREDUCE) ? 1'b0 : ext_dma_we_i);
  assign sram_dma_addr  = noc_rx_valid_i ? noc_rx_flit_i[74:64] :
                          ((state_q == MPU_ALLREDUCE) ? src_addr_q : ext_dma_addr_i);
  assign sram_dma_wdata = noc_rx_valid_i ? noc_rx_flit_i[63:0] : ext_dma_wdata_i;

  assign ext_dma_grant_o  = sram_dma_grant & ~noc_rx_valid_i & (state_q != MPU_ALLREDUCE);
  assign ext_dma_rdata_o  = sram_dma_rdata;
  assign ext_dma_rvalid_o = sram_dma_rvalid & (state_q != MPU_ALLREDUCE);

  assign sram_bcast_en      = (state_q == MPU_BCAST);
  assign sram_bcast_addr    = src_addr_q;
  assign sram_atomic_add_en = (state_q == MPU_ALLREDUCE) ||
                              (noc_rx_valid_i && noc_rx_flit_i[125]);

  // ---------------------------------------------------------------------------
  // 3. MPU Collective Command FSM & Outgoing MLU-Link NoC Flit Generator
  // ---------------------------------------------------------------------------
  mlu_pkg::mlu_inst_t cmd_dec;
  assign cmd_dec          = mpu_cmd_inst_i;
  assign mpu_cmd_ready_o  = (state_q == MPU_IDLE);
  assign mpu_busy_o       = (state_q != MPU_IDLE);
  assign mpu_done_valid_o = (state_q == MPU_DONE);
  assign mpu_done_tag_o   = tag_q;

  mlu_pkg::mlu_noc_flit_t tx_flit_s;
  always_comb begin
    tx_flit_s.flit_type    = mlu_pkg::FLIT_HEAD_TAIL;
    tx_flit_s.vc_id        = 1'b1; // VC1 AllReduce Priority Channel
    tx_flit_s.src_id       = CLUSTER_ID;
    tx_flit_s.dst_id       = target_node_q;
    tx_flit_s.pkt_seq      = pkt_seq_q;
    tx_flit_s.crc16_or_cmd = {10'd0, mlu_pkg::OP_MPU_ALLREDUCE};
    tx_flit_s.addr         = {21'd0, dst_addr_q};
    tx_flit_s.payload      = sram_dma_rdata;
  end

  assign noc_tx_valid_o = (state_q == MPU_ALLREDUCE) && sram_dma_rvalid;
  assign noc_tx_flit_o  = tx_flit_s;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q              <= MPU_IDLE;
      tag_q                <= 8'd0;
      src_addr_q           <= 11'd0;
      dst_addr_q           <= 11'd0;
      bcast_dst_addr_o     <= 11'd0;
      beats_rem_q          <= 16'd0;
      target_node_q        <= 4'd0;
      pkt_seq_q            <= 5'd0;
      bcast_beats_cnt_o    <= 32'd0;
      allreduce_flit_cnt_o <= 32'd0;
    end else begin
      case (state_q)
        MPU_IDLE: begin
          if (mpu_cmd_valid_i) begin
            tag_q         <= cmd_dec.tag_id;
            src_addr_q    <= cmd_dec.src0_addr[13:3];
            dst_addr_q    <= cmd_dec.dst_addr[13:3];
            bcast_dst_addr_o <= cmd_dec.dst_addr[13:3];
            beats_rem_q   <= (cmd_dec.len_or_dims == 16'd0) ? 16'd1 : cmd_dec.len_or_dims;
            target_node_q <= (cmd_dec.src1_or_strd[3:0] == CLUSTER_ID) ?
                             (CLUSTER_ID ^ 4'b1100) : cmd_dec.src1_or_strd[3:0];
            if (cmd_dec.opcode == mlu_pkg::OP_MPU_BCAST_SRAM) begin
              state_q <= MPU_BCAST;
            end else begin
              state_q <= MPU_ALLREDUCE;
            end
          end
        end
        MPU_BCAST: begin
          bcast_beats_cnt_o <= bcast_beats_cnt_o + 32'd1;
          bcast_dst_addr_o  <= dst_addr_q;
          src_addr_q        <= src_addr_q + 11'd1;
          dst_addr_q        <= dst_addr_q + 11'd1;
          if (beats_rem_q <= 16'd1) begin
            state_q <= MPU_DONE;
          end else begin
            beats_rem_q <= beats_rem_q - 16'd1;
          end
        end
        MPU_ALLREDUCE: begin
          if (sram_dma_grant && !noc_rx_valid_i && noc_tx_ready_i) begin
            src_addr_q           <= src_addr_q + 11'd1;
          end
          if (sram_dma_rvalid && noc_tx_ready_i) begin
            allreduce_flit_cnt_o <= allreduce_flit_cnt_o + 32'd1;
            pkt_seq_q            <= pkt_seq_q + 5'd1;
            dst_addr_q           <= dst_addr_q + 11'd1;
            if (beats_rem_q <= 16'd1) begin
              state_q <= MPU_DONE;
            end else begin
              beats_rem_q <= beats_rem_q - 16'd1;
            end
          end
        end
        MPU_DONE: begin
          state_q <= MPU_IDLE;
        end
        default: state_q <= MPU_IDLE;
      endcase
    end
  end

  wire _unused_ok = &{1'b0, cmd_dec, noc_rx_flit_i};

endmodule : mlu_mpu_core
