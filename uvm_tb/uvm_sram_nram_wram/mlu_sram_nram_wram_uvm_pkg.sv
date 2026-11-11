// =============================================================================
// File: uvm_tb/uvm_sram_nram_wram/mlu_sram_nram_wram_uvm_pkg.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Accellera IEEE 1800.2-2020 UVM Verification Package for Suite 1:
//              mlu_sram_secded_ecc, mlu_sram_sp_macro, mlu_nram_banked_scratchpad,
//              mlu_wram_weight_buffer, and mlu_mpu_shared_sram.
// =============================================================================
`ifndef MLU_SRAM_NRAM_WRAM_UVM_PKG_SV
`define MLU_SRAM_NRAM_WRAM_UVM_PKG_SV

`timescale 1ns/1ps
`include "uvm_macros.svh"
`include "mlu_pkg.sv"

package mlu_sram_nram_wram_uvm_pkg;
  import uvm_pkg::*;
  import mlu_pkg::*;

  // DPI-C C++17 Hsiao (72,64) SECDED Reference Model Imports
  import "DPI-C" function void         dpi_sram_set_status(int status);
  import "DPI-C" function int          dpi_sram_get_status();
  import "DPI-C" function int unsigned dpi_sram_get_calls();
  import "DPI-C" function int unsigned dpi_ecc_ref_syndrome(longint unsigned err_lo64, int unsigned err_hi8);
  import "DPI-C" function int unsigned dpi_ecc_ref_sec(longint unsigned err_lo64, int unsigned err_hi8);
  import "DPI-C" function int unsigned dpi_ecc_ref_ded(longint unsigned err_lo64, int unsigned err_hi8);
  import "DPI-C" function longint unsigned dpi_ecc_ref_dout(longint unsigned din, longint unsigned err_lo64, int unsigned err_hi8);

  // ---------------------------------------------------------------------------
  // 1. UVM Sequence Item: mlu_sram_seq_item
  // ---------------------------------------------------------------------------
  class mlu_sram_seq_item extends uvm_sequence_item;
    `uvm_object_utils(mlu_sram_seq_item)

    int unsigned cycle_id;
    int unsigned subtest_id;

    // Driven Stimulus Fields
    logic [63:0] ecc_din;
    logic [71:0] ecc_err_mask;

    logic        sp_req_en;
    logic        sp_req_we;
    logic [7:0]  sp_req_addr;
    logic [63:0] sp_req_wdata;
    logic [7:0]  sp_req_wmask;
    logic [71:0] sp_err_mask;
    logic        sp_bist_en;
    logic        sp_repair_en;
    logic [7:0]  sp_repair_bad_addr;
    logic        sp_scrub_en;
    logic        sp_slp;
    logic        sp_dslp;
    logic        sp_sd;

    logic [7:0]       nram_req_valid;
    logic [7:0]       nram_req_we;
    logic [7:0][9:0]  nram_req_addr;
    logic [7:0][63:0] nram_req_wdata;
    logic             nram_swizzle_en;
    logic             nram_transpose_en;
    logic [2:0]       nram_err_bank;
    logic [71:0]      nram_err_mask;

    logic         wram_pp_sel;
    logic         wram_dma_we;
    logic [8:0]   wram_dma_addr;
    logic [63:0]  wram_dma_wdata;
    logic         wram_meta_we;
    logic [31:0]  wram_meta_wdata;
    logic         wram_tfu_rd_en;
    logic [6:0]   wram_tfu_rd_addr;
    logic [1:0]   wram_err_bank;
    logic [71:0]  wram_err_mask;

    logic [3:0]       mpu_ipu_valid;
    logic [3:0]       mpu_ipu_we;
    logic [3:0][10:0] mpu_ipu_addr;
    logic [3:0][63:0] mpu_ipu_wdata;
    logic             mpu_dma_valid;
    logic             mpu_dma_we;
    logic [10:0]      mpu_dma_addr;
    logic [63:0]      mpu_dma_wdata;
    logic             mpu_bcast_en;
    logic [10:0]      mpu_bcast_addr;
    logic             mpu_atomic_add_en;
    logic [2:0]       mpu_err_bank;
    logic [71:0]      mpu_err_mask;
    // Observed DUT Response Fields
    logic [63:0] act_ecc_dout;
    logic [7:0]  act_ecc_syndrome;
    logic        act_ecc_sec_err;
    logic        act_ecc_ded_err;

    logic [63:0] act_sp_rdata;
    logic        act_sp_rvalid;
    logic        act_sp_sec_err;
    logic        act_sp_ded_err;
    logic        act_sp_bist_done;
    logic        act_sp_bist_fail;
    logic [63:0] act_sp_spare_data;
    logic        act_sp_pwr_ready;

    logic [7:0]       act_nram_grant;
    logic [7:0][63:0] act_nram_rdata;
    logic [7:0]       act_nram_rvalid;
    logic             act_nram_conflict_stall;
    logic [31:0]      act_nram_conflict_cnt;
    logic             act_nram_sec_err;
    logic             act_nram_ded_err;

    logic [255:0] act_wram_weight_vec;
    logic [31:0]  act_wram_meta_o;
    logic         act_wram_weight_valid;
    logic         act_wram_sec_err;
    logic         act_wram_ded_err;

    logic [3:0]       act_mpu_ipu_grant;
    logic [3:0][63:0] act_mpu_ipu_rdata;
    logic [3:0]       act_mpu_ipu_rvalid;
    logic             act_mpu_dma_grant;
    logic [63:0]      act_mpu_dma_rdata;
    logic             act_mpu_dma_rvalid;
    logic [255:0]     act_mpu_bcast_data;
    logic [3:0]       act_mpu_bcast_valid;
    logic             act_mpu_sec_err;
    logic             act_mpu_ded_err;

    function new(string name = "mlu_sram_seq_item");
      super.new(name);
    endfunction
  endclass : mlu_sram_seq_item

  // ---------------------------------------------------------------------------
  // 2. UVM Sequencer: mlu_sram_sequencer
  // ---------------------------------------------------------------------------
  class mlu_sram_sequencer extends uvm_sequencer #(mlu_sram_seq_item);
    `uvm_component_utils(mlu_sram_sequencer)
    function new(string name = "mlu_sram_sequencer", uvm_component parent = null);
      super.new(name, parent);
    endfunction
  endclass : mlu_sram_sequencer

  // ---------------------------------------------------------------------------
  // 3. UVM Sequence: mlu_sram_sequence (1,200 Cycles Directed + Constrained-Random)
  // ---------------------------------------------------------------------------
  class mlu_sram_sequence extends uvm_sequence #(mlu_sram_seq_item);
    `uvm_object_utils(mlu_sram_sequence)

    int unsigned num_cycles = 1200;
    longint unsigned prng_state = 64'h5906_90CA_FEBA_BE01;

    function new(string name = "mlu_sram_sequence");
      super.new(name);
    endfunction

    function longint unsigned next_rand64();
      prng_state ^= (prng_state << 13);
      prng_state ^= (prng_state >> 7);
      prng_state ^= (prng_state << 17);
      return prng_state;
    endfunction
    task body();
      for (int unsigned cyc = 0; cyc < num_cycles; cyc++) begin
        mlu_sram_seq_item item = mlu_sram_seq_item::type_id::create("item");
        longint unsigned r0 = next_rand64();
        longint unsigned r1 = next_rand64();
        start_item(item);

        item.cycle_id           = cyc;
        item.subtest_id         = (cyc < 200) ? 0 : (cyc < 450) ? 1 : (cyc < 650) ? 2 :
                                  (cyc < 850) ? 3 : (cyc < 1050) ? 4 : 5;
        item.ecc_din            = r0;
        item.ecc_err_mask       = 72'd0;

        item.sp_req_en          = 1'b0;
        item.sp_req_we          = 1'b0;
        item.sp_req_addr        = 8'd0;
        item.sp_req_wdata       = 64'd0;
        item.sp_req_wmask       = 8'hFF;
        item.sp_err_mask        = 72'd0;
        item.sp_bist_en         = 1'b0;
        item.sp_repair_en       = 1'b0;
        item.sp_repair_bad_addr = 8'h2A;
        item.sp_scrub_en        = 1'b0;
        item.sp_slp             = 1'b0;
        item.sp_dslp            = 1'b0;
        item.sp_sd              = 1'b0;

        item.nram_req_valid     = '0;
        item.nram_req_we        = '0;
        item.nram_req_addr      = '0;
        item.nram_req_wdata     = '0;
        item.nram_swizzle_en    = 1'b0;
        item.nram_transpose_en  = 1'b0;
        item.nram_err_bank      = 3'd0;
        item.nram_err_mask      = 72'd0;

        item.wram_pp_sel        = 1'b0;
        item.wram_dma_we        = 1'b0;
        item.wram_dma_addr      = 9'd0;
        item.wram_dma_wdata     = 64'd0;
        item.wram_meta_we       = 1'b0;
        item.wram_meta_wdata    = 32'd0;
        item.wram_tfu_rd_en     = 1'b0;
        item.wram_tfu_rd_addr   = 7'd0;
        item.wram_err_bank      = 2'd0;
        item.wram_err_mask      = 72'd0;

        item.mpu_ipu_valid      = '0;
        item.mpu_ipu_we         = '0;
        item.mpu_ipu_addr       = '0;
        item.mpu_ipu_wdata      = '0;
        item.mpu_dma_valid      = 1'b0;
        item.mpu_dma_we         = 1'b0;
        item.mpu_dma_addr       = 11'd0;
        item.mpu_dma_wdata      = 64'd0;
        item.mpu_bcast_en       = 1'b0;
        item.mpu_bcast_addr     = 11'd0;
        item.mpu_atomic_add_en  = 1'b0;
        item.mpu_err_bank       = 3'd0;
        item.mpu_err_mask       = 72'd0;

        // Always exercise standalone SECDED ECC codec with clean, 1-bit SEC, and 2-bit DED
        if (cyc < 72) begin
          item.ecc_err_mask = 72'd1 << cyc;
        end else if (cyc < 143) begin
          int b0 = (cyc - 72);
          int b1 = (b0 + 7) % 72;
          item.ecc_err_mask = (72'd1 << b0) | (72'd1 << b1);
        end else if ((cyc % 3) == 1) begin
          item.ecc_err_mask = 72'd1 << (r1[6:0] % 72);
        end else if ((cyc % 3) == 2) begin
          int b0 = r1[6:0] % 72;
          int b1 = (b0 + 1 + (r1[13:7] % 71)) % 72;
          item.ecc_err_mask = (72'd1 << b0) | (72'd1 << b1);
        end
        // Phase 0 (0..199): SP-SRAM Writes & SEC/DED Fault-Injected Reads
        if (cyc < 64) begin
          item.sp_req_en    = 1'b1;
          item.sp_req_we    = 1'b1;
          item.sp_req_addr  = 8'(cyc);
          item.sp_req_wdata = 64'hCAFE_0000_0000_0000 | (64'(cyc) * 64'h0101_0101_0101);
        end else if (cyc < 192) begin
          int idx = cyc - 64;
          item.sp_req_en    = 1'b1;
          item.sp_req_we    = 1'b0;
          item.sp_req_addr  = 8'(idx % 64);
          if ((idx % 3) == 1) begin
            item.sp_err_mask = 72'd1 << (idx % 72);
          end else if ((idx % 3) == 2) begin
            item.sp_err_mask = (72'd1 << (idx % 36)) | (72'd1 << ((idx % 36) + 36));
          end
        end
        // Phase 1 (200..449): March-C- BIST (200..405) + Spare-Row Fuse Repair + Low-Power
        else if (cyc >= 200 && cyc < 405) begin
          item.sp_bist_en = 1'b1;
        end else if (cyc == 410) begin
          item.sp_req_en          = 1'b1;
          item.sp_req_we          = 1'b1;
          item.sp_req_addr        = 8'h2A;
          item.sp_req_wdata       = 64'hDEAD_BEEF_1234_5678;
          item.sp_repair_en       = 1'b1;
          item.sp_repair_bad_addr = 8'h2A;
        end else if (cyc == 411) begin
          item.sp_req_en          = 1'b1;
          item.sp_req_we          = 1'b0;
          item.sp_req_addr        = 8'h2A;
          item.sp_repair_en       = 1'b1;
          item.sp_repair_bad_addr = 8'h2A;
        end else if (cyc == 412) begin
          item.sp_repair_en       = 1'b1;
          item.sp_repair_bad_addr = 8'h2A;
        end else if (cyc >= 415 && cyc < 419) begin
          item.sp_slp  = (cyc < 417);
          item.sp_dslp = (cyc >= 417);
        end else if (cyc >= 419 && cyc < 421) begin
          item.sp_sd   = 1'b1;
        end else if (cyc >= 423 && cyc < 435) begin
          item.sp_scrub_en = 1'b1;
        end else if (cyc == 436) begin
          item.sp_req_en    = 1'b1;
          item.sp_req_we    = 1'b1;
          item.sp_req_addr  = 8'h3F;
          item.sp_req_wdata = 64'h55AA_55AA_55AA_55AA;
          item.sp_req_wmask = 8'h0F;
        end
        // Phase 2 (450..649): NRAM Bank-Conflict Stress vs. XOR Swizzling + 8x8 Transpose
        else if (cyc >= 450 && cyc < 500) begin
          item.sp_bist_en  = 1'b1;
          item.sp_err_mask = 72'd3 << ((cyc - 450) % 60);
          // Power-of-2 stride (stride=8 words): raw bank = 0 for all 8 lanes
          // Even cycles: swizzle_en=0 -> conflict_stall=1; Odd cycles: swizzle_en=1 -> 0 stall
          item.nram_swizzle_en = cyc[0];
          item.nram_req_valid  = 8'hFF;
          item.nram_req_we     = 8'hFF;
          for (int l = 0; l < 8; l++) begin
            item.nram_req_addr[l]  = 10'(l * 8);
            item.nram_req_wdata[l] = 64'hA000_0000_0000_0000 + (64'(cyc) << 8) + 64'(l);
          end
        end else if (cyc >= 500 && cyc < 550) begin
          item.sp_bist_en  = 1'b1;
          item.sp_err_mask = 72'd3 << ((cyc - 500) % 60);
          // Swizzled conflict-free reads
          item.nram_swizzle_en = 1'b1;
          item.nram_req_valid  = 8'hFF;
          item.nram_req_we     = 8'h00;
          for (int l = 0; l < 8; l++) begin
            item.nram_req_addr[l] = 10'(l * 8);
          end
          if (cyc == 510) begin
            item.nram_err_bank = 3'd2;
            item.nram_err_mask = 72'd1 << 11;
          end else if (cyc == 512) begin
            item.nram_err_bank = 3'd3;
            item.nram_err_mask = (72'd1 << 4) | (72'd1 << 29);
          end
        end else if (cyc >= 550 && cyc < 560) begin
          item.sp_bist_en  = 1'b1;
          item.sp_err_mask = 72'd3 << ((cyc - 550) % 60);
        end else if (cyc == 560) begin
          // 8x8 2D Matrix Transpose Write to Row 2 across Banks 0..7
          item.nram_transpose_en = 1'b1;
          item.nram_req_valid    = 8'hFF;
          item.nram_req_we       = 8'hFF;
          for (int r = 0; r < 8; r++) begin
            item.nram_req_addr[r] = {7'd2, 3'(r)};
            for (int c = 0; c < 8; c++) begin
              item.nram_req_wdata[r][c*8 +: 8] = 8'((r << 4) | c);
            end
          end
        end else if (cyc == 561) begin
          // Read back Row 2 without read-side transpose so we observe transposed matrix in SRAM
          item.nram_transpose_en = 1'b0;
          item.nram_req_valid    = 8'hFF;
          item.nram_req_we       = 8'h00;
          for (int r = 0; r < 8; r++) begin
            item.nram_req_addr[r] = {7'd2, 3'(r)};
          end
        end
        // Phase 3 (650..849): WRAM Ping-Pong Shadow Fill + 256b TFU Read + Sparse Meta
        else if (cyc >= 650 && cyc < 682) begin
          // ping_pong_sel=0 => shadow buffer is Buf 1. Fill rows 0..7 across 4 banks
          int idx = cyc - 650;
          int row = idx / 4;
          int bnk = idx % 4;
          item.wram_pp_sel     = 1'b0;
          item.wram_dma_we     = 1'b1;
          item.wram_dma_addr   = {2'(bnk), 7'(row)};
          item.wram_dma_wdata  = 64'hB100_0000_0000_0000 | (64'(row) << 16) | 64'(bnk);
          item.wram_meta_we    = (bnk == 0);
          item.wram_meta_wdata = 32'hE4E4_0000 | 32'(row);
        end else if (cyc >= 682 && cyc < 750) begin
          // Flip ping_pong_sel=1 => Buf 1 is active for 256-bit TFU read while DMA fills Buf 0
          int row = (cyc - 682) % 8;
          item.wram_pp_sel      = 1'b1;
          item.wram_tfu_rd_en   = 1'b1;
          item.wram_tfu_rd_addr = 7'(row);
          item.wram_dma_we      = 1'b1;
          item.wram_dma_addr    = {2'((cyc - 682) % 4), 7'(row)};
          item.wram_dma_wdata   = 64'hB000_0000_0000_0000 | (64'(row) << 16) | 64'((cyc - 682) % 4);
          item.wram_meta_we     = 1'b1;
          item.wram_meta_wdata  = 32'hD0D0_0000 | 32'(row);
          if (cyc == 690) begin
            item.wram_err_bank = 2'd1;
            item.wram_err_mask = 72'd1 << 19;
          end else if (cyc == 692) begin
            item.wram_err_bank = 2'd2;
            item.wram_err_mask = (72'd1 << 3) | (72'd1 << 41);
          end
        end else if (cyc >= 750 && cyc < 782) begin
          // Flip ping_pong_sel=0 => Buf 0 is active for 256-bit TFU read & sparse_meta_mem0 readback
          int row = (cyc - 750) % 8;
          item.wram_pp_sel      = 1'b0;
          item.wram_tfu_rd_en   = 1'b1;
          item.wram_tfu_rd_addr = 7'(row);
        end
        // Phase 4 (850..1049): MPU Shared SRAM 4-IPU Broadcast + Atomic AllReduce
        else if (cyc >= 850 && cyc < 854) begin
          // Write Banks 0..3 at Row 5 via 4 IPU ports in parallel
          item.mpu_ipu_valid = 4'b1111;
          item.mpu_ipu_we    = 4'b1111;
          for (int i = 0; i < 4; i++) begin
            item.mpu_ipu_addr[i]  = {3'(i), 8'd5};
            item.mpu_ipu_wdata[i] = 64'hC000_0000_0000_0000 | 64'(i + 1);
          end
        end else if (cyc >= 855 && cyc < 875) begin
          // 1-to-4 Multi-Cast Broadcast of Row 5 (256-bit across Banks 0..3)
          item.mpu_bcast_en   = 1'b1;
          item.mpu_bcast_addr = {3'd0, 8'd5};
          if (cyc == 860) begin
            item.mpu_err_bank = 3'd1;
            item.mpu_err_mask = 72'd1 << 22;
          end
        end else if (cyc == 880) begin
          // Initialize Bank 4 Row 3 to 100 with atomic_add_en=0
          item.mpu_dma_valid     = 1'b1;
          item.mpu_dma_we        = 1'b1;
          item.mpu_dma_addr      = {3'd4, 8'd3};
          item.mpu_dma_wdata     = 64'd100;
          item.mpu_atomic_add_en = 1'b0;
        end else if (cyc >= 881 && cyc <= 884) begin
          // 4 consecutive Atomic AllReduce accumulations (+10, +20, +30, +40 -> 200)
          int step = cyc - 880;
          item.mpu_ipu_valid     = 4'b0001;
          item.mpu_ipu_we        = 4'b0001;
          item.mpu_ipu_addr[0]   = {3'd4, 8'd3};
          item.mpu_ipu_wdata[0]  = 64'(step * 10);
          item.mpu_atomic_add_en = 1'b1;
        end else if (cyc == 885) begin
          // Read back Bank 4 Row 3 via IPU 0 (expect 200)
          item.mpu_ipu_valid   = 4'b0001;
          item.mpu_ipu_we      = 4'b0000;
          item.mpu_ipu_addr[0] = {3'd4, 8'd3};
        end
        // Phase 5 (1050..1199): Constrained-Random Multi-Memory Stress
        else if (cyc >= 1050) begin
          item.nram_swizzle_en = r0[0];
          item.nram_req_valid  = r0[15:8];
          item.nram_req_we     = r0[23:16];
          for (int l = 0; l < 8; l++) begin
            item.nram_req_addr[l]  = r1[(l*8) +: 8] + 10'(l * 16);
            item.nram_req_wdata[l] = r0 ^ (64'(l) << 32);
          end
          item.wram_pp_sel      = r0[1];
          item.wram_tfu_rd_en   = r0[2];
          item.wram_tfu_rd_addr = r0[9:3];
          item.mpu_bcast_en     = r0[4];
          item.mpu_bcast_addr   = {3'd0, 8'd5};
        end

        finish_item(item);
      end
    endtask
  endclass : mlu_sram_sequence
  // ---------------------------------------------------------------------------
  // 4. UVM Driver: mlu_sram_driver
  // ---------------------------------------------------------------------------
  class mlu_sram_driver extends uvm_driver #(mlu_sram_seq_item);
    `uvm_component_utils(mlu_sram_driver)

    virtual mlu_sram_nram_wram_if vif;
    int unsigned driven = 0;

    function new(string name = "mlu_sram_driver", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual mlu_sram_nram_wram_if)::get(this, "", "vif", vif)) begin
        `uvm_fatal("NO_VIF", "Virtual interface mlu_sram_nram_wram_if missing in mlu_sram_driver")
      end
    endfunction

    task run_phase(uvm_phase phase);
      mlu_sram_seq_item item;
      vif.rst_n       = 1'b0;
      vif.cycle_valid = 1'b0;
      repeat (3) @(negedge vif.clk);

      forever begin
        seq_item_port.get_next_item(item);
        vif.rst_n              = 1'b1;
        vif.cycle_id           = item.cycle_id;
        vif.subtest_id         = item.subtest_id;

        vif.ecc_din            = item.ecc_din;
        vif.ecc_err_mask       = item.ecc_err_mask;

        vif.sp_req_en          = item.sp_req_en;
        vif.sp_req_we          = item.sp_req_we;
        vif.sp_req_addr        = item.sp_req_addr;
        vif.sp_req_wdata       = item.sp_req_wdata;
        vif.sp_req_wmask       = item.sp_req_wmask;
        vif.sp_err_mask        = item.sp_err_mask;
        vif.sp_bist_en         = item.sp_bist_en;
        vif.sp_repair_en       = item.sp_repair_en;
        vif.sp_repair_bad_addr = item.sp_repair_bad_addr;
        vif.sp_scrub_en        = item.sp_scrub_en;
        vif.sp_slp             = item.sp_slp;
        vif.sp_dslp            = item.sp_dslp;
        vif.sp_sd              = item.sp_sd;

        vif.nram_req_valid     = item.nram_req_valid;
        vif.nram_req_we        = item.nram_req_we;
        vif.nram_req_addr      = item.nram_req_addr;
        vif.nram_req_wdata     = item.nram_req_wdata;
        vif.nram_swizzle_en    = item.nram_swizzle_en;
        vif.nram_transpose_en  = item.nram_transpose_en;
        vif.nram_err_bank      = item.nram_err_bank;
        vif.nram_err_mask      = item.nram_err_mask;

        vif.wram_pp_sel        = item.wram_pp_sel;
        vif.wram_dma_we        = item.wram_dma_we;
        vif.wram_dma_addr      = item.wram_dma_addr;
        vif.wram_dma_wdata     = item.wram_dma_wdata;
        vif.wram_meta_we       = item.wram_meta_we;
        vif.wram_meta_wdata    = item.wram_meta_wdata;
        vif.wram_tfu_rd_en     = item.wram_tfu_rd_en;
        vif.wram_tfu_rd_addr   = item.wram_tfu_rd_addr;
        vif.wram_err_bank      = item.wram_err_bank;
        vif.wram_err_mask      = item.wram_err_mask;

        vif.mpu_ipu_valid      = item.mpu_ipu_valid;
        vif.mpu_ipu_we         = item.mpu_ipu_we;
        vif.mpu_ipu_addr       = item.mpu_ipu_addr;
        vif.mpu_ipu_wdata      = item.mpu_ipu_wdata;
        vif.mpu_dma_valid      = item.mpu_dma_valid;
        vif.mpu_dma_we         = item.mpu_dma_we;
        vif.mpu_dma_addr       = item.mpu_dma_addr;
        vif.mpu_dma_wdata      = item.mpu_dma_wdata;
        vif.mpu_bcast_en       = item.mpu_bcast_en;
        vif.mpu_bcast_addr     = item.mpu_bcast_addr;
        vif.mpu_atomic_add_en  = item.mpu_atomic_add_en;
        vif.mpu_err_bank       = item.mpu_err_bank;
        vif.mpu_err_mask       = item.mpu_err_mask;

        vif.cycle_valid = 1'b1;
        @(posedge vif.clk);
        #1ns;
        vif.cycle_valid = 1'b0;
        driven++;
        @(negedge vif.clk);
        seq_item_port.item_done();
      end
    endtask
  endclass : mlu_sram_driver
  // ---------------------------------------------------------------------------
  // 5. UVM Monitor: mlu_sram_monitor (with Functional Covergroup)
  // ---------------------------------------------------------------------------
  class mlu_sram_monitor extends uvm_monitor;
    `uvm_component_utils(mlu_sram_monitor)

    virtual mlu_sram_nram_wram_if vif;
    uvm_analysis_port #(mlu_sram_seq_item) ap;
    int unsigned seen = 0;

    covergroup mlu_sram_cg with function sample(
      int unsigned subtest,
      bit          sec_hit,
      bit          ded_hit,
      bit          bist_done,
      bit          swizzle_en,
      bit          conflict_stall,
      bit          wram_valid,
      bit          mpu_bcast
    );
      option.per_instance = 1;
      cp_subtest: coverpoint subtest {
        bins st_ecc_sp   = {0};
        bins st_bist_rep = {1};
        bins st_nram     = {2};
        bins st_wram     = {3};
        bins st_mpu      = {4};
        bins st_stress   = {5};
      }
      cp_sec: coverpoint sec_hit { bins b0 = {0}; bins b1 = {1}; }
      cp_ded: coverpoint ded_hit { bins b0 = {0}; bins b1 = {1}; }
      cp_bist: coverpoint bist_done { bins b0 = {0}; bins b1 = {1}; }
      cp_swiz: coverpoint swizzle_en { bins b0 = {0}; bins b1 = {1}; }
      cp_conf: coverpoint conflict_stall { bins b0 = {0}; bins b1 = {1}; }
      cp_wram: coverpoint wram_valid { bins b0 = {0}; bins b1 = {1}; }
      cp_bcast: coverpoint mpu_bcast { bins b0 = {0}; bins b1 = {1}; }
    endgroup

    function new(string name = "mlu_sram_monitor", uvm_component parent = null);
      super.new(name, parent);
      ap = new("ap", this);
      mlu_sram_cg = new();
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual mlu_sram_nram_wram_if)::get(this, "", "vif", vif)) begin
        `uvm_fatal("NO_VIF", "Virtual interface mlu_sram_nram_wram_if missing in mlu_sram_monitor")
      end
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        @(negedge vif.clk);
        #1ns;
        if (vif.rst_n && vif.cycle_valid) begin
          mlu_sram_seq_item item = mlu_sram_seq_item::type_id::create("obs_item");
          item.cycle_id                = vif.cycle_id;
          item.subtest_id              = vif.subtest_id;

          item.ecc_din                 = vif.ecc_din;
          item.ecc_err_mask            = vif.ecc_err_mask;
          item.act_ecc_dout            = vif.ecc_dout;
          item.act_ecc_syndrome        = vif.ecc_syndrome;
          item.act_ecc_sec_err         = vif.ecc_sec_err;
          item.act_ecc_ded_err         = vif.ecc_ded_err;

          item.sp_req_en               = vif.sp_req_en;
          item.sp_req_we               = vif.sp_req_we;
          item.sp_req_addr             = vif.sp_req_addr;
          item.sp_req_wdata            = vif.sp_req_wdata;
          item.sp_err_mask             = vif.sp_err_mask;
          item.sp_bist_en              = vif.sp_bist_en;
          item.sp_repair_en            = vif.sp_repair_en;
          item.sp_repair_bad_addr      = vif.sp_repair_bad_addr;
          item.act_sp_rdata            = vif.sp_rdata;
          item.act_sp_rvalid           = vif.sp_rvalid;
          item.act_sp_sec_err          = vif.sp_sec_err;
          item.act_sp_ded_err          = vif.sp_ded_err;
          item.act_sp_bist_done        = vif.sp_bist_done;
          item.act_sp_bist_fail        = vif.sp_bist_fail;
          item.act_sp_spare_data       = vif.sp_repair_spare_data;
          item.act_sp_pwr_ready        = vif.sp_pwr_ready;
          item.nram_req_valid          = vif.nram_req_valid;
          item.nram_req_we             = vif.nram_req_we;
          item.nram_req_addr           = vif.nram_req_addr;
          item.nram_req_wdata          = vif.nram_req_wdata;
          item.nram_swizzle_en         = vif.nram_swizzle_en;
          item.nram_transpose_en       = vif.nram_transpose_en;
          item.nram_err_bank           = vif.nram_err_bank;
          item.nram_err_mask           = vif.nram_err_mask;
          item.act_nram_grant          = vif.nram_req_grant;
          item.act_nram_rdata          = vif.nram_resp_rdata;
          item.act_nram_rvalid         = vif.nram_resp_valid;
          item.act_nram_conflict_stall = vif.nram_conflict_stall;
          item.act_nram_conflict_cnt   = vif.nram_conflict_cnt;
          item.act_nram_sec_err        = vif.nram_sec_err;
          item.act_nram_ded_err        = vif.nram_ded_err;

          item.wram_pp_sel             = vif.wram_pp_sel;
          item.wram_dma_we             = vif.wram_dma_we;
          item.wram_dma_addr           = vif.wram_dma_addr;
          item.wram_dma_wdata          = vif.wram_dma_wdata;
          item.wram_meta_we            = vif.wram_meta_we;
          item.wram_meta_wdata         = vif.wram_meta_wdata;
          item.wram_tfu_rd_en          = vif.wram_tfu_rd_en;
          item.wram_tfu_rd_addr        = vif.wram_tfu_rd_addr;
          item.act_wram_weight_vec     = vif.wram_tfu_weight_vec;
          item.act_wram_meta_o         = vif.wram_tfu_meta_o;
          item.act_wram_weight_valid   = vif.wram_tfu_weight_valid;
          item.act_wram_sec_err        = vif.wram_sec_err;
          item.act_wram_ded_err        = vif.wram_ded_err;

          item.mpu_ipu_valid           = vif.mpu_ipu_valid;
          item.mpu_ipu_we              = vif.mpu_ipu_we;
          item.mpu_ipu_addr            = vif.mpu_ipu_addr;
          item.mpu_ipu_wdata           = vif.mpu_ipu_wdata;
          item.mpu_bcast_en            = vif.mpu_bcast_en;
          item.mpu_bcast_addr          = vif.mpu_bcast_addr;
          item.mpu_atomic_add_en       = vif.mpu_atomic_add_en;
          item.act_mpu_ipu_grant       = vif.mpu_ipu_grant;
          item.act_mpu_ipu_rdata       = vif.mpu_ipu_rdata;
          item.act_mpu_ipu_rvalid      = vif.mpu_ipu_rvalid;
          item.act_mpu_dma_grant       = vif.mpu_dma_grant;
          item.act_mpu_dma_rdata       = vif.mpu_dma_rdata;
          item.act_mpu_dma_rvalid      = vif.mpu_dma_rvalid;
          item.act_mpu_bcast_data      = vif.mpu_bcast_data;
          item.act_mpu_bcast_valid     = vif.mpu_bcast_valid;
          item.act_mpu_sec_err         = vif.mpu_sec_err;
          item.act_mpu_ded_err         = vif.mpu_ded_err;

          mlu_sram_cg.sample(
            item.subtest_id,
            (item.act_ecc_sec_err | item.act_sp_sec_err | item.act_nram_sec_err | item.act_wram_sec_err | item.act_mpu_sec_err),
            (item.act_ecc_ded_err | item.act_sp_ded_err | item.act_nram_ded_err | item.act_wram_ded_err | item.act_mpu_ded_err),
            item.act_sp_bist_done,
            item.nram_swizzle_en,
            item.act_nram_conflict_stall,
            item.act_wram_weight_valid,
            (|item.act_mpu_bcast_valid)
          );

          seen++;
          ap.write(item);
        end
      end
    endtask
  endclass : mlu_sram_monitor

  // ---------------------------------------------------------------------------
  // 6. UVM Agent: mlu_sram_agent
  // ---------------------------------------------------------------------------
  class mlu_sram_agent extends uvm_agent;
    `uvm_component_utils(mlu_sram_agent)

    mlu_sram_sequencer sequencer;
    mlu_sram_driver    driver;
    mlu_sram_monitor   monitor;

    function new(string name = "mlu_sram_agent", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      sequencer = mlu_sram_sequencer::type_id::create("sequencer", this);
      driver    = mlu_sram_driver::type_id::create("driver", this);
      monitor   = mlu_sram_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
  endclass : mlu_sram_agent
  // ---------------------------------------------------------------------------
  // 7. UVM Scoreboard: mlu_sram_scoreboard (C++17 DPI-C + SV Golden Reference)
  // ---------------------------------------------------------------------------
  class mlu_sram_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(mlu_sram_scoreboard)

    uvm_analysis_imp #(mlu_sram_seq_item, mlu_sram_scoreboard) analysis_export;

    int unsigned checked_cycles    = 0;
    int unsigned mismatches        = 0;
    int unsigned sec_verified_cnt  = 0;
    int unsigned ded_verified_cnt  = 0;
    int unsigned bist_verified_cnt = 0;
    int unsigned repair_verified   = 0;
    int unsigned nram_swiz_checks  = 0;
    int unsigned nram_xpose_checks = 0;
    int unsigned wram_pp_checks    = 0;
    int unsigned mpu_bcast_checks  = 0;
    int unsigned mpu_atomic_checks = 0;

    function new(string name = "mlu_sram_scoreboard", uvm_component parent = null);
      super.new(name, parent);
      analysis_export = new("analysis_export", this);
    endfunction

    function void write(mlu_sram_seq_item item);
      int unsigned exp_syn;
      int unsigned exp_sec;
      int unsigned exp_ded;
      longint unsigned exp_dout;

      checked_cycles++;

      // 1. Check Standalone (72,64) Hsiao SECDED ECC Codec via C++17 DPI-C Model
      exp_syn  = dpi_ecc_ref_syndrome(item.ecc_err_mask[63:0], {24'd0, item.ecc_err_mask[71:64]});
      exp_sec  = dpi_ecc_ref_sec(item.ecc_err_mask[63:0], {24'd0, item.ecc_err_mask[71:64]});
      exp_ded  = dpi_ecc_ref_ded(item.ecc_err_mask[63:0], {24'd0, item.ecc_err_mask[71:64]});
      exp_dout = dpi_ecc_ref_dout(item.ecc_din, item.ecc_err_mask[63:0], {24'd0, item.ecc_err_mask[71:64]});

      if (item.act_ecc_syndrome !== exp_syn[7:0] ||
          item.act_ecc_sec_err  !== exp_sec[0]   ||
          item.act_ecc_ded_err  !== exp_ded[0]   ||
          (exp_ded[0] == 1'b0 && item.act_ecc_dout !== exp_dout)) begin
        `uvm_error("ECC_MISMATCH", $sformatf(
          "Cyc %0d: syn=%h(exp %h) sec=%b(exp %b) ded=%b(exp %b) dout=%h(exp %h)",
          item.cycle_id, item.act_ecc_syndrome, exp_syn[7:0],
          item.act_ecc_sec_err, exp_sec[0], item.act_ecc_ded_err, exp_ded[0],
          item.act_ecc_dout, exp_dout))
        mismatches++;
      end else begin
        if (exp_sec[0]) sec_verified_cnt++;
        if (exp_ded[0]) ded_verified_cnt++;
      end

      // 2. Check SP-SRAM Read & SEC/DED Fault Injection (Phase 0: cyc 65..192)
      if (item.cycle_id >= 65 && item.cycle_id <= 192 && item.act_sp_rvalid) begin
        int rd_idx = (item.cycle_id - 65) % 64;
        logic [63:0] exp_sp_word = 64'hCAFE_0000_0000_0000 | (64'(rd_idx) * 64'h0101_0101_0101);
        int unsigned sp_sec = dpi_ecc_ref_sec(item.sp_err_mask[63:0], {24'd0, item.sp_err_mask[71:64]});
        int unsigned sp_ded = dpi_ecc_ref_ded(item.sp_err_mask[63:0], {24'd0, item.sp_err_mask[71:64]});
        if (item.act_sp_sec_err !== sp_sec[0] || item.act_sp_ded_err !== sp_ded[0] ||
            (sp_ded[0] == 1'b0 && item.act_sp_rdata !== exp_sp_word)) begin
          `uvm_error("SP_SRAM_MISMATCH", $sformatf(
            "Cyc %0d: rdata=%h(exp %h) sec=%b ded=%b",
            item.cycle_id, item.act_sp_rdata, exp_sp_word, item.act_sp_sec_err, item.act_sp_ded_err))
          mismatches++;
        end else begin
          if (sp_sec[0]) sec_verified_cnt++;
          if (sp_ded[0]) ded_verified_cnt++;
        end
      end

      // 3. Check Hardware March-C- BIST & Spare-Row Fuse Repair (Phase 1)
      if (item.cycle_id == 404) begin
        if (!item.act_sp_bist_done || item.act_sp_bist_fail) begin
          `uvm_error("BIST_FAIL", $sformatf("Cyc 404: bist_done=%b bist_fail=%b",
            item.act_sp_bist_done, item.act_sp_bist_fail))
          mismatches++;
        end else begin
          bist_verified_cnt++;
        end
      end
      if (item.cycle_id == 412) begin
        if (!item.act_sp_rvalid || item.act_sp_rdata !== 64'hDEAD_BEEF_1234_5678 ||
            item.act_sp_spare_data !== 64'hDEAD_BEEF_1234_5678) begin
          `uvm_error("REPAIR_FAIL", $sformatf("Cyc 412: spare rdata=%h", item.act_sp_rdata))
          mismatches++;
        end else begin
          repair_verified++;
        end
      end
      // 4. Check NRAM Bank-Conflict vs. XOR Swizzling & 8x8 2D Matrix Transpose (Phase 2)
      if (item.cycle_id >= 450 && item.cycle_id < 500) begin
        bit exp_stall = !item.nram_swizzle_en;
        logic [7:0] exp_grant = item.nram_swizzle_en ? 8'hFF : 8'h01;
        if (item.act_nram_conflict_stall !== exp_stall || item.act_nram_grant !== exp_grant) begin
          `uvm_error("NRAM_SWIZ_FAIL", $sformatf("Cyc %0d: swiz=%b stall=%b grant=%b",
            item.cycle_id, item.nram_swizzle_en, item.act_nram_conflict_stall, item.act_nram_grant))
          mismatches++;
        end else begin
          nram_swiz_checks++;
        end
      end
      if (item.cycle_id == 562) begin
        if (item.act_nram_rvalid !== 8'hFF) begin
          `uvm_error("NRAM_XPOSE_VALID", "Cyc 562: expected 8-lane transpose read valid")
          mismatches++;
        end else begin
          for (int r = 0; r < 8; r++) begin
            for (int c = 0; c < 8; c++) begin
              if (item.act_nram_rdata[r][c*8 +: 8] !== 8'((c << 4) | r)) begin
                `uvm_error("NRAM_XPOSE_DATA", $sformatf("r=%0d c=%0d got=%h",
                  r, c, item.act_nram_rdata[r][c*8 +: 8]))
                mismatches++;
              end
            end
          end
          nram_xpose_checks++;
        end
      end

      // 5. Check WRAM Ping-Pong 256-bit TFU Read & Cambricon-S Sparse Meta (Phase 3)
      if (item.cycle_id >= 683 && item.cycle_id < 750 && item.act_wram_weight_valid) begin
        int rd_row = (item.cycle_id - 683) % 8;
        logic [31:0] exp_meta = 32'hE4E4_0000 | 32'(rd_row);
        if (item.act_wram_meta_o !== exp_meta) begin
          `uvm_error("WRAM_META_FAIL", $sformatf("Cyc %0d: meta=%h exp=%h",
            item.cycle_id, item.act_wram_meta_o, exp_meta))
          mismatches++;
        end
        if (item.cycle_id != 692) begin
          for (int b = 0; b < 4; b++) begin
            logic [63:0] exp_w = 64'hB100_0000_0000_0000 | (64'(rd_row) << 16) | 64'(b);
            if (item.act_wram_weight_vec[b*64 +: 64] !== exp_w) begin
              `uvm_error("WRAM_VEC_FAIL", $sformatf("Cyc %0d b=%0d got=%h exp=%h",
                item.cycle_id, b, item.act_wram_weight_vec[b*64 +: 64], exp_w))
              mismatches++;
            end
          end
        end
        wram_pp_checks++;
      end

      // 6. Check MPU Shared SRAM 1-to-4 Broadcast & Atomic AllReduce (Phase 4)
      if (item.cycle_id >= 856 && item.cycle_id < 875 && (|item.act_mpu_bcast_valid)) begin
        logic [255:0] exp_bcast = {
          64'hC000_0000_0000_0004, 64'hC000_0000_0000_0003,
          64'hC000_0000_0000_0002, 64'hC000_0000_0000_0001
        };
        if (item.act_mpu_bcast_valid !== 4'b1111 || item.act_mpu_bcast_data !== exp_bcast) begin
          `uvm_error("MPU_BCAST_FAIL", $sformatf("Cyc %0d: bcast=%h", item.cycle_id, item.act_mpu_bcast_data))
          mismatches++;
        end else begin
          mpu_bcast_checks++;
        end
      end
      if (item.cycle_id == 886) begin
        if (!item.act_mpu_ipu_rvalid[0] || item.act_mpu_ipu_rdata[0] !== 64'd200) begin
          `uvm_error("MPU_ATOMIC_FAIL", $sformatf("Cyc 886: atomic rdata=%0d exp=200",
            item.act_mpu_ipu_rdata[0]))
          mismatches++;
        end else begin
          mpu_atomic_checks++;
        end
      end
    endfunction
  endclass : mlu_sram_scoreboard

  // ---------------------------------------------------------------------------
  // 8. UVM Environment & Test
  // ---------------------------------------------------------------------------
  class mlu_sram_env extends uvm_env;
    `uvm_component_utils(mlu_sram_env)
    mlu_sram_agent      agent;
    mlu_sram_scoreboard scoreboard;
    function new(string name = "mlu_sram_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent      = mlu_sram_agent::type_id::create("agent", this);
      scoreboard = mlu_sram_scoreboard::type_id::create("scoreboard", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent.monitor.ap.connect(scoreboard.analysis_export);
    endfunction
  endclass : mlu_sram_env

  class mlu_sram_nram_wram_test extends uvm_test;
    `uvm_component_utils(mlu_sram_nram_wram_test)
    mlu_sram_env env;
    function new(string name = "mlu_sram_nram_wram_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = mlu_sram_env::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
      mlu_sram_sequence seq = mlu_sram_sequence::type_id::create("seq");
      phase.raise_objection(this);
      seq.start(env.agent.sequencer);
      phase.drop_objection(this);
    endtask
    function void report_phase(uvm_phase phase);
      real func_cov = env.agent.monitor.mlu_sram_cg.get_inst_coverage();
      bit pass_gate = (env.agent.driver.driven == 1200) &&
                      (env.scoreboard.checked_cycles == 1200) &&
                      (env.scoreboard.mismatches == 0) &&
                      (env.scoreboard.sec_verified_cnt >= 100) &&
                      (env.scoreboard.ded_verified_cnt >= 100) &&
                      (env.scoreboard.bist_verified_cnt > 0) &&
                      (env.scoreboard.repair_verified > 0) &&
                      (env.scoreboard.nram_swiz_checks >= 50) &&
                      (env.scoreboard.nram_xpose_checks > 0) &&
                      (env.scoreboard.wram_pp_checks >= 60) &&
                      (env.scoreboard.mpu_bcast_checks >= 15) &&
                      (env.scoreboard.mpu_atomic_checks > 0);
      super.report_phase(phase);
      dpi_sram_set_status(pass_gate ? 0 : 1);
      if (!pass_gate) begin
        `uvm_fatal("UVM_SRAM_FAIL", $sformatf("Suite 1 gate failed: mismatches=%0d cov=%0.2f%%",
          env.scoreboard.mismatches, func_cov))
      end else begin
        `uvm_info("UVM_SRAM_PASS", $sformatf(
          "SUITE 1 PASS: cycles=%0d dpi_calls=%0d sec=%0d ded=%0d bist=%0d repair=%0d swiz=%0d xpose=%0d wram=%0d bcast=%0d atomic=%0d cov=%0.2f%%",
          env.scoreboard.checked_cycles, dpi_sram_get_calls(),
          env.scoreboard.sec_verified_cnt, env.scoreboard.ded_verified_cnt,
          env.scoreboard.bist_verified_cnt, env.scoreboard.repair_verified,
          env.scoreboard.nram_swiz_checks, env.scoreboard.nram_xpose_checks,
          env.scoreboard.wram_pp_checks, env.scoreboard.mpu_bcast_checks,
          env.scoreboard.mpu_atomic_checks, func_cov), UVM_LOW)
      end
    endfunction
  endclass : mlu_sram_nram_wram_test

endpackage : mlu_sram_nram_wram_uvm_pkg

`endif // MLU_SRAM_NRAM_WRAM_UVM_PKG_SV
