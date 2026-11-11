//      // verilator_coverage annotation
        // =============================================================================
        // File: sram_ip/mlu_sram_secded_ecc.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: (72,64) Hsiao Odd-Weight-Column SECDED ECC Encoder & Decoder.
        //              Uses 56 weight-3 + 8 weight-5 columns for 64 data bits and
        //              8 weight-1 columns for check bits, guaranteeing 100% single-error
        //              correction (SEC) and 100% double-error detection (DED).
        // =============================================================================
        `include "mlu_pkg.sv"
        
        module mlu_sram_secded_ecc #(
          parameter int unsigned DATA_W = 64,
          parameter int unsigned ECC_W  = 72
        )(
          // Encode Path (Write to SRAM)
~001022   input  logic [DATA_W-1:0] data_i,
~002322   output logic [ECC_W-1:0]  codeword_o,
        
          // Decode & Error Injection Path (Read from SRAM)
~001554   input  logic [ECC_W-1:0]  codeword_i,
~000073   input  logic [ECC_W-1:0]  err_inject_mask_i,
~000610   output logic [DATA_W-1:0] data_o,
~000338   output logic [7:0]        syndrome_o,
~000399   output logic              sec_err_o,
~000398   output logic              ded_err_o
        );
        
          // ---------------------------------------------------------------------------
          // 1. (72,64) Hsiao Parity-Check Matrix Columns (All 64 Data Columns Odd-Weight)
          //    Indices 0..55: all 56 combinations of weight-3 8-bit vectors
          //    Indices 56..63: 8 cyclic weight-5 8-bit vectors
          // ---------------------------------------------------------------------------
          localparam logic [511:0] HSIAO_H_MAT = {
            // 8 weight-5 columns (indices 63 down to 56)
            8'h7C, 8'h3E, 8'h1F, 8'h8F, 8'hC7, 8'hE3, 8'hF1, 8'hF8,
            // 56 weight-3 columns (indices 55 down to 0)
            8'hE0, 8'hD0, 8'hB0, 8'h70, 8'hC8, 8'hA8, 8'h68, 8'h98,
            8'h58, 8'h38, 8'hC4, 8'hA4, 8'h64, 8'h94, 8'h54, 8'h34,
            8'h8C, 8'h4C, 8'h2C, 8'h1C, 8'hC2, 8'hA2, 8'h62, 8'h92,
            8'h52, 8'h32, 8'h8A, 8'h4A, 8'h2A, 8'h1A, 8'h86, 8'h46,
            8'h26, 8'h16, 8'h0E, 8'hC1, 8'hA1, 8'h61, 8'h91, 8'h51,
            8'h31, 8'h89, 8'h49, 8'h29, 8'h19, 8'h85, 8'h45, 8'h25,
            8'h15, 8'h0D, 8'h83, 8'h43, 8'h23, 8'h13, 8'h0B, 8'h07
          };
        
 000216   function automatic logic [7:0] calc_hsiao_parity(input logic [63:0] d);
 000216     begin
 000216       calc_hsiao_parity = 8'h00;
 013824       for (int b = 0; b < 64; b++) begin
 013824         calc_hsiao_parity = calc_hsiao_parity ^ ({8{d[b]}} & HSIAO_H_MAT[b*8 +: 8]);
              end
            end
          endfunction
        
          // ---------------------------------------------------------------------------
          // 2. Combinational ECC Encoder: Generate 8 Check Bits from 64-Bit Data
          // ---------------------------------------------------------------------------
 001021   logic [7:0] enc_chk_bits;
          assign enc_chk_bits = calc_hsiao_parity(data_i);
          assign codeword_o   = {enc_chk_bits, data_i};
        
          // ---------------------------------------------------------------------------
          // 3. Combinational ECC Decoder: Syndrome Calculation & SECDED Classification
          //    By GF(2) linearity: H*(codeword_i ^ err) = H*codeword_i ^ H*err
          // ---------------------------------------------------------------------------
~001559   logic [71:0] rx_codeword;
~000615   logic [63:0] rx_data;
 000641   logic [7:0]  rx_chk;
%000002   logic [7:0]  cw_syndrome;
~000338   logic [7:0]  err_syndrome;
~000338   logic [7:0]  calc_syndrome;
~000402   logic        syn_nonzero;
~000399   logic        syn_odd_parity;
        
          assign rx_codeword   = codeword_i ^ err_inject_mask_i;
          assign rx_data       = rx_codeword[63:0];
          assign rx_chk        = rx_codeword[71:64];
          assign cw_syndrome   = codeword_i[71:64] ^ calc_hsiao_parity(codeword_i[63:0]);
          assign err_syndrome  = err_inject_mask_i[71:64] ^ calc_hsiao_parity(err_inject_mask_i[63:0]);
          assign calc_syndrome = cw_syndrome ^ err_syndrome;
        
          assign syndrome_o     = calc_syndrome;
          assign syn_nonzero    = |calc_syndrome;
          assign syn_odd_parity = ^calc_syndrome;
        
          // Odd parity syndrome => Single-bit error (correctable)
          // Non-zero even parity syndrome => Double-bit error (uncorrectable)
          assign sec_err_o = syn_nonzero & syn_odd_parity;
          assign ded_err_o = syn_nonzero & (~syn_odd_parity);
        
          // ---------------------------------------------------------------------------
          // 4. Bit-Flipping Data Error Corrector
          // ---------------------------------------------------------------------------
 043616   always_comb begin
 043616     data_o = rx_data;
~043608     if (sec_err_o) begin
~065856       for (int b = 0; b < 64; b++) begin
~064901         if (calc_syndrome == HSIAO_H_MAT[b*8 +: 8]) begin
~000955           data_o[b] = ~rx_data[b];
                end
              end
            end
          end
        
          wire _unused_rx_chk = &{1'b0, rx_chk};
        
        endmodule : mlu_sram_secded_ecc
        
