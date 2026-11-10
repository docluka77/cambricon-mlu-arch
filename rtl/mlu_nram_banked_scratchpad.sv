// =============================================================================
// File: rtl/mlu_nram_banked_scratchpad.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Cambricon IPU Core Private NRAM Banked Scratchpad:
//              - 8 Parallel 64-bit SRAM Banks (512-bit/cycle aggregate bandwidth)
//              - XOR Bank-Swizzling to eliminate power-of-2 stride bank conflicts
//              - Multi-Lane Crossbar with Conflict Detection & Stall Counter
//              - On-the-Fly 8x8 2D Matrix Transpose Network (OP_BANG_TRANSPOSE)
//              - Per-Bank (72,64) Hsiao SECDED ECC & Aggregated Fault Telemetry
// =============================================================================
`include "mlu_pkg.sv"

module mlu_nram_banked_scratchpad #(
  parameter int unsigned NUM_BANKS  = 8,
  parameter int unsigned BANK_DEPTH = 128,
  parameter int unsigned DATA_W     = 64,
  parameter int unsigned ECC_W      = 72,
  parameter int unsigned BANK_SEL_W = $clog2(NUM_BANKS),
  parameter int unsigned ROW_ADDR_W = $clog2(BANK_DEPTH),
  parameter int unsigned ADDR_W     = BANK_SEL_W + ROW_ADDR_W
)(
  input  logic                                clk,
  input  logic                                rst_n,

  // Multi-Lane Vector/Tensor Request Interface (8 Lanes x 64-bit)
  input  logic [NUM_BANKS-1:0]                req_valid_i,
  input  logic [NUM_BANKS-1:0]                req_we_i,
  input  logic [NUM_BANKS-1:0][ADDR_W-1:0]    req_addr_i,
  input  logic [NUM_BANKS-1:0][DATA_W-1:0]    req_wdata_i,
  output logic [NUM_BANKS-1:0]                req_grant_o,
  output logic [NUM_BANKS-1:0][DATA_W-1:0]    resp_rdata_o,
  output logic [NUM_BANKS-1:0]                resp_valid_o,

  // Addressing & Transpose Control Modes
  input  logic                                swizzle_en_i,
  input  logic                                transpose_en_i,

  // Bank-Conflict Telemetry
  output logic                                conflict_stall_o,
  output logic [31:0]                         conflict_cnt_o,

  // ECC Fault Injection & Aggregated Error Status
  input  logic [BANK_SEL_W-1:0]               err_inject_bank_i,
  input  logic [ECC_W-1:0]                    err_inject_mask_i,
  output logic                                sec_err_o,
  output logic                                ded_err_o
);

  // ---------------------------------------------------------------------------
  // 1. XOR Bank-Swizzling & Row Address Extraction per Request Lane
  // ---------------------------------------------------------------------------
  logic [NUM_BANKS-1:0][BANK_SEL_W-1:0] lane_raw_bank;
  logic [NUM_BANKS-1:0][ROW_ADDR_W-1:0] lane_row_addr;
  logic [NUM_BANKS-1:0][BANK_SEL_W-1:0] lane_phys_bank;

  always_comb begin
    for (int l = 0; l < NUM_BANKS; l++) begin
      lane_raw_bank[l]  = req_addr_i[l][BANK_SEL_W-1:0];
      lane_row_addr[l]  = req_addr_i[l][ADDR_W-1:BANK_SEL_W];
      lane_phys_bank[l] = swizzle_en_i ?
                          (lane_raw_bank[l] ^ lane_row_addr[l][BANK_SEL_W-1:0]) :
                          lane_raw_bank[l];
    end
  end

  // ---------------------------------------------------------------------------
  // 2. On-the-Fly 8x8 Byte Matrix Transpose Input Network (Write Path)
  // ---------------------------------------------------------------------------
  logic [NUM_BANKS-1:0][DATA_W-1:0] xbar_wdata_in;

  always_comb begin
    for (int r = 0; r < NUM_BANKS; r++) begin
      for (int c = 0; c < 8; c++) begin
        if (transpose_en_i) begin
          xbar_wdata_in[r][c*8 +: 8] = req_wdata_i[c][r*8 +: 8];
        end else begin
          xbar_wdata_in[r][c*8 +: 8] = req_wdata_i[r][c*8 +: 8];
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // 3. Multi-Bank Crossbar Arbitration & Conflict Detection
  // ---------------------------------------------------------------------------
  logic [NUM_BANKS-1:0]                 bank_req_en;
  logic [NUM_BANKS-1:0]                 bank_req_we;
  logic [NUM_BANKS-1:0][ROW_ADDR_W-1:0] bank_req_row;
  logic [NUM_BANKS-1:0][DATA_W-1:0]     bank_req_wdata;
  logic [NUM_BANKS-1:0][BANK_SEL_W-1:0] bank_owner_lane;
  always_comb begin
    bank_req_en     = '0;
    bank_req_we     = '0;
    bank_req_row    = '0;
    bank_req_wdata  = '0;
    bank_owner_lane = '0;
    req_grant_o     = '0;

    for (int l = 0; l < NUM_BANKS; l++) begin
      if (req_valid_i[l]) begin
        if (!bank_req_en[lane_phys_bank[l]]) begin
          bank_req_en[lane_phys_bank[l]]     = 1'b1;
          bank_req_we[lane_phys_bank[l]]     = req_we_i[l];
          bank_req_row[lane_phys_bank[l]]    = lane_row_addr[l];
          bank_req_wdata[lane_phys_bank[l]]  = xbar_wdata_in[l];
          bank_owner_lane[lane_phys_bank[l]] = BANK_SEL_W'(l);
          req_grant_o[l]                     = 1'b1;
        end
      end
    end
  end

  assign conflict_stall_o = |(req_valid_i & ~req_grant_o);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      conflict_cnt_o <= 32'd0;
    end else if (conflict_stall_o) begin
      conflict_cnt_o <= conflict_cnt_o + 32'd1;
    end
  end

  // ---------------------------------------------------------------------------
  // 4. Pipeline Stage Tracking for Read Response Crossbar & Transpose
  // ---------------------------------------------------------------------------
  logic [NUM_BANKS-1:0]                 rd_lane_valid_q;
  logic [NUM_BANKS-1:0][BANK_SEL_W-1:0] rd_lane_bank_q;
  logic                                 rd_transpose_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_lane_valid_q <= '0;
      rd_lane_bank_q  <= '0;
      rd_transpose_q  <= 1'b0;
    end else begin
      rd_transpose_q  <= transpose_en_i;
      for (int l = 0; l < NUM_BANKS; l++) begin
        rd_lane_valid_q[l] <= req_valid_i[l] && !req_we_i[l] && req_grant_o[l];
        rd_lane_bank_q[l]  <= lane_phys_bank[l];
      end
    end
  end

  // ---------------------------------------------------------------------------
  // 5. Instantiate 8 Physical SRAM Macro Banks with SECDED ECC
  // ---------------------------------------------------------------------------
  logic [NUM_BANKS-1:0][DATA_W-1:0] bank_rdata;
  logic [NUM_BANKS-1:0]             bank_rvalid;
  logic [NUM_BANKS-1:0]             bank_sec_err;
  logic [NUM_BANKS-1:0]             bank_ded_err;
  logic [NUM_BANKS-1:0][7:0]        bank_syndrome;
  logic [NUM_BANKS-1:0]             bank_bist_done;
  logic [NUM_BANKS-1:0]             bank_bist_fail;
  logic [NUM_BANKS-1:0][ROW_ADDR_W-1:0] bank_bist_faddr;
  logic [NUM_BANKS-1:0][DATA_W-1:0] bank_spare_data;
  logic [NUM_BANKS-1:0][ROW_ADDR_W-1:0] bank_scrub_addr;
  logic [NUM_BANKS-1:0]             bank_pwr_ready;

  genvar b;
  generate
    for (b = 0; b < NUM_BANKS; b++) begin : gen_nram_banks
      logic [ECC_W-1:0] bank_err_mask;
      assign bank_err_mask = (err_inject_bank_i == BANK_SEL_W'(b)) ? err_inject_mask_i : '0;

      mlu_sram_sp_macro #(
        .DEPTH      (BANK_DEPTH),
        .DATA_W     (DATA_W),
        .ECC_W      (ECC_W),
        .ADDR_W     (ROW_ADDR_W),
        .BIST_DEPTH (16)
      ) u_bank_sram (
        .clk                 (clk),
        .rst_n               (rst_n),
        .req_en_i            (bank_req_en[b]),
        .req_we_i            (bank_req_we[b]),
        .req_addr_i          (bank_req_row[b]),
        .req_wdata_i         (bank_req_wdata[b]),
        .req_wmask_i         ({(DATA_W/8){1'b1}}),
        .rdata_o             (bank_rdata[b]),
        .rvalid_o            (bank_rvalid[b]),
        .err_inject_mask_i   (bank_err_mask),
        .sec_err_o           (bank_sec_err[b]),
        .ded_err_o           (bank_ded_err[b]),
        .syndrome_o          (bank_syndrome[b]),
        .bist_en_i           (1'b0),
        .bist_done_o         (bank_bist_done[b]),
        .bist_fail_o         (bank_bist_fail[b]),
        .bist_fail_addr_o    (bank_bist_faddr[b]),
        .repair_en_i         (1'b0),
        .repair_bad_addr_i   ('0),
        .repair_spare_data_q (bank_spare_data[b]),
        .scrub_en_i          (1'b0),
        .scrub_addr_o        (bank_scrub_addr[b]),
        .slp_i               (1'b0),
        .dslp_i              (1'b0),
        .sd_i                (1'b0),
        .pwr_ready_o         (bank_pwr_ready[b])
      );
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // 6. Read Response Crossbar & 8x8 Matrix Transpose Output Network
  // ---------------------------------------------------------------------------
  logic [NUM_BANKS-1:0][DATA_W-1:0] lane_raw_rdata;

  always_comb begin
    for (int l = 0; l < NUM_BANKS; l++) begin
      lane_raw_rdata[l] = bank_rdata[rd_lane_bank_q[l]];
    end
    for (int r = 0; r < NUM_BANKS; r++) begin
      for (int c = 0; c < 8; c++) begin
        if (rd_transpose_q) begin
          resp_rdata_o[r][c*8 +: 8] = lane_raw_rdata[c][r*8 +: 8];
        end else begin
          resp_rdata_o[r][c*8 +: 8] = lane_raw_rdata[r][c*8 +: 8];
        end
      end
    end
  end

  assign resp_valid_o = rd_lane_valid_q;
  assign sec_err_o    = |(bank_sec_err & bank_rvalid);
  assign ded_err_o    = |(bank_ded_err & bank_rvalid);

  // Tie off unused diagnostic outputs for clean Verilator -Wall lint
  logic unused_diag_ok;
  assign unused_diag_ok = &{1'b0, bank_owner_lane, bank_syndrome, bank_bist_done,
                            bank_bist_fail, bank_bist_faddr, bank_spare_data,
                            bank_scrub_addr, bank_pwr_ready};

endmodule : mlu_nram_banked_scratchpad
