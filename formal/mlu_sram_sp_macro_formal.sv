// =============================================================================
// File: formal/mlu_sram_sp_macro_formal.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Sequential SAT / BMC Formal Wrapper for mlu_sram_sp_macro
//              (parameterized to DEPTH=8, BIST_DEPTH=4 for formal closure):
//              - Property 1: Spare-row repair remapping invariance & readback
//              - Property 2: Low-power gating safety & BIST FSM legality
// =============================================================================
`include "mlu_pkg.sv"

module mlu_sram_sp_macro_formal (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        req_en_i,
  input  logic        req_we_i,
  input  logic [2:0]  req_addr_i,
  input  logic [63:0] req_wdata_i,
  input  logic        bist_en_i,
  input  logic        repair_en_i,
  input  logic [2:0]  repair_bad_addr_i,
  input  logic        slp_i,
  input  logic        dslp_i,
  input  logic        sd_i,
  output logic [63:0] rdata_o,
  output logic        rvalid_o,
  output logic        pwr_ready_o,
  output logic        bist_done_o,
  output logic        bist_fail_o
);

  logic        sec_err, ded_err;
  logic [7:0]  syndrome;
  logic [2:0]  bist_fail_addr, scrub_addr;
  logic [63:0] repair_spare_data_q;

  logic [63:0] sym_wdata;
  assign sym_wdata = {56'd0, req_wdata_i[7:0]};

  mlu_sram_sp_macro #(
    .DEPTH      (8),
    .DATA_W     (64),
    .ECC_W      (72),
    .ADDR_W     (3),
    .BIST_DEPTH (4)
  ) u_dut (
    .clk                 (clk),
    .rst_n               (rst_n),
    .req_en_i            (req_en_i),
    .req_we_i            (req_we_i),
    .req_addr_i          (req_addr_i),
    .req_wdata_i         (sym_wdata),
    .req_wmask_i         (8'hFF),
    .rdata_o             (rdata_o),
    .rvalid_o            (rvalid_o),
    .err_inject_mask_i   (72'd0),
    .sec_err_o           (sec_err),
    .ded_err_o           (ded_err),
    .syndrome_o          (syndrome),
    .bist_en_i           (bist_en_i),
    .bist_done_o         (bist_done_o),
    .bist_fail_o         (bist_fail_o),
    .bist_fail_addr_o    (bist_fail_addr),
    .repair_en_i         (repair_en_i),
    .repair_bad_addr_i   (repair_bad_addr_i),
    .repair_spare_data_q (repair_spare_data_q),
    .scrub_en_i          (1'b0),
    .scrub_addr_o        (scrub_addr),
    .slp_i               (slp_i),
    .dslp_i              (dslp_i),
    .sd_i                (sd_i),
    .pwr_ready_o         (pwr_ready_o)
  );

  // Port-level reference tracking for spare-row repair & normal array isolation
  logic        spare_written_q;
  logic [63:0] expected_spare_q;
  logic        rd_spare_pending_q;
  logic        rd_normal_pending_q;
  logic        pwr_gated_d1_q;
  logic        was_active_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      spare_written_q     <= 1'b0;
      expected_spare_q    <= 64'd0;
      rd_spare_pending_q  <= 1'b0;
      rd_normal_pending_q <= 1'b0;
      pwr_gated_d1_q      <= 1'b0;
      was_active_q        <= 1'b1;
    end else begin
      rd_spare_pending_q  <= 1'b0;
      rd_normal_pending_q <= 1'b0;
      pwr_gated_d1_q      <= !pwr_ready_o;
      was_active_q        <= pwr_ready_o;

      if (pwr_ready_o && !bist_en_i && req_en_i && (req_addr_i == repair_bad_addr_i)) begin
        if (repair_en_i) begin
          if (req_we_i) begin
            spare_written_q  <= 1'b1;
            expected_spare_q <= sym_wdata;
          end else if (spare_written_q) begin
            rd_spare_pending_q <= 1'b1;
          end
        end else if (!req_we_i) begin
          rd_normal_pending_q <= 1'b1;
        end
      end
    end
  end

  always_comb begin
    assume (rst_n == 1'b1);
    assume (repair_bad_addr_i == 3'd3);
    // Disallow normal-mode writes to bad_addr=3 so normal row[3] stays at 0
    // while allowing arbitrary repaired writes to bad_addr=3 when repair_en_i=1
    if (req_en_i && req_we_i && (req_addr_i == 3'd3)) begin
      assume (repair_en_i == 1'b1);
    end
    if (bist_en_i) begin
      assume (repair_en_i == 1'b0);
    end

    // Property 1: Spare-row repair remapping invariance & normal array isolation
    if (spare_written_q) begin
      assert (repair_spare_data_q == expected_spare_q);
    end
    if (rd_spare_pending_q) begin
      assert (rvalid_o);
      assert (rdata_o == expected_spare_q);
      assert (!sec_err && !ded_err);
    end
    if (rd_normal_pending_q && !bist_en_i) begin
      // Normal array row 3 was never corrupted by writes to repaired spare row 3
      assert (rvalid_o);
      assert (rdata_o == 64'd0);
    end

    // Property 2: Low-power gating safety & BIST legality
    if (slp_i || dslp_i || sd_i) begin
      assert (!pwr_ready_o);
    end
    if (was_active_q) begin
      assert (pwr_ready_o == !(slp_i | dslp_i | sd_i));
    end
    if (pwr_gated_d1_q) begin
      assert (!rvalid_o);
    end
    assert (!bist_fail_o);
    assert (bist_fail_addr < 3'd4);
  end

endmodule : mlu_sram_sp_macro_formal
