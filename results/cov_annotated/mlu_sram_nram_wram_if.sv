//      // verilator_coverage annotation
        // =============================================================================
        // File: uvm_tb/uvm_sram_nram_wram/mlu_sram_nram_wram_if.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: SystemVerilog Interface & DUT Wrapper for Accellera UVM 2020.3.1
        //              Suite 1: mlu_sram_secded_ecc, mlu_sram_sp_macro,
        //              mlu_nram_banked_scratchpad, mlu_wram_weight_buffer,
        //              and mlu_mpu_shared_sram.
        // =============================================================================
        `ifndef MLU_SRAM_NRAM_WRAM_IF_SV
        `define MLU_SRAM_NRAM_WRAM_IF_SV
        
        `timescale 1ns/1ps
        `include "mlu_pkg.sv"
        
 001203 interface mlu_sram_nram_wram_if (input logic clk);
          import mlu_pkg::*;
        
%000001   logic        rst_n       = 1'b0;
~001200   logic        cycle_valid = 1'b0;
%000001   int unsigned cycle_id    = 0;
%000001   int unsigned subtest_id  = 0;
        
          // 1. mlu_sram_secded_ecc Signals
~000328   logic [63:0] ecc_din      = 64'd0;
 000916   logic [71:0] ecc_codeword;
~000062   logic [71:0] ecc_err_mask = 72'd0;
 000327   logic [63:0] ecc_dout;
 000281   logic [7:0]  ecc_syndrome;
 000353   logic        ecc_sec_err;
 000353   logic        ecc_ded_err;
        
          // 2. mlu_sram_sp_macro Signals
%000003   logic        sp_req_en          = 1'b0;
%000003   logic        sp_req_we          = 1'b0;
~000097   logic [7:0]  sp_req_addr        = 8'd0;
~000033   logic [63:0] sp_req_wdata       = 64'd0;
%000002   logic [7:0]  sp_req_wmask       = 8'hFF;
~000083   logic [63:0] sp_rdata;
%000002   logic        sp_rvalid;
~000011   logic [71:0] sp_err_mask        = 72'd0;
 000043   logic        sp_sec_err;
 000043   logic        sp_ded_err;
 000062   logic [7:0]  sp_syndrome;
%000002   logic        sp_bist_en         = 1'b0;
%000001   logic        sp_bist_done;
%000001   logic        sp_bist_fail;
~000022   logic [7:0]  sp_bist_fail_addr;
%000001   logic        sp_repair_en       = 1'b0;
%000001   logic [7:0]  sp_repair_bad_addr = 8'h2A;
%000001   logic [63:0] sp_repair_spare_data;
%000001   logic        sp_scrub_en        = 1'b0;
%000003   logic [7:0]  sp_scrub_addr;
%000001   logic        sp_slp             = 1'b0;
%000001   logic        sp_dslp            = 1'b0;
%000001   logic        sp_sd              = 1'b0;
%000002   logic        sp_pwr_ready;
        
          // 3. mlu_nram_banked_scratchpad Signals
~000043   logic [7:0]       nram_req_valid = '0;
~000043   logic [7:0]       nram_req_we    = '0;
~000044   logic [7:0][9:0]  nram_req_addr  = '0;
%000001   logic [7:0][63:0] nram_req_wdata = '0;
 000063   logic [7:0]       nram_req_grant;
          logic [7:0][63:0] nram_resp_rdata;
 000039   logic [7:0]       nram_resp_valid;
~000058   logic             nram_swizzle_en   = 1'b0;
%000001   logic             nram_transpose_en = 1'b0;
 000067   logic             nram_conflict_stall;
~000056   logic [31:0]      nram_conflict_cnt;
%000002   logic [2:0]       nram_err_bank = 3'd0;
%000001   logic [71:0]      nram_err_mask = 72'd0;
%000001   logic             nram_sec_err;
%000001   logic             nram_ded_err;
        
          // 4. mlu_wram_weight_buffer Signals
~000038   logic         wram_pp_sel     = 1'b0;
%000001   logic         wram_dma_we     = 1'b0;
~000050   logic [8:0]   wram_dma_addr   = 9'd0;
~000050   logic [63:0]  wram_dma_wdata  = 64'd0;
%000009   logic         wram_meta_we    = 1'b0;
~000038   logic [31:0]  wram_meta_wdata = 32'd0;
~000038   logic         wram_tfu_rd_en  = 1'b0;
~000087   logic [6:0]   wram_tfu_rd_addr= 7'd0;
~000165   logic [255:0] wram_tfu_weight_vec;
~000053   logic [31:0]  wram_tfu_meta_o;
 000038   logic         wram_tfu_weight_valid;
%000001   logic [1:0]   wram_err_bank   = 2'd0;
%000001   logic [71:0]  wram_err_mask   = 72'd0;
%000001   logic         wram_sec_err;
%000001   logic         wram_ded_err;
          // 5. mlu_mpu_shared_sram Signals
%000002   logic [3:0]       mpu_ipu_valid       = '0;
%000002   logic [3:0]       mpu_ipu_we          = '0;
%000002   logic [3:0][10:0] mpu_ipu_addr        = '0;
%000002   logic [3:0][63:0] mpu_ipu_wdata       = '0;
%000002   logic [3:0]       mpu_ipu_grant;
%000002   logic [3:0][63:0] mpu_ipu_rdata;
%000001   logic [3:0]       mpu_ipu_rvalid;
%000001   logic             mpu_dma_valid       = 1'b0;
%000001   logic             mpu_dma_we          = 1'b0;
%000001   logic [10:0]      mpu_dma_addr        = 11'd0;
%000001   logic [63:0]      mpu_dma_wdata       = 64'd0;
%000001   logic             mpu_dma_grant;
%000002   logic [63:0]      mpu_dma_rdata;
%000000   logic             mpu_dma_rvalid;
~000036   logic             mpu_bcast_en        = 1'b0;
%000002   logic [10:0]      mpu_bcast_addr      = 11'd0;
%000004   logic [255:0]     mpu_bcast_data;
 000036   logic [3:0]       mpu_bcast_valid;
%000001   logic             mpu_atomic_add_en   = 1'b0;
%000001   logic [2:0]       mpu_err_bank        = 3'd0;
%000001   logic [71:0]      mpu_err_mask        = 72'd0;
%000001   logic             mpu_sec_err;
%000000   logic             mpu_ded_err;
        endinterface : mlu_sram_nram_wram_if
        
        module mlu_sram_nram_wram_dut_wrap (
          mlu_sram_nram_wram_if bus
        );
          mlu_sram_secded_ecc u_dut_ecc (
            .data_i            (bus.ecc_din),
            .codeword_o        (bus.ecc_codeword),
            .codeword_i        (bus.ecc_codeword),
            .err_inject_mask_i (bus.ecc_err_mask),
            .data_o            (bus.ecc_dout),
            .syndrome_o        (bus.ecc_syndrome),
            .sec_err_o         (bus.ecc_sec_err),
            .ded_err_o         (bus.ecc_ded_err)
          );
        
          mlu_sram_sp_macro #(
            .DEPTH      (256),
            .DATA_W     (64),
            .ECC_W      (72),
            .ADDR_W     (8),
            .BIST_DEPTH (16)
          ) u_dut_sp_macro (
            .clk                 (bus.clk),
            .rst_n               (bus.rst_n),
            .req_en_i            (bus.sp_req_en),
            .req_we_i            (bus.sp_req_we),
            .req_addr_i          (bus.sp_req_addr),
            .req_wdata_i         (bus.sp_req_wdata),
            .req_wmask_i         (bus.sp_req_wmask),
            .rdata_o             (bus.sp_rdata),
            .rvalid_o            (bus.sp_rvalid),
            .err_inject_mask_i   (bus.sp_err_mask),
            .sec_err_o           (bus.sp_sec_err),
            .ded_err_o           (bus.sp_ded_err),
            .syndrome_o          (bus.sp_syndrome),
            .bist_en_i           (bus.sp_bist_en),
            .bist_done_o         (bus.sp_bist_done),
            .bist_fail_o         (bus.sp_bist_fail),
            .bist_fail_addr_o    (bus.sp_bist_fail_addr),
            .repair_en_i         (bus.sp_repair_en),
            .repair_bad_addr_i   (bus.sp_repair_bad_addr),
            .repair_spare_data_q (bus.sp_repair_spare_data),
            .scrub_en_i          (bus.sp_scrub_en),
            .scrub_addr_o        (bus.sp_scrub_addr),
            .slp_i               (bus.sp_slp),
            .dslp_i              (bus.sp_dslp),
            .sd_i                (bus.sp_sd),
            .pwr_ready_o         (bus.sp_pwr_ready)
          );
        
          mlu_nram_banked_scratchpad u_dut_nram (
            .clk               (bus.clk),
            .rst_n             (bus.rst_n),
            .req_valid_i       (bus.nram_req_valid),
            .req_we_i          (bus.nram_req_we),
            .req_addr_i        (bus.nram_req_addr),
            .req_wdata_i       (bus.nram_req_wdata),
            .req_grant_o       (bus.nram_req_grant),
            .resp_rdata_o      (bus.nram_resp_rdata),
            .resp_valid_o      (bus.nram_resp_valid),
            .swizzle_en_i      (bus.nram_swizzle_en),
            .transpose_en_i    (bus.nram_transpose_en),
            .conflict_stall_o  (bus.nram_conflict_stall),
            .conflict_cnt_o    (bus.nram_conflict_cnt),
            .err_inject_bank_i (bus.nram_err_bank),
            .err_inject_mask_i (bus.nram_err_mask),
            .sec_err_o         (bus.nram_sec_err),
            .ded_err_o         (bus.nram_ded_err)
          );
          mlu_wram_weight_buffer u_dut_wram (
            .clk                 (bus.clk),
            .rst_n               (bus.rst_n),
            .ping_pong_sel_i     (bus.wram_pp_sel),
            .dma_we_i            (bus.wram_dma_we),
            .dma_addr_i          (bus.wram_dma_addr),
            .dma_wdata_i         (bus.wram_dma_wdata),
            .sparse_meta_we_i    (bus.wram_meta_we),
            .sparse_meta_wdata_i (bus.wram_meta_wdata),
            .tfu_rd_en_i         (bus.wram_tfu_rd_en),
            .tfu_rd_addr_i       (bus.wram_tfu_rd_addr),
            .tfu_weight_vec_o    (bus.wram_tfu_weight_vec),
            .tfu_sparse_meta_o   (bus.wram_tfu_meta_o),
            .tfu_weight_valid_o  (bus.wram_tfu_weight_valid),
            .err_inject_bank_i   (bus.wram_err_bank),
            .err_inject_mask_i   (bus.wram_err_mask),
            .sec_err_o           (bus.wram_sec_err),
            .ded_err_o           (bus.wram_ded_err)
          );
        
          mlu_mpu_shared_sram u_dut_mpu_sram (
            .clk               (bus.clk),
            .rst_n             (bus.rst_n),
            .ipu_req_valid_i   (bus.mpu_ipu_valid),
            .ipu_req_we_i      (bus.mpu_ipu_we),
            .ipu_req_addr_i    (bus.mpu_ipu_addr),
            .ipu_req_wdata_i   (bus.mpu_ipu_wdata),
            .ipu_req_grant_o   (bus.mpu_ipu_grant),
            .ipu_resp_rdata_o  (bus.mpu_ipu_rdata),
            .ipu_resp_valid_o  (bus.mpu_ipu_rvalid),
            .dma_req_valid_i   (bus.mpu_dma_valid),
            .dma_req_we_i      (bus.mpu_dma_we),
            .dma_req_addr_i    (bus.mpu_dma_addr),
            .dma_req_wdata_i   (bus.mpu_dma_wdata),
            .dma_req_grant_o   (bus.mpu_dma_grant),
            .dma_resp_rdata_o  (bus.mpu_dma_rdata),
            .dma_resp_valid_o  (bus.mpu_dma_rvalid),
            .bcast_en_i        (bus.mpu_bcast_en),
            .bcast_addr_i      (bus.mpu_bcast_addr),
            .bcast_data_o      (bus.mpu_bcast_data),
            .bcast_valid_o     (bus.mpu_bcast_valid),
            .atomic_add_en_i   (bus.mpu_atomic_add_en),
            .err_inject_bank_i (bus.mpu_err_bank),
            .err_inject_mask_i (bus.mpu_err_mask),
            .sec_err_o         (bus.mpu_sec_err),
            .ded_err_o         (bus.mpu_ded_err)
          );
        endmodule : mlu_sram_nram_wram_dut_wrap
        
        `endif // MLU_SRAM_NRAM_WRAM_IF_SV
        
