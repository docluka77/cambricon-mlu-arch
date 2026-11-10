// =============================================================================
// File: rtl/mlu_wram_weight_buffer.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Cambricon IPU Core Private WRAM Weight Scratchpad:
//              - Ping-Pong Double-Buffered 4-Bank Architecture (2 x 4 x 128 x 64b)
//              - Zero-Stall Concurrent Shadow-Buffer DMA Write & Active-Buffer
//                256-bit (4 x 64-bit) Wide Row Broadcast to TFU Fractal MAC Array
//              - Integrated Cambricon-S Sparsity Bitmap & 2:4 Index Metadata SRAM
//              - Per-Bank (72,64) Hsiao SECDED ECC Protection
// =============================================================================
`include "mlu_pkg.sv"

module mlu_wram_weight_buffer #(
  parameter int unsigned NUM_BANKS  = 4,
  parameter int unsigned BANK_DEPTH = 128,
  parameter int unsigned DATA_W     = 64,
  parameter int unsigned ECC_W      = 72,
  parameter int unsigned META_W     = 32,
  parameter int unsigned BANK_SEL_W = $clog2(NUM_BANKS),
  parameter int unsigned ROW_ADDR_W = $clog2(BANK_DEPTH),
  parameter int unsigned DMA_ADDR_W = BANK_SEL_W + ROW_ADDR_W
)(
  input  logic                          clk,
  input  logic                          rst_n,

  // Ping-Pong Buffer Select (0: Buf0=Active/TFU, Buf1=Shadow/DMA;
  //                          1: Buf1=Active/TFU, Buf0=Shadow/DMA)
  input  logic                          ping_pong_sel_i,

  // MFU Asynchronous DMA Shadow-Buffer Write Port
  // Address Format: dma_addr_i = {bank_sel[BANK_SEL_W-1:0], row_addr[ROW_ADDR_W-1:0]}
  input  logic                          dma_we_i,
  input  logic [DMA_ADDR_W-1:0]         dma_addr_i,
  input  logic [DATA_W-1:0]             dma_wdata_i,

  // Cambricon-S Sparsity Bitmap & 2:4 Index Metadata Shadow Write Port
  input  logic                          sparse_meta_we_i,
  input  logic [META_W-1:0]             sparse_meta_wdata_i,

  // TFU Active-Buffer Wide Broadcast Read Port (4 x 64b = 256b/cycle)
  input  logic                          tfu_rd_en_i,
  input  logic [ROW_ADDR_W-1:0]         tfu_rd_addr_i,
  output logic [NUM_BANKS*DATA_W-1:0]   tfu_weight_vec_o,
  output logic [META_W-1:0]             tfu_sparse_meta_o,
  output logic                          tfu_weight_valid_o,

  // ECC Fault Injection & Error Status
  input  logic [BANK_SEL_W-1:0]         err_inject_bank_i,
  input  logic [ECC_W-1:0]              err_inject_mask_i,
  output logic                          sec_err_o,
  output logic                          ded_err_o
);

  // ---------------------------------------------------------------------------
  // 1. Address Decomposition & Ping-Pong Buffer Routing
  // ---------------------------------------------------------------------------
  logic [BANK_SEL_W-1:0] dma_bank_sel;
  logic [ROW_ADDR_W-1:0] dma_row_addr;
  logic                  active_buf_sel;
  logic                  shadow_buf_sel;

  assign dma_bank_sel   = dma_addr_i[DMA_ADDR_W-1:ROW_ADDR_W];
  assign dma_row_addr   = dma_addr_i[ROW_ADDR_W-1:0];
  assign active_buf_sel = ping_pong_sel_i;
  assign shadow_buf_sel = ~ping_pong_sel_i;

  // ---------------------------------------------------------------------------
  // 2. Cambricon-S Sparsity Bitmap & 2:4 Index Table Memory (Double-Buffered)
  // ---------------------------------------------------------------------------
`ifdef SYNTH_SRAM_DEPTH
  localparam int unsigned PHYS_META_DEPTH  = `SYNTH_SRAM_DEPTH;
  localparam int unsigned PHYS_META_ADDR_W = $clog2(PHYS_META_DEPTH);
`else
  localparam int unsigned PHYS_META_DEPTH  = BANK_DEPTH;
  localparam int unsigned PHYS_META_ADDR_W = ROW_ADDR_W;
`endif
  logic [META_W-1:0] sparse_meta_mem0 [0:PHYS_META_DEPTH-1];
  logic [META_W-1:0] sparse_meta_mem1 [0:PHYS_META_DEPTH-1];
  logic [META_W-1:0] sparse_meta_rd0_q;
  logic [META_W-1:0] sparse_meta_rd1_q;
  logic              tfu_weight_valid_q;
  logic              active_buf_sel_q;

  always_ff @(posedge clk) begin
    if (sparse_meta_we_i && !shadow_buf_sel) begin
      sparse_meta_mem0[dma_row_addr[PHYS_META_ADDR_W-1:0]] <= sparse_meta_wdata_i;
    end
    if (sparse_meta_we_i && shadow_buf_sel) begin
      sparse_meta_mem1[dma_row_addr[PHYS_META_ADDR_W-1:0]] <= sparse_meta_wdata_i;
    end
    if (tfu_rd_en_i) begin
      sparse_meta_rd0_q <= sparse_meta_mem0[tfu_rd_addr_i[PHYS_META_ADDR_W-1:0]];
      sparse_meta_rd1_q <= sparse_meta_mem1[tfu_rd_addr_i[PHYS_META_ADDR_W-1:0]];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tfu_weight_valid_q <= 1'b0;
      active_buf_sel_q   <= 1'b0;
    end else begin
      tfu_weight_valid_q <= tfu_rd_en_i;
      active_buf_sel_q   <= active_buf_sel;
    end
  end

  assign tfu_sparse_meta_o  = active_buf_sel_q ? sparse_meta_rd1_q : sparse_meta_rd0_q;
  assign tfu_weight_valid_o = tfu_weight_valid_q;
  // ---------------------------------------------------------------------------
  // 3. Double-Buffered 2 x 4 Physical SRAM Banks with (72,64) SECDED ECC
  // ---------------------------------------------------------------------------
  logic [1:0][NUM_BANKS-1:0][DATA_W-1:0]     buf_bank_rdata;
  logic [1:0][NUM_BANKS-1:0]                 buf_bank_rvalid;
  logic [1:0][NUM_BANKS-1:0]                 buf_bank_sec_err;
  logic [1:0][NUM_BANKS-1:0]                 buf_bank_ded_err;
  logic [1:0][NUM_BANKS-1:0][7:0]            buf_bank_syndrome;
  logic [1:0][NUM_BANKS-1:0]                 buf_bank_bist_done;
  logic [1:0][NUM_BANKS-1:0]                 buf_bank_bist_fail;
  logic [1:0][NUM_BANKS-1:0][ROW_ADDR_W-1:0] buf_bank_bist_faddr;
  logic [1:0][NUM_BANKS-1:0][DATA_W-1:0]     buf_bank_spare_data;
  logic [1:0][NUM_BANKS-1:0][ROW_ADDR_W-1:0] buf_bank_scrub_addr;
  logic [1:0][NUM_BANKS-1:0]                 buf_bank_pwr_ready;

  genvar pp, b;
  generate
    for (pp = 0; pp < 2; pp++) begin : gen_ping_pong_buf
      for (b = 0; b < NUM_BANKS; b++) begin : gen_wram_bank
        logic                  is_active_buf;
        logic                  bank_en;
        logic                  bank_we;
        logic [ROW_ADDR_W-1:0] bank_addr;
        logic [ECC_W-1:0]      bank_err_mask;

        assign is_active_buf = (active_buf_sel == 1'(pp));
        assign bank_we       = (!is_active_buf) && dma_we_i && (dma_bank_sel == BANK_SEL_W'(b));
        assign bank_en       = is_active_buf ? tfu_rd_en_i : bank_we;
        assign bank_addr     = is_active_buf ? tfu_rd_addr_i : dma_row_addr;
        assign bank_err_mask = (is_active_buf && (err_inject_bank_i == BANK_SEL_W'(b))) ?
                               err_inject_mask_i : '0;

        mlu_sram_sp_macro #(
          .DEPTH      (BANK_DEPTH),
          .DATA_W     (DATA_W),
          .ECC_W      (ECC_W),
          .ADDR_W     (ROW_ADDR_W),
          .BIST_DEPTH (16)
        ) u_wram_macro (
          .clk                 (clk),
          .rst_n               (rst_n),
          .req_en_i            (bank_en),
          .req_we_i            (bank_we),
          .req_addr_i          (bank_addr),
          .req_wdata_i         (dma_wdata_i),
          .req_wmask_i         ({(DATA_W/8){1'b1}}),
          .rdata_o             (buf_bank_rdata[pp][b]),
          .rvalid_o            (buf_bank_rvalid[pp][b]),
          .err_inject_mask_i   (bank_err_mask),
          .sec_err_o           (buf_bank_sec_err[pp][b]),
          .ded_err_o           (buf_bank_ded_err[pp][b]),
          .syndrome_o          (buf_bank_syndrome[pp][b]),
          .bist_en_i           (1'b0),
          .bist_done_o         (buf_bank_bist_done[pp][b]),
          .bist_fail_o         (buf_bank_bist_fail[pp][b]),
          .bist_fail_addr_o    (buf_bank_bist_faddr[pp][b]),
          .repair_en_i         (1'b0),
          .repair_bad_addr_i   ('0),
          .repair_spare_data_q (buf_bank_spare_data[pp][b]),
          .scrub_en_i          (1'b0),
          .scrub_addr_o        (buf_bank_scrub_addr[pp][b]),
          .slp_i               (1'b0),
          .dslp_i              (1'b0),
          .sd_i                (1'b0),
          .pwr_ready_o         (buf_bank_pwr_ready[pp][b])
        );
      end
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // 4. Active-Buffer 256-Bit (4 x 64-Bit) Broadcast Output & ECC Aggregation
  // ---------------------------------------------------------------------------
  always_comb begin
    for (int k = 0; k < NUM_BANKS; k++) begin
      tfu_weight_vec_o[k*DATA_W +: DATA_W] = buf_bank_rdata[active_buf_sel_q][k];
    end
  end

  assign sec_err_o = |(buf_bank_sec_err[active_buf_sel_q] & buf_bank_rvalid[active_buf_sel_q]);
  assign ded_err_o = |(buf_bank_ded_err[active_buf_sel_q] & buf_bank_rvalid[active_buf_sel_q]);

  logic unused_wram_diag;
  assign unused_wram_diag = &{1'b0, buf_bank_syndrome, buf_bank_bist_done,
                              buf_bank_bist_fail, buf_bank_bist_faddr,
                              buf_bank_spare_data, buf_bank_scrub_addr,
                              buf_bank_pwr_ready};

endmodule : mlu_wram_weight_buffer
