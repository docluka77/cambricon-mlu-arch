//      // verilator_coverage annotation
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
%000000   class mlu_sram_seq_item extends uvm_sequence_item;
~001200     `uvm_object_utils(mlu_sram_seq_item)
        
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
        
~002400     function new(string name = "mlu_sram_seq_item");
 002400       super.new(name);
            endfunction
          endclass : mlu_sram_seq_item
        
          // ---------------------------------------------------------------------------
          // 2. UVM Sequencer: mlu_sram_sequencer
          // ---------------------------------------------------------------------------
          class mlu_sram_sequencer extends uvm_sequencer #(mlu_sram_seq_item);
%000001     `uvm_component_utils(mlu_sram_sequencer)
%000001     function new(string name = "mlu_sram_sequencer", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
          endclass : mlu_sram_sequencer
        
          // ---------------------------------------------------------------------------
          // 3. UVM Sequence: mlu_sram_sequence (1,200 Cycles Directed + Constrained-Random)
          // ---------------------------------------------------------------------------
          class mlu_sram_sequence extends uvm_sequence #(mlu_sram_seq_item);
%000001     `uvm_object_utils(mlu_sram_sequence)
        
%000001     int unsigned num_cycles = 1200;
%000001     longint unsigned prng_state = 64'h5906_90CA_FEBA_BE01;
        
%000001     function new(string name = "mlu_sram_sequence");
%000001       super.new(name);
            endfunction
        
 002400     function longint unsigned next_rand64();
 002400       prng_state ^= (prng_state << 13);
 002400       prng_state ^= (prng_state >> 7);
 002400       prng_state ^= (prng_state << 17);
 002400       return prng_state;
            endfunction
%000001     task body();
~001200       for (int unsigned cyc = 0; cyc < num_cycles; cyc++) begin
 001200         mlu_sram_seq_item item = mlu_sram_seq_item::type_id::create("item");
 001200         longint unsigned r0 = next_rand64();
 001200         longint unsigned r1 = next_rand64();
 001200         start_item(item);
        
 001200         item.cycle_id           = cyc;
 001200         item.subtest_id         = (cyc < 200) ? 0 : (cyc < 450) ? 1 : (cyc < 650) ? 2 :
                                          (cyc < 850) ? 3 : (cyc < 1050) ? 4 : 5;
 001200         item.ecc_din            = r0;
 001200         item.ecc_err_mask       = 72'd0;
        
 001200         item.sp_req_en          = 1'b0;
 001200         item.sp_req_we          = 1'b0;
 001200         item.sp_req_addr        = 8'd0;
 001200         item.sp_req_wdata       = 64'd0;
 001200         item.sp_req_wmask       = 8'hFF;
 001200         item.sp_err_mask        = 72'd0;
 001200         item.sp_bist_en         = 1'b0;
 001200         item.sp_repair_en       = 1'b0;
 001200         item.sp_repair_bad_addr = 8'h2A;
 001200         item.sp_scrub_en        = 1'b0;
 001200         item.sp_slp             = 1'b0;
 001200         item.sp_dslp            = 1'b0;
 001200         item.sp_sd              = 1'b0;
        
 001200         item.nram_req_valid     = '0;
 001200         item.nram_req_we        = '0;
 001200         item.nram_req_addr      = '0;
 001200         item.nram_req_wdata     = '0;
 001200         item.nram_swizzle_en    = 1'b0;
 001200         item.nram_transpose_en  = 1'b0;
 001200         item.nram_err_bank      = 3'd0;
 001200         item.nram_err_mask      = 72'd0;
        
 001200         item.wram_pp_sel        = 1'b0;
 001200         item.wram_dma_we        = 1'b0;
 001200         item.wram_dma_addr      = 9'd0;
 001200         item.wram_dma_wdata     = 64'd0;
 001200         item.wram_meta_we       = 1'b0;
 001200         item.wram_meta_wdata    = 32'd0;
 001200         item.wram_tfu_rd_en     = 1'b0;
 001200         item.wram_tfu_rd_addr   = 7'd0;
 001200         item.wram_err_bank      = 2'd0;
 001200         item.wram_err_mask      = 72'd0;
        
 001200         item.mpu_ipu_valid      = '0;
 001200         item.mpu_ipu_we         = '0;
 001200         item.mpu_ipu_addr       = '0;
 001200         item.mpu_ipu_wdata      = '0;
 001200         item.mpu_dma_valid      = 1'b0;
 001200         item.mpu_dma_we         = 1'b0;
 001200         item.mpu_dma_addr       = 11'd0;
 001200         item.mpu_dma_wdata      = 64'd0;
 001200         item.mpu_bcast_en       = 1'b0;
 001200         item.mpu_bcast_addr     = 11'd0;
 001200         item.mpu_atomic_add_en  = 1'b0;
 001200         item.mpu_err_bank       = 3'd0;
 001200         item.mpu_err_mask       = 72'd0;
        
                // Always exercise standalone SECDED ECC codec with clean, 1-bit SEC, and 2-bit DED
 000072         if (cyc < 72) begin
 000072           item.ecc_err_mask = 72'd1 << cyc;
 000071         end else if (cyc < 143) begin
 000071           int b0 = (cyc - 72);
 000071           int b1 = (b0 + 7) % 72;
 000071           item.ecc_err_mask = (72'd1 << b0) | (72'd1 << b1);
 000352         end else if ((cyc % 3) == 1) begin
 000352           item.ecc_err_mask = 72'd1 << (r1[6:0] % 72);
 000353         end else if ((cyc % 3) == 2) begin
 000353           int b0 = r1[6:0] % 72;
 000353           int b1 = (b0 + 1 + (r1[13:7] % 71)) % 72;
 000353           item.ecc_err_mask = (72'd1 << b0) | (72'd1 << b1);
                end
                // Phase 0 (0..199): SP-SRAM Writes & SEC/DED Fault-Injected Reads
 000064         if (cyc < 64) begin
 000064           item.sp_req_en    = 1'b1;
 000064           item.sp_req_we    = 1'b1;
 000064           item.sp_req_addr  = 8'(cyc);
 000064           item.sp_req_wdata = 64'hCAFE_0000_0000_0000 | (64'(cyc) * 64'h0101_0101_0101);
 000128         end else if (cyc < 192) begin
 000128           int idx = cyc - 64;
 000128           item.sp_req_en    = 1'b1;
 000128           item.sp_req_we    = 1'b0;
 000128           item.sp_req_addr  = 8'(idx % 64);
 000043           if ((idx % 3) == 1) begin
 000043             item.sp_err_mask = 72'd1 << (idx % 72);
 000043           end else if ((idx % 3) == 2) begin
 000042             item.sp_err_mask = (72'd1 << (idx % 36)) | (72'd1 << ((idx % 36) + 36));
                  end
                end
                // Phase 1 (200..449): March-C- BIST (200..405) + Spare-Row Fuse Repair + Low-Power
 000205         else if (cyc >= 200 && cyc < 405) begin
 000205           item.sp_bist_en = 1'b1;
%000001         end else if (cyc == 410) begin
%000001           item.sp_req_en          = 1'b1;
%000001           item.sp_req_we          = 1'b1;
%000001           item.sp_req_addr        = 8'h2A;
%000001           item.sp_req_wdata       = 64'hDEAD_BEEF_1234_5678;
%000001           item.sp_repair_en       = 1'b1;
%000001           item.sp_repair_bad_addr = 8'h2A;
%000001         end else if (cyc == 411) begin
%000001           item.sp_req_en          = 1'b1;
%000001           item.sp_req_we          = 1'b0;
%000001           item.sp_req_addr        = 8'h2A;
%000001           item.sp_repair_en       = 1'b1;
%000001           item.sp_repair_bad_addr = 8'h2A;
%000001         end else if (cyc == 412) begin
%000001           item.sp_repair_en       = 1'b1;
%000001           item.sp_repair_bad_addr = 8'h2A;
%000004         end else if (cyc >= 415 && cyc < 419) begin
%000004           item.sp_slp  = (cyc < 417);
%000004           item.sp_dslp = (cyc >= 417);
%000002         end else if (cyc >= 419 && cyc < 421) begin
%000002           item.sp_sd   = 1'b1;
 000012         end else if (cyc >= 423 && cyc < 435) begin
 000012           item.sp_scrub_en = 1'b1;
%000001         end else if (cyc == 436) begin
%000001           item.sp_req_en    = 1'b1;
%000001           item.sp_req_we    = 1'b1;
%000001           item.sp_req_addr  = 8'h3F;
%000001           item.sp_req_wdata = 64'h55AA_55AA_55AA_55AA;
%000001           item.sp_req_wmask = 8'h0F;
                end
                // Phase 2 (450..649): NRAM Bank-Conflict Stress vs. XOR Swizzling + 8x8 Transpose
 000050         else if (cyc >= 450 && cyc < 500) begin
 000050           item.sp_bist_en  = 1'b1;
 000050           item.sp_err_mask = 72'd3 << ((cyc - 450) % 60);
                  // Power-of-2 stride (stride=8 words): raw bank = 0 for all 8 lanes
                  // Even cycles: swizzle_en=0 -> conflict_stall=1; Odd cycles: swizzle_en=1 -> 0 stall
 000050           item.nram_swizzle_en = cyc[0];
 000050           item.nram_req_valid  = 8'hFF;
 000050           item.nram_req_we     = 8'hFF;
 000400           for (int l = 0; l < 8; l++) begin
 000400             item.nram_req_addr[l]  = 10'(l * 8);
 000400             item.nram_req_wdata[l] = 64'hA000_0000_0000_0000 + (64'(cyc) << 8) + 64'(l);
                  end
 000050         end else if (cyc >= 500 && cyc < 550) begin
 000050           item.sp_bist_en  = 1'b1;
 000050           item.sp_err_mask = 72'd3 << ((cyc - 500) % 60);
                  // Swizzled conflict-free reads
 000050           item.nram_swizzle_en = 1'b1;
 000050           item.nram_req_valid  = 8'hFF;
 000050           item.nram_req_we     = 8'h00;
 000400           for (int l = 0; l < 8; l++) begin
 000400             item.nram_req_addr[l] = 10'(l * 8);
                  end
%000001           if (cyc == 510) begin
%000001             item.nram_err_bank = 3'd2;
%000001             item.nram_err_mask = 72'd1 << 11;
~000048           end else if (cyc == 512) begin
%000001             item.nram_err_bank = 3'd3;
%000001             item.nram_err_mask = (72'd1 << 4) | (72'd1 << 29);
                  end
 000010         end else if (cyc >= 550 && cyc < 560) begin
 000010           item.sp_bist_en  = 1'b1;
 000010           item.sp_err_mask = 72'd3 << ((cyc - 550) % 60);
%000001         end else if (cyc == 560) begin
                  // 8x8 2D Matrix Transpose Write to Row 2 across Banks 0..7
%000001           item.nram_transpose_en = 1'b1;
%000001           item.nram_req_valid    = 8'hFF;
%000001           item.nram_req_we       = 8'hFF;
%000008           for (int r = 0; r < 8; r++) begin
%000008             item.nram_req_addr[r] = {7'd2, 3'(r)};
~000064             for (int c = 0; c < 8; c++) begin
 000064               item.nram_req_wdata[r][c*8 +: 8] = 8'((r << 4) | c);
                    end
                  end
%000001         end else if (cyc == 561) begin
                  // Read back Row 2 without read-side transpose so we observe transposed matrix in SRAM
%000001           item.nram_transpose_en = 1'b0;
%000001           item.nram_req_valid    = 8'hFF;
%000001           item.nram_req_we       = 8'h00;
%000008           for (int r = 0; r < 8; r++) begin
%000008             item.nram_req_addr[r] = {7'd2, 3'(r)};
                  end
                end
                // Phase 3 (650..849): WRAM Ping-Pong Shadow Fill + 256b TFU Read + Sparse Meta
 000032         else if (cyc >= 650 && cyc < 682) begin
                  // ping_pong_sel=0 => shadow buffer is Buf 1. Fill rows 0..7 across 4 banks
 000032           int idx = cyc - 650;
 000032           int row = idx / 4;
 000032           int bnk = idx % 4;
 000032           item.wram_pp_sel     = 1'b0;
 000032           item.wram_dma_we     = 1'b1;
 000032           item.wram_dma_addr   = {2'(bnk), 7'(row)};
 000032           item.wram_dma_wdata  = 64'hB100_0000_0000_0000 | (64'(row) << 16) | 64'(bnk);
 000032           item.wram_meta_we    = (bnk == 0);
 000032           item.wram_meta_wdata = 32'hE4E4_0000 | 32'(row);
 000068         end else if (cyc >= 682 && cyc < 750) begin
                  // Flip ping_pong_sel=1 => Buf 1 is active for 256-bit TFU read while DMA fills Buf 0
 000068           int row = (cyc - 682) % 8;
 000068           item.wram_pp_sel      = 1'b1;
 000068           item.wram_tfu_rd_en   = 1'b1;
 000068           item.wram_tfu_rd_addr = 7'(row);
 000068           item.wram_dma_we      = 1'b1;
 000068           item.wram_dma_addr    = {2'((cyc - 682) % 4), 7'(row)};
 000068           item.wram_dma_wdata   = 64'hB000_0000_0000_0000 | (64'(row) << 16) | 64'((cyc - 682) % 4);
 000068           item.wram_meta_we     = 1'b1;
 000068           item.wram_meta_wdata  = 32'hD0D0_0000 | 32'(row);
%000001           if (cyc == 690) begin
%000001             item.wram_err_bank = 2'd1;
%000001             item.wram_err_mask = 72'd1 << 19;
~000066           end else if (cyc == 692) begin
%000001             item.wram_err_bank = 2'd2;
%000001             item.wram_err_mask = (72'd1 << 3) | (72'd1 << 41);
                  end
 000032         end else if (cyc >= 750 && cyc < 782) begin
                  // Flip ping_pong_sel=0 => Buf 0 is active for 256-bit TFU read & sparse_meta_mem0 readback
 000032           int row = (cyc - 750) % 8;
 000032           item.wram_pp_sel      = 1'b0;
 000032           item.wram_tfu_rd_en   = 1'b1;
 000032           item.wram_tfu_rd_addr = 7'(row);
                end
                // Phase 4 (850..1049): MPU Shared SRAM 4-IPU Broadcast + Atomic AllReduce
%000004         else if (cyc >= 850 && cyc < 854) begin
                  // Write Banks 0..3 at Row 5 via 4 IPU ports in parallel
%000004           item.mpu_ipu_valid = 4'b1111;
%000004           item.mpu_ipu_we    = 4'b1111;
~000016           for (int i = 0; i < 4; i++) begin
 000016             item.mpu_ipu_addr[i]  = {3'(i), 8'd5};
 000016             item.mpu_ipu_wdata[i] = 64'hC000_0000_0000_0000 | 64'(i + 1);
                  end
 000020         end else if (cyc >= 855 && cyc < 875) begin
                  // 1-to-4 Multi-Cast Broadcast of Row 5 (256-bit across Banks 0..3)
 000020           item.mpu_bcast_en   = 1'b1;
 000020           item.mpu_bcast_addr = {3'd0, 8'd5};
~000019           if (cyc == 860) begin
%000001             item.mpu_err_bank = 3'd1;
%000001             item.mpu_err_mask = 72'd1 << 22;
                  end
%000001         end else if (cyc == 880) begin
                  // Initialize Bank 4 Row 3 to 100 with atomic_add_en=0
%000001           item.mpu_dma_valid     = 1'b1;
%000001           item.mpu_dma_we        = 1'b1;
%000001           item.mpu_dma_addr      = {3'd4, 8'd3};
%000001           item.mpu_dma_wdata     = 64'd100;
%000001           item.mpu_atomic_add_en = 1'b0;
%000004         end else if (cyc >= 881 && cyc <= 884) begin
                  // 4 consecutive Atomic AllReduce accumulations (+10, +20, +30, +40 -> 200)
%000004           int step = cyc - 880;
%000004           item.mpu_ipu_valid     = 4'b0001;
%000004           item.mpu_ipu_we        = 4'b0001;
%000004           item.mpu_ipu_addr[0]   = {3'd4, 8'd3};
%000004           item.mpu_ipu_wdata[0]  = 64'(step * 10);
%000004           item.mpu_atomic_add_en = 1'b1;
%000001         end else if (cyc == 885) begin
                  // Read back Bank 4 Row 3 via IPU 0 (expect 200)
%000001           item.mpu_ipu_valid   = 4'b0001;
%000001           item.mpu_ipu_we      = 4'b0000;
%000001           item.mpu_ipu_addr[0] = {3'd4, 8'd3};
                end
                // Phase 5 (1050..1199): Constrained-Random Multi-Memory Stress
 000357         else if (cyc >= 1050) begin
 000150           item.nram_swizzle_en = r0[0];
 000150           item.nram_req_valid  = r0[15:8];
 000150           item.nram_req_we     = r0[23:16];
 001200           for (int l = 0; l < 8; l++) begin
 001200             item.nram_req_addr[l]  = r1[(l*8) +: 8] + 10'(l * 16);
 001200             item.nram_req_wdata[l] = r0 ^ (64'(l) << 32);
                  end
 000150           item.wram_pp_sel      = r0[1];
 000150           item.wram_tfu_rd_en   = r0[2];
 000150           item.wram_tfu_rd_addr = r0[9:3];
 000150           item.mpu_bcast_en     = r0[4];
 000150           item.mpu_bcast_addr   = {3'd0, 8'd5};
                end
        
 001200         finish_item(item);
              end
            endtask
          endclass : mlu_sram_sequence
          // ---------------------------------------------------------------------------
          // 4. UVM Driver: mlu_sram_driver
          // ---------------------------------------------------------------------------
          class mlu_sram_driver extends uvm_driver #(mlu_sram_seq_item);
%000001     `uvm_component_utils(mlu_sram_driver)
        
            virtual mlu_sram_nram_wram_if vif;
%000001     int unsigned driven = 0;
        
%000001     function new(string name = "mlu_sram_driver", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       if (!uvm_config_db#(virtual mlu_sram_nram_wram_if)::get(this, "", "vif", vif)) begin
%000000         `uvm_fatal("NO_VIF", "Virtual interface mlu_sram_nram_wram_if missing in mlu_sram_driver")
              end
            endfunction
        
%000000     task run_phase(uvm_phase phase);
%000000       mlu_sram_seq_item item;
%000000       vif.rst_n       = 1'b0;
%000000       vif.cycle_valid = 1'b0;
%000003       repeat (3) @(negedge vif.clk);
        
 001200       forever begin
 001200         seq_item_port.get_next_item(item);
 001200         vif.rst_n              = 1'b1;
 001200         vif.cycle_id           = item.cycle_id;
 001200         vif.subtest_id         = item.subtest_id;
        
 001200         vif.ecc_din            = item.ecc_din;
 001200         vif.ecc_err_mask       = item.ecc_err_mask;
        
 001200         vif.sp_req_en          = item.sp_req_en;
 001200         vif.sp_req_we          = item.sp_req_we;
 001200         vif.sp_req_addr        = item.sp_req_addr;
 001200         vif.sp_req_wdata       = item.sp_req_wdata;
 001200         vif.sp_req_wmask       = item.sp_req_wmask;
 001200         vif.sp_err_mask        = item.sp_err_mask;
 001200         vif.sp_bist_en         = item.sp_bist_en;
 001200         vif.sp_repair_en       = item.sp_repair_en;
 001200         vif.sp_repair_bad_addr = item.sp_repair_bad_addr;
 001200         vif.sp_scrub_en        = item.sp_scrub_en;
 001200         vif.sp_slp             = item.sp_slp;
 001200         vif.sp_dslp            = item.sp_dslp;
 001200         vif.sp_sd              = item.sp_sd;
        
 001200         vif.nram_req_valid     = item.nram_req_valid;
 001200         vif.nram_req_we        = item.nram_req_we;
 001200         vif.nram_req_addr      = item.nram_req_addr;
 001200         vif.nram_req_wdata     = item.nram_req_wdata;
 001200         vif.nram_swizzle_en    = item.nram_swizzle_en;
 001200         vif.nram_transpose_en  = item.nram_transpose_en;
 001200         vif.nram_err_bank      = item.nram_err_bank;
 001200         vif.nram_err_mask      = item.nram_err_mask;
        
 001200         vif.wram_pp_sel        = item.wram_pp_sel;
 001200         vif.wram_dma_we        = item.wram_dma_we;
 001200         vif.wram_dma_addr      = item.wram_dma_addr;
 001200         vif.wram_dma_wdata     = item.wram_dma_wdata;
 001200         vif.wram_meta_we       = item.wram_meta_we;
 001200         vif.wram_meta_wdata    = item.wram_meta_wdata;
 001200         vif.wram_tfu_rd_en     = item.wram_tfu_rd_en;
 001200         vif.wram_tfu_rd_addr   = item.wram_tfu_rd_addr;
 001200         vif.wram_err_bank      = item.wram_err_bank;
 001200         vif.wram_err_mask      = item.wram_err_mask;
        
 001200         vif.mpu_ipu_valid      = item.mpu_ipu_valid;
 001200         vif.mpu_ipu_we         = item.mpu_ipu_we;
 001200         vif.mpu_ipu_addr       = item.mpu_ipu_addr;
 001200         vif.mpu_ipu_wdata      = item.mpu_ipu_wdata;
 001200         vif.mpu_dma_valid      = item.mpu_dma_valid;
 001200         vif.mpu_dma_we         = item.mpu_dma_we;
 001200         vif.mpu_dma_addr       = item.mpu_dma_addr;
 001200         vif.mpu_dma_wdata      = item.mpu_dma_wdata;
 001200         vif.mpu_bcast_en       = item.mpu_bcast_en;
 001200         vif.mpu_bcast_addr     = item.mpu_bcast_addr;
 001200         vif.mpu_atomic_add_en  = item.mpu_atomic_add_en;
 001200         vif.mpu_err_bank       = item.mpu_err_bank;
 001200         vif.mpu_err_mask       = item.mpu_err_mask;
        
 001200         vif.cycle_valid = 1'b1;
 001200         @(posedge vif.clk);
 001200         #1ns;
 001200         vif.cycle_valid = 1'b0;
 001200         driven++;
 001200         @(negedge vif.clk);
 001200         seq_item_port.item_done();
              end
            endtask
          endclass : mlu_sram_driver
          // ---------------------------------------------------------------------------
          // 5. UVM Monitor: mlu_sram_monitor (with Functional Covergroup)
          // ---------------------------------------------------------------------------
          class mlu_sram_monitor extends uvm_monitor;
%000001     `uvm_component_utils(mlu_sram_monitor)
        
            virtual mlu_sram_nram_wram_if vif;
            uvm_analysis_port #(mlu_sram_seq_item) ap;
%000001     int unsigned seen = 0;
        
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
 000200         bins st_ecc_sp   = {0};
 000250         bins st_bist_rep = {1};
 000200         bins st_nram     = {2};
 000200         bins st_wram     = {3};
 000200         bins st_mpu      = {4};
 000150         bins st_stress   = {5};
              }
 000733       cp_sec: coverpoint sec_hit { bins b0 = {0}; bins b1 = {1}; }
 000684       cp_ded: coverpoint ded_hit { bins b0 = {0}; bins b1 = {1}; }
 001172       cp_bist: coverpoint bist_done { bins b0 = {0}; bins b1 = {1}; }
 001045       cp_swiz: coverpoint swizzle_en { bins b0 = {0}; bins b1 = {1}; }
 001089       cp_conf: coverpoint conflict_stall { bins b0 = {0}; bins b1 = {1}; }
 001019       cp_wram: coverpoint wram_valid { bins b0 = {0}; bins b1 = {1}; }
 001099       cp_bcast: coverpoint mpu_bcast { bins b0 = {0}; bins b1 = {1}; }
            endgroup
        
%000001     function new(string name = "mlu_sram_monitor", uvm_component parent = null);
%000001       super.new(name, parent);
%000001       ap = new("ap", this);
%000001       mlu_sram_cg = new();
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       if (!uvm_config_db#(virtual mlu_sram_nram_wram_if)::get(this, "", "vif", vif)) begin
%000000         `uvm_fatal("NO_VIF", "Virtual interface mlu_sram_nram_wram_if missing in mlu_sram_monitor")
              end
            endfunction
        
%000000     task run_phase(uvm_phase phase);
 001202       forever begin
 001202         @(negedge vif.clk);
 001202         #1ns;
~001200         if (vif.rst_n && vif.cycle_valid) begin
 001200           mlu_sram_seq_item item = mlu_sram_seq_item::type_id::create("obs_item");
 001200           item.cycle_id                = vif.cycle_id;
 001200           item.subtest_id              = vif.subtest_id;
        
 001200           item.ecc_din                 = vif.ecc_din;
 001200           item.ecc_err_mask            = vif.ecc_err_mask;
 001200           item.act_ecc_dout            = vif.ecc_dout;
 001200           item.act_ecc_syndrome        = vif.ecc_syndrome;
 001200           item.act_ecc_sec_err         = vif.ecc_sec_err;
 001200           item.act_ecc_ded_err         = vif.ecc_ded_err;
        
 001200           item.sp_req_en               = vif.sp_req_en;
 001200           item.sp_req_we               = vif.sp_req_we;
 001200           item.sp_req_addr             = vif.sp_req_addr;
 001200           item.sp_req_wdata            = vif.sp_req_wdata;
 001200           item.sp_err_mask             = vif.sp_err_mask;
 001200           item.sp_bist_en              = vif.sp_bist_en;
 001200           item.sp_repair_en            = vif.sp_repair_en;
 001200           item.sp_repair_bad_addr      = vif.sp_repair_bad_addr;
 001200           item.act_sp_rdata            = vif.sp_rdata;
 001200           item.act_sp_rvalid           = vif.sp_rvalid;
 001200           item.act_sp_sec_err          = vif.sp_sec_err;
 001200           item.act_sp_ded_err          = vif.sp_ded_err;
 001200           item.act_sp_bist_done        = vif.sp_bist_done;
 001200           item.act_sp_bist_fail        = vif.sp_bist_fail;
 001200           item.act_sp_spare_data       = vif.sp_repair_spare_data;
 001200           item.act_sp_pwr_ready        = vif.sp_pwr_ready;
 001200           item.nram_req_valid          = vif.nram_req_valid;
 001200           item.nram_req_we             = vif.nram_req_we;
 001200           item.nram_req_addr           = vif.nram_req_addr;
 001200           item.nram_req_wdata          = vif.nram_req_wdata;
 001200           item.nram_swizzle_en         = vif.nram_swizzle_en;
 001200           item.nram_transpose_en       = vif.nram_transpose_en;
 001200           item.nram_err_bank           = vif.nram_err_bank;
 001200           item.nram_err_mask           = vif.nram_err_mask;
 001200           item.act_nram_grant          = vif.nram_req_grant;
 001200           item.act_nram_rdata          = vif.nram_resp_rdata;
 001200           item.act_nram_rvalid         = vif.nram_resp_valid;
 001200           item.act_nram_conflict_stall = vif.nram_conflict_stall;
 001200           item.act_nram_conflict_cnt   = vif.nram_conflict_cnt;
 001200           item.act_nram_sec_err        = vif.nram_sec_err;
 001200           item.act_nram_ded_err        = vif.nram_ded_err;
        
 001200           item.wram_pp_sel             = vif.wram_pp_sel;
 001200           item.wram_dma_we             = vif.wram_dma_we;
 001200           item.wram_dma_addr           = vif.wram_dma_addr;
 001200           item.wram_dma_wdata          = vif.wram_dma_wdata;
 001200           item.wram_meta_we            = vif.wram_meta_we;
 001200           item.wram_meta_wdata         = vif.wram_meta_wdata;
 001200           item.wram_tfu_rd_en          = vif.wram_tfu_rd_en;
 001200           item.wram_tfu_rd_addr        = vif.wram_tfu_rd_addr;
 001200           item.act_wram_weight_vec     = vif.wram_tfu_weight_vec;
 001200           item.act_wram_meta_o         = vif.wram_tfu_meta_o;
 001200           item.act_wram_weight_valid   = vif.wram_tfu_weight_valid;
 001200           item.act_wram_sec_err        = vif.wram_sec_err;
 001200           item.act_wram_ded_err        = vif.wram_ded_err;
        
 001200           item.mpu_ipu_valid           = vif.mpu_ipu_valid;
 001200           item.mpu_ipu_we              = vif.mpu_ipu_we;
 001200           item.mpu_ipu_addr            = vif.mpu_ipu_addr;
 001200           item.mpu_ipu_wdata           = vif.mpu_ipu_wdata;
 001200           item.mpu_bcast_en            = vif.mpu_bcast_en;
 001200           item.mpu_bcast_addr          = vif.mpu_bcast_addr;
 001200           item.mpu_atomic_add_en       = vif.mpu_atomic_add_en;
 001200           item.act_mpu_ipu_grant       = vif.mpu_ipu_grant;
 001200           item.act_mpu_ipu_rdata       = vif.mpu_ipu_rdata;
 001200           item.act_mpu_ipu_rvalid      = vif.mpu_ipu_rvalid;
 001200           item.act_mpu_dma_grant       = vif.mpu_dma_grant;
 001200           item.act_mpu_dma_rdata       = vif.mpu_dma_rdata;
 001200           item.act_mpu_dma_rvalid      = vif.mpu_dma_rvalid;
 001200           item.act_mpu_bcast_data      = vif.mpu_bcast_data;
 001200           item.act_mpu_bcast_valid     = vif.mpu_bcast_valid;
 001200           item.act_mpu_sec_err         = vif.mpu_sec_err;
 001200           item.act_mpu_ded_err         = vif.mpu_ded_err;
        
 001200           mlu_sram_cg.sample(
 001200             item.subtest_id,
 001200             (item.act_ecc_sec_err | item.act_sp_sec_err | item.act_nram_sec_err | item.act_wram_sec_err | item.act_mpu_sec_err),
 001200             (item.act_ecc_ded_err | item.act_sp_ded_err | item.act_nram_ded_err | item.act_wram_ded_err | item.act_mpu_ded_err),
 001200             item.act_sp_bist_done,
 001200             item.nram_swizzle_en,
 001200             item.act_nram_conflict_stall,
 001200             item.act_wram_weight_valid,
 001200             (|item.act_mpu_bcast_valid)
                  );
        
 001200           seen++;
 001200           ap.write(item);
                end
              end
            endtask
          endclass : mlu_sram_monitor
        
          // ---------------------------------------------------------------------------
          // 6. UVM Agent: mlu_sram_agent
          // ---------------------------------------------------------------------------
          class mlu_sram_agent extends uvm_agent;
%000001     `uvm_component_utils(mlu_sram_agent)
        
            mlu_sram_sequencer sequencer;
            mlu_sram_driver    driver;
            mlu_sram_monitor   monitor;
        
%000001     function new(string name = "mlu_sram_agent", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       sequencer = mlu_sram_sequencer::type_id::create("sequencer", this);
%000001       driver    = mlu_sram_driver::type_id::create("driver", this);
%000001       monitor   = mlu_sram_monitor::type_id::create("monitor", this);
            endfunction
        
%000001     function void connect_phase(uvm_phase phase);
%000001       super.connect_phase(phase);
%000001       driver.seq_item_port.connect(sequencer.seq_item_export);
            endfunction
          endclass : mlu_sram_agent
          // ---------------------------------------------------------------------------
          // 7. UVM Scoreboard: mlu_sram_scoreboard (C++17 DPI-C + SV Golden Reference)
          // ---------------------------------------------------------------------------
          class mlu_sram_scoreboard extends uvm_scoreboard;
%000001     `uvm_component_utils(mlu_sram_scoreboard)
        
            uvm_analysis_imp #(mlu_sram_seq_item, mlu_sram_scoreboard) analysis_export;
        
%000001     int unsigned checked_cycles    = 0;
%000001     int unsigned mismatches        = 0;
%000001     int unsigned sec_verified_cnt  = 0;
%000001     int unsigned ded_verified_cnt  = 0;
%000001     int unsigned bist_verified_cnt = 0;
%000001     int unsigned repair_verified   = 0;
%000001     int unsigned nram_swiz_checks  = 0;
%000001     int unsigned nram_xpose_checks = 0;
%000001     int unsigned wram_pp_checks    = 0;
%000001     int unsigned mpu_bcast_checks  = 0;
%000001     int unsigned mpu_atomic_checks = 0;
        
%000001     function new(string name = "mlu_sram_scoreboard", uvm_component parent = null);
%000001       super.new(name, parent);
%000001       analysis_export = new("analysis_export", this);
            endfunction
        
 001200     function void write(mlu_sram_seq_item item);
 001200       int unsigned exp_syn;
 001200       int unsigned exp_sec;
 001200       int unsigned exp_ded;
 001200       longint unsigned exp_dout;
        
 001200       checked_cycles++;
        
              // 1. Check Standalone (72,64) Hsiao SECDED ECC Codec via C++17 DPI-C Model
 001200       exp_syn  = dpi_ecc_ref_syndrome(item.ecc_err_mask[63:0], {24'd0, item.ecc_err_mask[71:64]});
 001200       exp_sec  = dpi_ecc_ref_sec(item.ecc_err_mask[63:0], {24'd0, item.ecc_err_mask[71:64]});
 001200       exp_ded  = dpi_ecc_ref_ded(item.ecc_err_mask[63:0], {24'd0, item.ecc_err_mask[71:64]});
 001200       exp_dout = dpi_ecc_ref_dout(item.ecc_din, item.ecc_err_mask[63:0], {24'd0, item.ecc_err_mask[71:64]});
        
~001200       if (item.act_ecc_syndrome !== exp_syn[7:0] ||
                  item.act_ecc_sec_err  !== exp_sec[0]   ||
                  item.act_ecc_ded_err  !== exp_ded[0]   ||
%000000           (exp_ded[0] == 1'b0 && item.act_ecc_dout !== exp_dout)) begin
                `uvm_error("ECC_MISMATCH", $sformatf(
                  "Cyc %0d: syn=%h(exp %h) sec=%b(exp %b) ded=%b(exp %b) dout=%h(exp %h)",
                  item.cycle_id, item.act_ecc_syndrome, exp_syn[7:0],
                  item.act_ecc_sec_err, exp_sec[0], item.act_ecc_ded_err, exp_ded[0],
%000000           item.act_ecc_dout, exp_dout))
%000000         mismatches++;
 001200       end else begin
 000776         if (exp_sec[0]) sec_verified_cnt++;
 000776         if (exp_ded[0]) ded_verified_cnt++;
              end
        
              // 2. Check SP-SRAM Read & SEC/DED Fault Injection (Phase 0: cyc 65..192)
 001072       if (item.cycle_id >= 65 && item.cycle_id <= 192 && item.act_sp_rvalid) begin
 000128         int rd_idx = (item.cycle_id - 65) % 64;
 000128         logic [63:0] exp_sp_word = 64'hCAFE_0000_0000_0000 | (64'(rd_idx) * 64'h0101_0101_0101);
 000128         int unsigned sp_sec = dpi_ecc_ref_sec(item.sp_err_mask[63:0], {24'd0, item.sp_err_mask[71:64]});
 000128         int unsigned sp_ded = dpi_ecc_ref_ded(item.sp_err_mask[63:0], {24'd0, item.sp_err_mask[71:64]});
~000128         if (item.act_sp_sec_err !== sp_sec[0] || item.act_sp_ded_err !== sp_ded[0] ||
%000000             (sp_ded[0] == 1'b0 && item.act_sp_rdata !== exp_sp_word)) begin
                  `uvm_error("SP_SRAM_MISMATCH", $sformatf(
                    "Cyc %0d: rdata=%h(exp %h) sec=%b ded=%b",
%000000             item.cycle_id, item.act_sp_rdata, exp_sp_word, item.act_sp_sec_err, item.act_sp_ded_err))
%000000           mismatches++;
 000128         end else begin
 000085           if (sp_sec[0]) sec_verified_cnt++;
 000086           if (sp_ded[0]) ded_verified_cnt++;
                end
              end
        
              // 3. Check Hardware March-C- BIST & Spare-Row Fuse Repair (Phase 1)
~001199       if (item.cycle_id == 404) begin
%000001         if (!item.act_sp_bist_done || item.act_sp_bist_fail) begin
                  `uvm_error("BIST_FAIL", $sformatf("Cyc 404: bist_done=%b bist_fail=%b",
%000000             item.act_sp_bist_done, item.act_sp_bist_fail))
%000000           mismatches++;
%000001         end else begin
%000001           bist_verified_cnt++;
                end
              end
~001199       if (item.cycle_id == 412) begin
%000001         if (!item.act_sp_rvalid || item.act_sp_rdata !== 64'hDEAD_BEEF_1234_5678 ||
%000000             item.act_sp_spare_data !== 64'hDEAD_BEEF_1234_5678) begin
%000000           `uvm_error("REPAIR_FAIL", $sformatf("Cyc 412: spare rdata=%h", item.act_sp_rdata))
%000000           mismatches++;
%000001         end else begin
%000001           repair_verified++;
                end
              end
              // 4. Check NRAM Bank-Conflict vs. XOR Swizzling & 8x8 2D Matrix Transpose (Phase 2)
 001150       if (item.cycle_id >= 450 && item.cycle_id < 500) begin
 000050         bit exp_stall = !item.nram_swizzle_en;
 000050         logic [7:0] exp_grant = item.nram_swizzle_en ? 8'hFF : 8'h01;
~000050         if (item.act_nram_conflict_stall !== exp_stall || item.act_nram_grant !== exp_grant) begin
                  `uvm_error("NRAM_SWIZ_FAIL", $sformatf("Cyc %0d: swiz=%b stall=%b grant=%b",
%000000             item.cycle_id, item.nram_swizzle_en, item.act_nram_conflict_stall, item.act_nram_grant))
%000000           mismatches++;
 000050         end else begin
 000050           nram_swiz_checks++;
                end
              end
~001199       if (item.cycle_id == 562) begin
%000001         if (item.act_nram_rvalid !== 8'hFF) begin
%000000           `uvm_error("NRAM_XPOSE_VALID", "Cyc 562: expected 8-lane transpose read valid")
%000000           mismatches++;
%000001         end else begin
%000008           for (int r = 0; r < 8; r++) begin
~000064             for (int c = 0; c < 8; c++) begin
~000064               if (item.act_nram_rdata[r][c*8 +: 8] !== 8'((c << 4) | r)) begin
                        `uvm_error("NRAM_XPOSE_DATA", $sformatf("r=%0d c=%0d got=%h",
%000000                   r, c, item.act_nram_rdata[r][c*8 +: 8]))
%000000                 mismatches++;
                      end
                    end
                  end
%000001           nram_xpose_checks++;
                end
              end
        
              // 5. Check WRAM Ping-Pong 256-bit TFU Read & Cambricon-S Sparse Meta (Phase 3)
 001133       if (item.cycle_id >= 683 && item.cycle_id < 750 && item.act_wram_weight_valid) begin
 000067         int rd_row = (item.cycle_id - 683) % 8;
 000067         logic [31:0] exp_meta = 32'hE4E4_0000 | 32'(rd_row);
~000067         if (item.act_wram_meta_o !== exp_meta) begin
                  `uvm_error("WRAM_META_FAIL", $sformatf("Cyc %0d: meta=%h exp=%h",
%000000             item.cycle_id, item.act_wram_meta_o, exp_meta))
%000000           mismatches++;
                end
~000066         if (item.cycle_id != 692) begin
 000264           for (int b = 0; b < 4; b++) begin
 000264             logic [63:0] exp_w = 64'hB100_0000_0000_0000 | (64'(rd_row) << 16) | 64'(b);
~000264             if (item.act_wram_weight_vec[b*64 +: 64] !== exp_w) begin
                      `uvm_error("WRAM_VEC_FAIL", $sformatf("Cyc %0d b=%0d got=%h exp=%h",
%000000                 item.cycle_id, b, item.act_wram_weight_vec[b*64 +: 64], exp_w))
%000000               mismatches++;
                    end
                  end
                end
 000067         wram_pp_checks++;
              end
        
              // 6. Check MPU Shared SRAM 1-to-4 Broadcast & Atomic AllReduce (Phase 4)
 001181       if (item.cycle_id >= 856 && item.cycle_id < 875 && (|item.act_mpu_bcast_valid)) begin
 000019         logic [255:0] exp_bcast = {
 000019           64'hC000_0000_0000_0004, 64'hC000_0000_0000_0003,
 000019           64'hC000_0000_0000_0002, 64'hC000_0000_0000_0001
                };
~000019         if (item.act_mpu_bcast_valid !== 4'b1111 || item.act_mpu_bcast_data !== exp_bcast) begin
%000000           `uvm_error("MPU_BCAST_FAIL", $sformatf("Cyc %0d: bcast=%h", item.cycle_id, item.act_mpu_bcast_data))
%000000           mismatches++;
 000019         end else begin
 000019           mpu_bcast_checks++;
                end
              end
~001199       if (item.cycle_id == 886) begin
%000001         if (!item.act_mpu_ipu_rvalid[0] || item.act_mpu_ipu_rdata[0] !== 64'd200) begin
                  `uvm_error("MPU_ATOMIC_FAIL", $sformatf("Cyc 886: atomic rdata=%0d exp=200",
%000000             item.act_mpu_ipu_rdata[0]))
%000000           mismatches++;
%000001         end else begin
%000001           mpu_atomic_checks++;
                end
              end
            endfunction
          endclass : mlu_sram_scoreboard
        
          // ---------------------------------------------------------------------------
          // 8. UVM Environment & Test
          // ---------------------------------------------------------------------------
          class mlu_sram_env extends uvm_env;
%000001     `uvm_component_utils(mlu_sram_env)
            mlu_sram_agent      agent;
            mlu_sram_scoreboard scoreboard;
%000001     function new(string name = "mlu_sram_env", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       agent      = mlu_sram_agent::type_id::create("agent", this);
%000001       scoreboard = mlu_sram_scoreboard::type_id::create("scoreboard", this);
            endfunction
%000001     function void connect_phase(uvm_phase phase);
%000001       super.connect_phase(phase);
%000001       agent.monitor.ap.connect(scoreboard.analysis_export);
            endfunction
          endclass : mlu_sram_env
        
          class mlu_sram_nram_wram_test extends uvm_test;
%000002     `uvm_component_utils(mlu_sram_nram_wram_test)
            mlu_sram_env env;
%000001     function new(string name = "mlu_sram_nram_wram_test", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       env = mlu_sram_env::type_id::create("env", this);
            endfunction
%000001     task run_phase(uvm_phase phase);
%000001       mlu_sram_sequence seq = mlu_sram_sequence::type_id::create("seq");
%000001       phase.raise_objection(this);
%000001       seq.start(env.agent.sequencer);
%000001       phase.drop_objection(this);
            endtask
%000001     function void report_phase(uvm_phase phase);
%000001       real func_cov = env.agent.monitor.mlu_sram_cg.get_inst_coverage();
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
%000001                       (env.scoreboard.mpu_bcast_checks >= 15) &&
                              (env.scoreboard.mpu_atomic_checks > 0);
%000001       super.report_phase(phase);
%000001       dpi_sram_set_status(pass_gate ? 0 : 1);
%000001       if (!pass_gate) begin
                `uvm_fatal("UVM_SRAM_FAIL", $sformatf("Suite 1 gate failed: mismatches=%0d cov=%0.2f%%",
%000000           env.scoreboard.mismatches, func_cov))
%000001       end else begin
                `uvm_info("UVM_SRAM_PASS", $sformatf(
                  "SUITE 1 PASS: cycles=%0d dpi_calls=%0d sec=%0d ded=%0d bist=%0d repair=%0d swiz=%0d xpose=%0d wram=%0d bcast=%0d atomic=%0d cov=%0.2f%%",
                  env.scoreboard.checked_cycles, dpi_sram_get_calls(),
                  env.scoreboard.sec_verified_cnt, env.scoreboard.ded_verified_cnt,
                  env.scoreboard.bist_verified_cnt, env.scoreboard.repair_verified,
                  env.scoreboard.nram_swiz_checks, env.scoreboard.nram_xpose_checks,
                  env.scoreboard.wram_pp_checks, env.scoreboard.mpu_bcast_checks,
%000001           env.scoreboard.mpu_atomic_checks, func_cov), UVM_LOW)
              end
            endfunction
          endclass : mlu_sram_nram_wram_test
        
        endpackage : mlu_sram_nram_wram_uvm_pkg
        
        `endif // MLU_SRAM_NRAM_WRAM_UVM_PKG_SV
        
