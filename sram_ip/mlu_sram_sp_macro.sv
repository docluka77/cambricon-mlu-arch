// =============================================================================
// File: sram_ip/mlu_sram_sp_macro.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Industrial Parameterized Single-Port SRAM Macro with:
//              1. Integrated (72,64) Hsiao SECDED ECC Encoder/Decoder
//              2. Hardware 6-Phase March-C- BIST Engine
//              3. Fuse-Programmable Spare-Row Redundancy Remapping
//              4. Autonomous Background ECC Scrubbing Pointer & Writeback
//              5. Multi-Mode Low-Power FSM (Active, Light-Sleep, Deep-Sleep, SD)
// =============================================================================
`include "mlu_pkg.sv"

module mlu_sram_sp_macro #(
  parameter int unsigned DEPTH      = 256,
  parameter int unsigned DATA_W     = 64,
  parameter int unsigned ECC_W      = 72,
  parameter int unsigned ADDR_W     = $clog2(DEPTH),
  parameter int unsigned BIST_DEPTH = 16
)(
  input  logic                clk,
  input  logic                rst_n,

  // Functional SRAM Port
  input  logic                req_en_i,
  input  logic                req_we_i,
  input  logic [ADDR_W-1:0]   req_addr_i,
  input  logic [DATA_W-1:0]   req_wdata_i,
  input  logic [DATA_W/8-1:0] req_wmask_i,
  output logic [DATA_W-1:0]   rdata_o,
  output logic                rvalid_o,

  // ECC Diagnostics & Fault Injection
  input  logic [ECC_W-1:0]    err_inject_mask_i,
  output logic                sec_err_o,
  output logic                ded_err_o,
  output logic [7:0]          syndrome_o,

  // Hardware March-C- BIST Interface
  input  logic                bist_en_i,
  output logic                bist_done_o,
  output logic                bist_fail_o,
  output logic [ADDR_W-1:0]   bist_fail_addr_o,

  // Fuse-Programmable Spare-Row Redundancy Repair Interface
  input  logic                repair_en_i,
  input  logic [ADDR_W-1:0]   repair_bad_addr_i,
  output logic [DATA_W-1:0]   repair_spare_data_q,

  // Autonomous Background ECC Scrubbing Interface
  input  logic                scrub_en_i,
  output logic [ADDR_W-1:0]   scrub_addr_o,

  // Low-Power Control & Status
  input  logic                slp_i,
  input  logic                dslp_i,
  input  logic                sd_i,
  output logic                pwr_ready_o
);

  // ---------------------------------------------------------------------------
  // 1. Low-Power Mode State Machine
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    PWR_ACTIVE      = 3'd0,
    PWR_LIGHT_SLEEP = 3'd1,
    PWR_DEEP_SLEEP  = 3'd2,
    PWR_SHUTDOWN    = 3'd3,
    PWR_WAKEUP      = 3'd4
  } pwr_state_e;

  pwr_state_e pwr_state_q, pwr_state_d;

  always_comb begin
    pwr_state_d = pwr_state_q;
    if (sd_i) begin
      pwr_state_d = PWR_SHUTDOWN;
    end else if (dslp_i) begin
      pwr_state_d = PWR_DEEP_SLEEP;
    end else if (slp_i) begin
      pwr_state_d = PWR_LIGHT_SLEEP;
    end else begin
      case (pwr_state_q)
        PWR_DEEP_SLEEP, PWR_SHUTDOWN: pwr_state_d = PWR_WAKEUP;
        PWR_LIGHT_SLEEP, PWR_WAKEUP:  pwr_state_d = PWR_ACTIVE;
        default:                      pwr_state_d = PWR_ACTIVE;
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) pwr_state_q <= PWR_ACTIVE;
    else        pwr_state_q <= pwr_state_d;
  end

  assign pwr_ready_o = (pwr_state_q == PWR_ACTIVE) && !slp_i && !dslp_i && !sd_i;

  // ---------------------------------------------------------------------------
  // 2. Hardware 6-Phase March-C- BIST FSM
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    BIST_IDLE = 3'd0,
    BIST_M0   = 3'd1, // Ascending Write 0
    BIST_M1   = 3'd2, // Ascending Read 0, Write 1
    BIST_M2   = 3'd3, // Ascending Read 1, Write 0
    BIST_M3   = 3'd4, // Descending Read 0, Write 1
    BIST_M4   = 3'd5, // Descending Read 1, Write 0
    BIST_M5   = 3'd6, // Ascending Read 0
    BIST_DONE = 3'd7
  } bist_state_e;

  localparam logic [ADDR_W-1:0] BIST_LAST_ADDR = ADDR_W'(BIST_DEPTH - 1);

  bist_state_e       bist_state_q;
  logic [ADDR_W-1:0] bist_addr_q;
  logic              bist_sub_q; // 0 = Read cycle, 1 = Check & Write cycle
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bist_state_q     <= BIST_IDLE;
      bist_addr_q      <= '0;
      bist_sub_q       <= 1'b0;
      bist_done_o      <= 1'b0;
      bist_fail_o      <= 1'b0;
      bist_fail_addr_o <= '0;
    end else if (!bist_en_i) begin
      bist_state_q     <= BIST_IDLE;
      bist_addr_q      <= '0;
      bist_sub_q       <= 1'b0;
      bist_done_o      <= 1'b0;
      bist_fail_o      <= 1'b0;
      bist_fail_addr_o <= '0;
    end else if (pwr_ready_o) begin
      case (bist_state_q)
        BIST_IDLE: begin
          bist_state_q <= BIST_M0;
          bist_addr_q  <= '0;
          bist_sub_q   <= 1'b0;
        end
        BIST_M0: begin
          if (bist_addr_q == BIST_LAST_ADDR) begin
            bist_state_q <= BIST_M1;
            bist_addr_q  <= '0;
            bist_sub_q   <= 1'b0;
          end else begin
            bist_addr_q  <= bist_addr_q + 1'b1;
          end
        end
        BIST_M1, BIST_M2, BIST_M5: begin
          if (!bist_sub_q) begin
            bist_sub_q <= 1'b1;
          end else begin
            if ((rdata_o != ((bist_state_q == BIST_M2) ? {DATA_W{1'b1}} : {DATA_W{1'b0}})) || ded_err_o) begin
              bist_fail_o      <= 1'b1;
              bist_fail_addr_o <= bist_addr_q;
            end
            bist_sub_q <= 1'b0;
            if (bist_addr_q == BIST_LAST_ADDR) begin
              if (bist_state_q == BIST_M1) begin
                bist_state_q <= BIST_M2;
                bist_addr_q  <= '0;
              end else if (bist_state_q == BIST_M2) begin
                bist_state_q <= BIST_M3;
                bist_addr_q  <= BIST_LAST_ADDR;
              end else begin
                bist_state_q <= BIST_DONE;
              end
            end else begin
              bist_addr_q <= bist_addr_q + 1'b1;
            end
          end
        end
        BIST_M3, BIST_M4: begin
          if (!bist_sub_q) begin
            bist_sub_q <= 1'b1;
          end else begin
            if ((rdata_o != ((bist_state_q == BIST_M4) ? {DATA_W{1'b1}} : {DATA_W{1'b0}})) || ded_err_o) begin
              bist_fail_o      <= 1'b1;
              bist_fail_addr_o <= bist_addr_q;
            end
            bist_sub_q <= 1'b0;
            if (bist_addr_q == '0) begin
              bist_state_q <= (bist_state_q == BIST_M3) ? BIST_M4 : BIST_M5;
              bist_addr_q  <= (bist_state_q == BIST_M3) ? BIST_LAST_ADDR : '0;
            end else begin
              bist_addr_q  <= bist_addr_q - 1'b1;
            end
          end
        end
        BIST_DONE: begin
          bist_done_o <= 1'b1;
        end
        default: bist_state_q <= BIST_IDLE;
      endcase
    end
  end
  // ---------------------------------------------------------------------------
  // 3. Autonomous Background ECC Scrubbing Pointer
  // ---------------------------------------------------------------------------
  logic [ADDR_W-1:0] scrub_ptr_q;
  logic              scrub_wb_phase_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      scrub_ptr_q      <= '0;
      scrub_wb_phase_q <= 1'b0;
    end else if (pwr_ready_o && scrub_en_i && !bist_en_i && !req_en_i) begin
      if (!scrub_wb_phase_q) begin
        scrub_wb_phase_q <= 1'b1;
      end else begin
        scrub_wb_phase_q <= 1'b0;
        scrub_ptr_q      <= scrub_ptr_q + 1'b1;
      end
    end else begin
      scrub_wb_phase_q <= 1'b0;
    end
  end

  assign scrub_addr_o = scrub_ptr_q;

  // ---------------------------------------------------------------------------
  // 4. Effective SRAM Port Mux (BIST > Functional > Background Scrub)
  // ---------------------------------------------------------------------------
  logic                eff_en;
  logic                eff_we;
  logic [ADDR_W-1:0]   eff_addr;
  logic [DATA_W-1:0]   eff_wdata;
  logic [DATA_W/8-1:0] eff_wmask;

  always_comb begin
    eff_en    = 1'b0;
    eff_we    = 1'b0;
    eff_addr  = req_addr_i;
    eff_wdata = req_wdata_i;
    eff_wmask = req_wmask_i;

    if (pwr_ready_o) begin
      if (bist_en_i) begin
        eff_addr  = bist_addr_q;
        eff_wmask = {(DATA_W/8){1'b1}};
        case (bist_state_q)
          BIST_M0: begin
            eff_en    = 1'b1;
            eff_we    = 1'b1;
            eff_wdata = '0;
          end
          BIST_M1, BIST_M3: begin
            eff_en    = 1'b1;
            eff_we    = bist_sub_q;
            eff_wdata = {DATA_W{1'b1}};
          end
          BIST_M2, BIST_M4: begin
            eff_en    = 1'b1;
            eff_we    = bist_sub_q;
            eff_wdata = '0;
          end
          BIST_M5: begin
            eff_en    = !bist_sub_q;
            eff_we    = 1'b0;
          end
          default: eff_en = 1'b0;
        endcase
      end else if (req_en_i) begin
        eff_en    = 1'b1;
        eff_we    = req_we_i;
        eff_addr  = req_addr_i;
        eff_wdata = req_wdata_i;
        eff_wmask = req_wmask_i;
      end else if (scrub_en_i) begin
        eff_en    = !scrub_wb_phase_q || sec_err_o;
        eff_we    = scrub_wb_phase_q && sec_err_o;
        eff_addr  = scrub_ptr_q;
        eff_wdata = rdata_o;
        eff_wmask = {(DATA_W/8){1'b1}};
      end
    end
  end

  // ---------------------------------------------------------------------------
  // 5. SRAM Core Array + Spare-Row Redundancy + SECDED ECC Codec
  // ---------------------------------------------------------------------------
`ifdef SYNTH_SRAM_DEPTH
  localparam int unsigned PHYS_DEPTH  = `SYNTH_SRAM_DEPTH;
  localparam int unsigned PHYS_ADDR_W = $clog2(PHYS_DEPTH);
`else
  localparam int unsigned PHYS_DEPTH  = DEPTH;
  localparam int unsigned PHYS_ADDR_W = ADDR_W;
`endif
  logic [ECC_W-1:0]  mem_array     [0:PHYS_DEPTH-1];
  logic [ECC_W-1:0]  sram_rd_word_q;
  logic [ECC_W-1:0]  spare_row_q;
  logic              hit_spare_row;
  logic              hit_spare_row_q;
  logic [ECC_W-1:0]  rd_codeword_mux;
  logic [DATA_W-1:0] enc_din;
  logic [ECC_W-1:0]  enc_codeword;

  assign hit_spare_row = repair_en_i && (eff_addr == repair_bad_addr_i);

  always_comb begin
    enc_din = '0;
    for (int byte_idx = 0; byte_idx < DATA_W/8; byte_idx++) begin
      if (eff_wmask[byte_idx]) begin
        enc_din[byte_idx*8 +: 8] = eff_wdata[byte_idx*8 +: 8];
      end else begin
        enc_din[byte_idx*8 +: 8] = rdata_o[byte_idx*8 +: 8];
      end
    end
  end

  assign rd_codeword_mux = hit_spare_row_q ? spare_row_q : sram_rd_word_q;

  mlu_sram_secded_ecc u_ecc_codec (
    .data_i            (enc_din),
    .codeword_o        (enc_codeword),
    .codeword_i        (rd_codeword_mux),
    .err_inject_mask_i (err_inject_mask_i),
    .data_o            (rdata_o),
    .syndrome_o        (syndrome_o),
    .sec_err_o         (sec_err_o),
    .ded_err_o         (ded_err_o)
  );

  always_ff @(posedge clk) begin
    if (eff_en) begin
      if (eff_we && !hit_spare_row) begin
        mem_array[eff_addr[PHYS_ADDR_W-1:0]] <= enc_codeword;
      end
      sram_rd_word_q <= mem_array[eff_addr[PHYS_ADDR_W-1:0]];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      spare_row_q     <= '0;
      hit_spare_row_q <= 1'b0;
      rvalid_o        <= 1'b0;
    end else begin
      rvalid_o <= eff_en && !eff_we && (!bist_en_i) && (req_en_i);
      if (eff_en) begin
        if (eff_we && hit_spare_row) begin
          spare_row_q <= enc_codeword;
        end
        if (!eff_we) begin
          hit_spare_row_q <= hit_spare_row;
        end
      end
    end
  end

  assign repair_spare_data_q = spare_row_q[DATA_W-1:0];

endmodule : mlu_sram_sp_macro
