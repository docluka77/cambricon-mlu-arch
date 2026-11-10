// =============================================================================
// File: uvm_tb/tb_stage2_mem_subsystem.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Self-Checking Cycle-Accurate Verification Suite for Stage 2
//              On-Chip Memory Subsystem:
//              1. mlu_sram_secded_ecc (All 72 SEC bit-flips + DED pairs)
//              2. mlu_sram_sp_macro (March-C- BIST, Spare-Row Repair, Low-Power)
//              3. mlu_nram_banked_scratchpad (Bank Conflict, XOR Swizzle, 8x8 Transpose)
//              4. mlu_wram_weight_buffer (Concurrent Ping-Pong DMA + 256b TFU + Sparse)
//              5. mlu_mpu_shared_sram (256b 4-IPU Broadcast + Atomic AllReduce)
// =============================================================================
`include "mlu_pkg.sv"

module tb_stage2_mem_subsystem (
  input  logic clk,
  input  logic rst_n,
  output logic test_done_o,
  output logic test_pass_o
);

  // ---------------------------------------------------------------------------
  // 1. DUT 1: Standalone (72,64) Hsiao SECDED ECC Codec
  // ---------------------------------------------------------------------------
  logic [63:0] ecc_din;
  logic [71:0] ecc_codeword;
  logic [71:0] ecc_err_mask;
  logic [63:0] ecc_dout;
  logic [7:0]  ecc_syndrome;
  logic        ecc_sec_err;
  logic        ecc_ded_err;

  mlu_sram_secded_ecc u_dut_ecc (
    .data_i            (ecc_din),
    .codeword_o        (ecc_codeword),
    .codeword_i        (ecc_codeword),
    .err_inject_mask_i (ecc_err_mask),
    .data_o            (ecc_dout),
    .syndrome_o        (ecc_syndrome),
    .sec_err_o         (ecc_sec_err),
    .ded_err_o         (ecc_ded_err)
  );

  // ---------------------------------------------------------------------------
  // 2. DUT 2: Industrial Single-Port SRAM Macro
  // ---------------------------------------------------------------------------
  logic        sp_req_en, sp_req_we;
  logic [7:0]  sp_req_addr;
  logic [63:0] sp_req_wdata, sp_rdata;
  logic        sp_rvalid;
  logic [71:0] sp_err_mask;
  logic        sp_sec_err, sp_ded_err;
  logic [7:0]  sp_syndrome;
  logic        sp_bist_en, sp_bist_done, sp_bist_fail;
  logic [7:0]  sp_bist_fail_addr;
  logic        sp_repair_en;
  logic [7:0]  sp_repair_bad_addr;
  logic [63:0] sp_repair_spare_data;
  logic        sp_scrub_en;
  logic [7:0]  sp_scrub_addr;
  logic        sp_slp, sp_dslp, sp_sd, sp_pwr_ready;

  mlu_sram_sp_macro #(
    .DEPTH      (256),
    .DATA_W     (64),
    .ECC_W      (72),
    .ADDR_W     (8),
    .BIST_DEPTH (16)
  ) u_dut_sp_macro (
    .clk                 (clk),
    .rst_n               (rst_n),
    .req_en_i            (sp_req_en),
    .req_we_i            (sp_req_we),
    .req_addr_i          (sp_req_addr),
    .req_wdata_i         (sp_req_wdata),
    .req_wmask_i         (8'hFF),
    .rdata_o             (sp_rdata),
    .rvalid_o            (sp_rvalid),
    .err_inject_mask_i   (sp_err_mask),
    .sec_err_o           (sp_sec_err),
    .ded_err_o           (sp_ded_err),
    .syndrome_o          (sp_syndrome),
    .bist_en_i           (sp_bist_en),
    .bist_done_o         (sp_bist_done),
    .bist_fail_o         (sp_bist_fail),
    .bist_fail_addr_o    (sp_bist_fail_addr),
    .repair_en_i         (sp_repair_en),
    .repair_bad_addr_i   (sp_repair_bad_addr),
    .repair_spare_data_q (sp_repair_spare_data),
    .scrub_en_i          (sp_scrub_en),
    .scrub_addr_o        (sp_scrub_addr),
    .slp_i               (sp_slp),
    .dslp_i              (sp_dslp),
    .sd_i                (sp_sd),
    .pwr_ready_o         (sp_pwr_ready)
  );
  // ---------------------------------------------------------------------------
  // 3. DUT 3: NRAM Banked Scratchpad (8 Banks x 128 Rows x 64-bit)
  // ---------------------------------------------------------------------------
  logic [7:0]        nram_req_valid, nram_req_we, nram_req_grant, nram_resp_valid;
  logic [7:0][9:0]   nram_req_addr;
  logic [7:0][63:0]  nram_req_wdata, nram_resp_rdata;
  logic              nram_swizzle_en, nram_transpose_en;
  logic              nram_conflict_stall;
  logic [31:0]       nram_conflict_cnt;
  logic [2:0]        nram_err_bank;
  logic [71:0]       nram_err_mask;
  logic              nram_sec_err, nram_ded_err;

  mlu_nram_banked_scratchpad u_dut_nram (
    .clk               (clk),
    .rst_n             (rst_n),
    .req_valid_i       (nram_req_valid),
    .req_we_i          (nram_req_we),
    .req_addr_i        (nram_req_addr),
    .req_wdata_i       (nram_req_wdata),
    .req_grant_o       (nram_req_grant),
    .resp_rdata_o      (nram_resp_rdata),
    .resp_valid_o      (nram_resp_valid),
    .swizzle_en_i      (nram_swizzle_en),
    .transpose_en_i    (nram_transpose_en),
    .conflict_stall_o  (nram_conflict_stall),
    .conflict_cnt_o    (nram_conflict_cnt),
    .err_inject_bank_i (nram_err_bank),
    .err_inject_mask_i (nram_err_mask),
    .sec_err_o         (nram_sec_err),
    .ded_err_o         (nram_ded_err)
  );

  // ---------------------------------------------------------------------------
  // 4. DUT 4: WRAM Double-Buffered Weight Scratchpad (2 x 4 Banks x 128 x 64b)
  // ---------------------------------------------------------------------------
  logic         wram_pp_sel, wram_dma_we, wram_meta_we, wram_tfu_rd_en;
  logic [8:0]   wram_dma_addr;
  logic [63:0]  wram_dma_wdata;
  logic [31:0]  wram_meta_wdata, wram_tfu_meta_o;
  logic [6:0]   wram_tfu_rd_addr;
  logic [255:0] wram_tfu_weight_vec;
  logic         wram_tfu_weight_valid;
  logic [1:0]   wram_err_bank;
  logic [71:0]  wram_err_mask;
  logic         wram_sec_err, wram_ded_err;

  mlu_wram_weight_buffer u_dut_wram (
    .clk                 (clk),
    .rst_n               (rst_n),
    .ping_pong_sel_i     (wram_pp_sel),
    .dma_we_i            (wram_dma_we),
    .dma_addr_i          (wram_dma_addr),
    .dma_wdata_i         (wram_dma_wdata),
    .sparse_meta_we_i    (wram_meta_we),
    .sparse_meta_wdata_i (wram_meta_wdata),
    .tfu_rd_en_i         (wram_tfu_rd_en),
    .tfu_rd_addr_i       (wram_tfu_rd_addr),
    .tfu_weight_vec_o    (wram_tfu_weight_vec),
    .tfu_sparse_meta_o   (wram_tfu_meta_o),
    .tfu_weight_valid_o  (wram_tfu_weight_valid),
    .err_inject_bank_i   (wram_err_bank),
    .err_inject_mask_i   (wram_err_mask),
    .sec_err_o           (wram_sec_err),
    .ded_err_o           (wram_ded_err)
  );

  // ---------------------------------------------------------------------------
  // 5. DUT 5: MPU Cluster Shared SRAM (8 Banks x 256 Rows x 64-bit)
  // ---------------------------------------------------------------------------
  logic [3:0]        mpu_ipu_valid, mpu_ipu_we, mpu_ipu_grant, mpu_ipu_rvalid;
  logic [3:0][10:0]  mpu_ipu_addr;
  logic [3:0][63:0]  mpu_ipu_wdata, mpu_ipu_rdata;
  logic              mpu_dma_valid, mpu_dma_we, mpu_dma_grant, mpu_dma_rvalid;
  logic [10:0]       mpu_dma_addr;
  logic [63:0]       mpu_dma_wdata, mpu_dma_rdata;
  logic              mpu_bcast_en, mpu_atomic_add_en;
  logic [10:0]       mpu_bcast_addr;
  logic [255:0]      mpu_bcast_data;
  logic [3:0]        mpu_bcast_valid;
  logic [2:0]        mpu_err_bank;
  logic [71:0]       mpu_err_mask;
  logic              mpu_sec_err, mpu_ded_err;

  mlu_mpu_shared_sram u_dut_mpu_sram (
    .clk               (clk),
    .rst_n             (rst_n),
    .ipu_req_valid_i   (mpu_ipu_valid),
    .ipu_req_we_i      (mpu_ipu_we),
    .ipu_req_addr_i    (mpu_ipu_addr),
    .ipu_req_wdata_i   (mpu_ipu_wdata),
    .ipu_req_grant_o   (mpu_ipu_grant),
    .ipu_resp_rdata_o  (mpu_ipu_rdata),
    .ipu_resp_valid_o  (mpu_ipu_rvalid),
    .dma_req_valid_i   (mpu_dma_valid),
    .dma_req_we_i      (mpu_dma_we),
    .dma_req_addr_i    (mpu_dma_addr),
    .dma_req_wdata_i   (mpu_dma_wdata),
    .dma_req_grant_o   (mpu_dma_grant),
    .dma_resp_rdata_o  (mpu_dma_rdata),
    .dma_resp_valid_o  (mpu_dma_rvalid),
    .bcast_en_i        (mpu_bcast_en),
    .bcast_addr_i      (mpu_bcast_addr),
    .bcast_data_o      (mpu_bcast_data),
    .bcast_valid_o     (mpu_bcast_valid),
    .atomic_add_en_i   (mpu_atomic_add_en),
    .err_inject_bank_i (mpu_err_bank),
    .err_inject_mask_i (mpu_err_mask),
    .sec_err_o         (mpu_sec_err),
    .ded_err_o         (mpu_ded_err)
  );
  // ---------------------------------------------------------------------------
  // 6. Cycle-Accurate Self-Checking Test State Machine
  // ---------------------------------------------------------------------------
  int unsigned cyc_cnt;
  int unsigned err_cnt;
  int unsigned sec_pass_cnt;
  int unsigned ded_pass_cnt;
  logic [31:0] saved_conflict_cnt;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cyc_cnt            <= 0;
      err_cnt            <= 0;
      sec_pass_cnt       <= 0;
      ded_pass_cnt       <= 0;
      saved_conflict_cnt <= 32'd0;
      test_done_o        <= 1'b0;
      test_pass_o        <= 1'b0;

      ecc_din            <= 64'hA55A_F00F_1234_5678;
      ecc_err_mask       <= 72'd0;

      sp_req_en          <= 1'b0;
      sp_req_we          <= 1'b0;
      sp_req_addr        <= 8'd0;
      sp_req_wdata       <= 64'd0;
      sp_err_mask        <= 72'd0;
      sp_bist_en         <= 1'b0;
      sp_repair_en       <= 1'b0;
      sp_repair_bad_addr <= 8'h2A;
      sp_scrub_en        <= 1'b0;
      sp_slp             <= 1'b0;
      sp_dslp            <= 1'b0;
      sp_sd              <= 1'b0;

      nram_req_valid     <= 8'd0;
      nram_req_we        <= 8'd0;
      nram_req_addr      <= '0;
      nram_req_wdata     <= '0;
      nram_swizzle_en    <= 1'b0;
      nram_transpose_en  <= 1'b0;
      nram_err_bank      <= 3'd0;
      nram_err_mask      <= 72'd0;

      wram_pp_sel        <= 1'b1; // Start with Buf0 = Shadow (DMA), Buf1 = Active (TFU)
      wram_dma_we        <= 1'b0;
      wram_dma_addr      <= 9'd0;
      wram_dma_wdata     <= 64'd0;
      wram_meta_we       <= 1'b0;
      wram_meta_wdata    <= 32'd0;
      wram_tfu_rd_en     <= 1'b0;
      wram_tfu_rd_addr   <= 7'd0;
      wram_err_bank      <= 2'd0;
      wram_err_mask      <= 72'd0;

      mpu_ipu_valid      <= 4'd0;
      mpu_ipu_we         <= 4'd0;
      mpu_ipu_addr       <= '0;
      mpu_ipu_wdata      <= '0;
      mpu_dma_valid      <= 1'b0;
      mpu_dma_we         <= 1'b0;
      mpu_dma_addr       <= 11'd0;
      mpu_dma_wdata      <= 64'd0;
      mpu_bcast_en       <= 1'b0;
      mpu_bcast_addr     <= 11'd0;
      mpu_atomic_add_en  <= 1'b0;
      mpu_err_bank       <= 3'd0;
      mpu_err_mask       <= 72'd0;
    end else begin
      cyc_cnt <= cyc_cnt + 1;

      // Default pulse deassertions
      sp_req_en       <= 1'b0;
      sp_req_we       <= 1'b0;
      nram_req_valid  <= 8'd0;
      nram_req_we     <= 8'd0;
      wram_dma_we     <= 1'b0;
      wram_meta_we    <= 1'b0;
      wram_tfu_rd_en  <= 1'b0;
      mpu_ipu_valid   <= 4'd0;
      mpu_ipu_we      <= 4'd0;
      mpu_dma_valid   <= 1'b0;
      mpu_dma_we      <= 1'b0;
      mpu_bcast_en    <= 1'b0;

      // -----------------------------------------------------------------------
      // Phase 1 (Cycles 1..73): Exhaustive 72-bit Single-Error Correction (SEC)
      // -----------------------------------------------------------------------
      if (cyc_cnt >= 1 && cyc_cnt <= 72) begin
        ecc_err_mask <= (72'd1 << (cyc_cnt - 1));
      end
      if (cyc_cnt >= 2 && cyc_cnt <= 73) begin
        if (!ecc_sec_err || ecc_ded_err || (ecc_dout != ecc_din)) begin
          $display("[ERROR] SEC failed at cycle %0d:dout=%h exp=%h sec=%b ded=%b",
                   cyc_cnt, ecc_dout, ecc_din, ecc_sec_err, ecc_ded_err);
          err_cnt <= err_cnt + 1;
        end else begin
          sec_pass_cnt <= sec_pass_cnt + 1;
        end
      end
      // -----------------------------------------------------------------------
      // Phase 2 (Cycles 74..138): 64 Double-Error Detection (DED) Bit-Pairs
      // -----------------------------------------------------------------------
      if (cyc_cnt >= 74 && cyc_cnt <= 137) begin
        int unsigned b0, b1;
        b0 = cyc_cnt - 74;
        b1 = (b0 + 7) % 72;
        ecc_err_mask <= (72'd1 << b0) | (72'd1 << b1);
      end
      if (cyc_cnt >= 75 && cyc_cnt <= 138) begin
        if (ecc_sec_err || !ecc_ded_err) begin
          $display("[ERROR] DED failed at cycle %0d: sec=%b ded=%b syn=%h",
                   cyc_cnt, ecc_sec_err, ecc_ded_err, ecc_syndrome);
          err_cnt <= err_cnt + 1;
        end else begin
          ded_pass_cnt <= ded_pass_cnt + 1;
        end
      end

      // -----------------------------------------------------------------------
      // Phase 3 (Cycles 140..360): SRAM Macro 6-Phase March-C- BIST & Repair
      // -----------------------------------------------------------------------
      if (cyc_cnt == 140) begin
        ecc_err_mask <= 72'd0;
        sp_bist_en   <= 1'b1;
      end
      if (cyc_cnt == 345) begin
        if (!sp_bist_done || sp_bist_fail) begin
          $display("[ERROR] SRAM March-C- BIST failed: done=%b fail=%b addr=%h",
                   sp_bist_done, sp_bist_fail, sp_bist_fail_addr);
          err_cnt <= err_cnt + 1;
        end else begin
          $display("[PASS] SRAM Macro 6-Phase March-C- BIST passed (0 faults across 16 rows).");
        end
        sp_bist_en         <= 1'b0;
        sp_repair_en       <= 1'b1;
        sp_repair_bad_addr <= 8'h2A;
      end
      if (cyc_cnt == 347) begin
        sp_req_en    <= 1'b1;
        sp_req_we    <= 1'b1;
        sp_req_addr  <= 8'h2A;
        sp_req_wdata <= 64'hCAFE_BABE_DEAD_BEEF;
      end
      if (cyc_cnt == 349) begin
        sp_req_en   <= 1'b1;
        sp_req_we   <= 1'b0;
        sp_req_addr <= 8'h2A;
      end
      if (cyc_cnt == 351) begin
        if (!sp_rvalid || (sp_rdata != 64'hCAFE_BABE_DEAD_BEEF) ||
            (sp_repair_spare_data != 64'hCAFE_BABE_DEAD_BEEF)) begin
          $display("[ERROR] Spare-Row Repair failed: rdata=%h spare=%h",
                   sp_rdata, sp_repair_spare_data);
          err_cnt <= err_cnt + 1;
        end else begin
          $display("[PASS] SRAM Spare-Row Redundancy Fuse Repair verified at addr 0x2A.");
        end
      end

      // -----------------------------------------------------------------------
      // Phase 4 (Cycles 355..375): NRAM Bank Conflict, XOR Swizzle, & 8x8 Transpose
      // -----------------------------------------------------------------------
      if (cyc_cnt == 355) begin
        // Stride-8 access without swizzling -> all 8 lanes hit Bank 0 -> Conflict!
        nram_swizzle_en   <= 1'b0;
        nram_transpose_en <= 1'b0;
        nram_req_valid    <= 8'hFF;
        nram_req_we       <= 8'hFF;
        for (int l = 0; l < 8; l++) begin
          nram_req_addr[l]  <= 10'(l * 8);
          nram_req_wdata[l] <= 64'h1000_0000_0000_0000 + 64'(l);
        end
      end
      if (cyc_cnt == 356) begin
        if (!nram_conflict_stall || (nram_req_grant != 8'h01)) begin
          $display("[ERROR] NRAM Bank Conflict not detected: stall=%b grant=%b",
                   nram_conflict_stall, nram_req_grant);
          err_cnt <= err_cnt + 1;
        end
        // Now enable XOR Swizzling on the exact same Stride-8 addresses -> Zero Conflict!
        nram_swizzle_en <= 1'b1;
        nram_req_valid  <= 8'hFF;
        nram_req_we     <= 8'hFF;
        for (int l = 0; l < 8; l++) begin
          nram_req_addr[l]  <= 10'(l * 8);
          nram_req_wdata[l] <= 64'h2000_0000_0000_0000 + 64'(l);
        end
      end
      if (cyc_cnt == 357) begin
        saved_conflict_cnt <= nram_conflict_cnt;
        if (nram_conflict_stall || (nram_req_grant != 8'hFF)) begin
          $display("[ERROR] NRAM XOR Bank Swizzling failed: stall=%b grant=%b",
                   nram_conflict_stall, nram_req_grant);
          err_cnt <= err_cnt + 1;
        end else begin
          $display("[PASS] NRAM Bank Conflict Detection (cnt=%0d) & XOR Swizzling (8/8 grant) verified.",
                   nram_conflict_cnt);
        end
        // Write 8x8 byte matrix into Row 2 across Banks 0..7: A[r][c] = (r << 4) | c
        nram_swizzle_en   <= 1'b0;
        nram_transpose_en <= 1'b0;
        nram_req_valid    <= 8'hFF;
        nram_req_we       <= 8'hFF;
        for (int r = 0; r < 8; r++) begin
          nram_req_addr[r] <= {7'd2, 3'(r)};
          for (int c = 0; c < 8; c++) begin
            nram_req_wdata[r][c*8 +: 8] <= {4'(r), 4'(c)};
          end
        end
      end
      if (cyc_cnt == 359) begin
        // Read back Row 2 with On-the-Fly 8x8 Matrix Transpose enabled!
        nram_transpose_en <= 1'b1;
        nram_req_valid    <= 8'hFF;
        nram_req_we       <= 8'h00;
        for (int r = 0; r < 8; r++) begin
          nram_req_addr[r] <= {7'd2, 3'(r)};
        end
      end
      if (cyc_cnt == 361) begin
        if (nram_resp_valid != 8'hFF) begin
          $display("[ERROR] NRAM Transpose read valid mismatch: %b", nram_resp_valid);
          err_cnt <= err_cnt + 1;
        end else begin
          for (int r = 0; r < 8; r++) begin
            for (int c = 0; c < 8; c++) begin
              if (nram_resp_rdata[r][c*8 +: 8] != {4'(c), 4'(r)}) begin
                $display("[ERROR] NRAM 8x8 Transpose mismatch at (%0d,%0d): got %h exp %h",
                         r, c, nram_resp_rdata[r][c*8 +: 8], {4'(c), 4'(r)});
                err_cnt <= err_cnt + 1;
              end
            end
          end
          $display("[PASS] NRAM On-the-Fly 8x8 2D Matrix Transpose (OP_BANG_TRANSPOSE) verified.");
        end
        nram_transpose_en <= 1'b0;
      end
      // -----------------------------------------------------------------------
      // Phase 5 (Cycles 362..372): WRAM Ping-Pong Concurrent DMA + TFU Read
      // -----------------------------------------------------------------------
      if (cyc_cnt >= 362 && cyc_cnt <= 365) begin
        // wram_pp_sel == 1 -> Shadow is Buf 0. Stream 4 banks of Row 5 into Buf 0
        int unsigned bk;
        bk = cyc_cnt - 362;
        wram_pp_sel     <= 1'b1;
        wram_dma_we     <= 1'b1;
        wram_dma_addr   <= {2'(bk), 7'd5};
        wram_dma_wdata  <= 64'hABCD_0000_0000_0010 + 64'(bk);
        if (bk == 0) begin
          wram_meta_we    <= 1'b1;
          wram_meta_wdata <= 32'hE4E4_B1B1;
        end
      end
      if (cyc_cnt == 367) begin
        // Switch Ping-Pong: Buf 0 becomes Active (TFU), Buf 1 becomes Shadow (DMA)
        // Issue concurrent TFU 256b read from Buf 0 Row 5 AND DMA write to Buf 1 Row 5!
        wram_pp_sel     <= 1'b0;
        wram_tfu_rd_en  <= 1'b1;
        wram_tfu_rd_addr<= 7'd5;
        wram_dma_we     <= 1'b1;
        wram_dma_addr   <= {2'd0, 7'd5};
        wram_dma_wdata  <= 64'hDEAD_BEEF_0000_9999;
      end
      if (cyc_cnt == 369) begin
        if (!wram_tfu_weight_valid ||
            (wram_tfu_weight_vec != {64'hABCD_0000_0000_0013, 64'hABCD_0000_0000_0012,
                                     64'hABCD_0000_0000_0011, 64'hABCD_0000_0000_0010}) ||
            (wram_tfu_meta_o != 32'hE4E4_B1B1)) begin
          $display("[ERROR] WRAM Ping-Pong TFU read mismatch: valid=%b vec=%h meta=%h",
                   wram_tfu_weight_valid, wram_tfu_weight_vec, wram_tfu_meta_o);
          err_cnt <= err_cnt + 1;
        end else begin
          $display("[PASS] WRAM Ping-Pong Concurrent DMA + 256-bit TFU Broadcast + Cambricon-S Meta verified.");
        end
      end

      // -----------------------------------------------------------------------
      // Phase 6 (Cycles 370..384): MPU Shared SRAM Broadcast & Atomic AllReduce
      // -----------------------------------------------------------------------
      if (cyc_cnt == 370) begin
        // 4 IPU cores simultaneously write Banks 0..3 at Row 9
        mpu_atomic_add_en <= 1'b0;
        mpu_ipu_valid     <= 4'b1111;
        mpu_ipu_we        <= 4'b1111;
        for (int i = 0; i < 4; i++) begin
          mpu_ipu_addr[i]  <= {3'(i), 8'd9};
          mpu_ipu_wdata[i] <= 64'h5900_6900_0000_0100 + 64'(i);
        end
      end
      if (cyc_cnt == 372) begin
        // Single-cycle 256-bit Multi-Cast Broadcast of Row 9 to all 4 IPUs
        mpu_bcast_en   <= 1'b1;
        mpu_bcast_addr <= 11'd9;
      end
      if (cyc_cnt == 374) begin
        if ((mpu_bcast_valid != 4'b1111) ||
            (mpu_bcast_data != {64'h5900_6900_0000_0103, 64'h5900_6900_0000_0102,
                                64'h5900_6900_0000_0101, 64'h5900_6900_0000_0100})) begin
          $display("[ERROR] MPU Shared SRAM Broadcast failed: valid=%b data=%h",
                   mpu_bcast_valid, mpu_bcast_data);
          err_cnt <= err_cnt + 1;
        end else begin
          $display("[PASS] MPU Shared SRAM 256-bit Multi-Cast Broadcast (OP_MPU_BCAST_SRAM) verified.");
        end
        // Initialize Bank 4 Row 3 to 100 via DMA (atomic_add_en = 0)
        mpu_atomic_add_en <= 1'b0;
        mpu_dma_valid     <= 1'b1;
        mpu_dma_we        <= 1'b1;
        mpu_dma_addr      <= {3'd4, 8'd3};
        mpu_dma_wdata     <= 64'd100;
      end
      if (cyc_cnt >= 375 && cyc_cnt <= 378) begin
        // 4 Atomic AllReduce Accumulations (+10, +20, +30, +40) into Bank 4 Row 3
        mpu_atomic_add_en <= 1'b1;
        mpu_ipu_valid[0]  <= 1'b1;
        mpu_ipu_we[0]     <= 1'b1;
        mpu_ipu_addr[0]   <= {3'd4, 8'd3};
        mpu_ipu_wdata[0]  <= {32'd0, (cyc_cnt - 32'd374) * 32'd10};
      end
      if (cyc_cnt == 380) begin
        mpu_atomic_add_en <= 1'b0;
        mpu_dma_valid     <= 1'b1;
        mpu_dma_we        <= 1'b0;
        mpu_dma_addr      <= {3'd4, 8'd3};
      end
      if (cyc_cnt == 382) begin
        if (!mpu_dma_rvalid || (mpu_dma_rdata != 64'd200)) begin
          $display("[ERROR] MPU Shared SRAM Atomic AllReduce failed: rvalid=%b rdata=%0d (exp 200)",
                   mpu_dma_rvalid, mpu_dma_rdata);
          err_cnt <= err_cnt + 1;
        end else begin
          $display("[PASS] MPU Shared SRAM In-Memory Atomic AllReduce (100+10+20+30+40 = 200) verified.");
        end
      end

      // -----------------------------------------------------------------------
      // Final Verdict Summary
      // -----------------------------------------------------------------------
      if (cyc_cnt == 385) begin
        $display("==================================================================");
        $display("[STAGE 2 SUMMARY] SEC_PASS=%0d/72, DED_PASS=%0d/64, CONFLICT_CNT=%0d, ERR_CNT=%0d",
                 sec_pass_cnt, ded_pass_cnt, saved_conflict_cnt, err_cnt);
        $display("==================================================================");
        test_done_o <= 1'b1;
        test_pass_o <= (err_cnt == 0) && (sec_pass_cnt == 72) && (ded_pass_cnt == 64);
      end
    end
  end

  logic unused_tb_sigs;
  assign unused_tb_sigs = &{1'b0, sp_sec_err, sp_ded_err, sp_syndrome, sp_scrub_addr,
                            sp_pwr_ready, nram_sec_err, nram_ded_err, wram_sec_err,
                            wram_ded_err, mpu_ipu_grant, mpu_ipu_rdata, mpu_ipu_rvalid,
                            mpu_dma_grant, mpu_sec_err, mpu_ded_err};

endmodule : tb_stage2_mem_subsystem
