// =============================================================================
// File: formal/mlu_sram_secded_ecc_formal.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Unbounded SAT Formal Verification Wrapper for (72,64) Hsiao
//              Odd-Weight-Column SECDED ECC Encoder & Decoder.
//              Exhaustively proves across all 2^64 data words, all 72 single-bit
//              faults, and all C(72,2)=2,556 double-bit faults:
//              - Property 1: Zero-Error Identity
//              - Property 2: 100% Single-Bit Error Correction (SEC)
//              - Property 3: 100% Double-Bit Error Detection (DED)
// =============================================================================
`include "mlu_pkg.sv"

module mlu_sram_secded_ecc_formal (
  input  logic [63:0] data_i,
  input  logic [1:0]  err_mode_i,
  input  logic [6:0]  err_bit0_i,
  input  logic [6:0]  err_bit1_i,
  output logic [71:0] codeword_o,
  output logic [63:0] data_o,
  output logic [7:0]  syndrome_o,
  output logic        sec_err_o,
  output logic        ded_err_o
);

  // Surjective parameterization over all 0-bit, 1-bit (72), and 2-bit (2,556) masks
  logic [71:0] err_mask;
  logic [71:0] mask_bit0;
  logic [71:0] mask_bit1;

  assign mask_bit0 = (72'd1 << err_bit0_i);
  assign mask_bit1 = (72'd1 << err_bit1_i);

  always_comb begin
    case (err_mode_i)
      2'd0:    err_mask = 72'd0;
      2'd1:    err_mask = mask_bit0;
      2'd2:    err_mask = mask_bit0 | mask_bit1;
      default: err_mask = 72'd0;
    endcase
  end

  mlu_sram_secded_ecc #(
    .DATA_W (64),
    .ECC_W  (72)
  ) u_dut (
    .data_i            (data_i),
    .codeword_o        (codeword_o),
    .codeword_i        (codeword_o),
    .err_inject_mask_i (err_mask),
    .data_o            (data_o),
    .syndrome_o        (syndrome_o),
    .sec_err_o         (sec_err_o),
    .ded_err_o         (ded_err_o)
  );

  // Formal Assumptions & Assertions (Combinational Unbounded SAT)
  always_comb begin
    assume (err_mode_i <= 2'd2);
    assume (err_bit0_i < 7'd72);
    assume (err_bit1_i < 7'd72);
    if (err_mode_i == 2'd2) begin
      assume (err_bit0_i != err_bit1_i);
    end

    // Property 1 (Zero-Error Identity): $countones(err_mask) == 0
    if (err_mode_i == 2'd0) begin
      assert (data_o == data_i);
      assert (!sec_err_o);
      assert (!ded_err_o);
      assert (syndrome_o == 8'h00);
    end

    // Property 2 (100% Single-Bit Correction): $countones(err_mask) == 1
    if (err_mode_i == 2'd1) begin
      assert (data_o == data_i);
      assert (sec_err_o);
      assert (!ded_err_o);
      assert (syndrome_o != 8'h00);
    end

    // Property 3 (100% Double-Bit Detection): $countones(err_mask) == 2
    if (err_mode_i == 2'd2) begin
      assert (ded_err_o);
      assert (!sec_err_o);
      assert (syndrome_o != 8'h00);
    end
  end

endmodule : mlu_sram_secded_ecc_formal
