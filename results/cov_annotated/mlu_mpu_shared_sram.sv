//      // verilator_coverage annotation
        // =============================================================================
        // File: rtl/mlu_mpu_shared_sram.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: Cambricon MPU Memory Core Cluster-Level Shared SRAM:
        //              - 8 Banks x 256 Rows x 64-bit with (72,64) Hsiao SECDED ECC
        //              - Crossbar Arbitration across 4 IPU Core Ports + 1 MFU Global DMA Port
        //              - Single-Cycle 256-bit Multi-Cast Broadcast to all 4 IPU Cores
        //                simultaneously (OP_MPU_BCAST_SRAM)
        //              - In-Memory Atomic Accumulation (OP_MPU_ALLREDUCE)
        // =============================================================================
        `include "mlu_pkg.sv"
        
        module mlu_mpu_shared_sram #(
          parameter int unsigned NUM_IPUS   = 4,
          parameter int unsigned NUM_BANKS  = 8,
          parameter int unsigned BANK_DEPTH = 256,
          parameter int unsigned DATA_W     = 64,
          parameter int unsigned ECC_W      = 72,
          parameter int unsigned BANK_SEL_W = $clog2(NUM_BANKS),
          parameter int unsigned ROW_ADDR_W = $clog2(BANK_DEPTH),
          parameter int unsigned ADDR_W     = BANK_SEL_W + ROW_ADDR_W
        )(
 001203   input  logic                                clk,
%000001   input  logic                                rst_n,
        
          // 4 IPU Core Request & Response Ports
%000002   input  logic [NUM_IPUS-1:0]                 ipu_req_valid_i,
%000002   input  logic [NUM_IPUS-1:0]                 ipu_req_we_i,
%000004   input  logic [NUM_IPUS-1:0][ADDR_W-1:0]     ipu_req_addr_i,
%000004   input  logic [NUM_IPUS-1:0][DATA_W-1:0]     ipu_req_wdata_i,
%000002   output logic [NUM_IPUS-1:0]                 ipu_req_grant_o,
~000012   output logic [NUM_IPUS-1:0][DATA_W-1:0]     ipu_resp_rdata_o,
%000001   output logic [NUM_IPUS-1:0]                 ipu_resp_valid_o,
        
          // 1 MFU Global DMA Port
%000006   input  logic                                dma_req_valid_i,
%000003   input  logic                                dma_req_we_i,
~000017   input  logic [ADDR_W-1:0]                   dma_req_addr_i,
~000012   input  logic [DATA_W-1:0]                   dma_req_wdata_i,
%000006   output logic                                dma_req_grant_o,
~000012   output logic [DATA_W-1:0]                   dma_resp_rdata_o,
%000003   output logic                                dma_resp_valid_o,
        
          // Single-Cycle 256-Bit Multi-Cast Broadcast Interface (OP_MPU_BCAST_SRAM)
~000036   input  logic                                bcast_en_i,
~000010   input  logic [ADDR_W-1:0]                   bcast_addr_i,
~000012   output logic [255:0]                        bcast_data_o,
~000036   output logic [NUM_IPUS-1:0]                 bcast_valid_o,
        
          // In-Memory Atomic Reduction Mode (OP_MPU_ALLREDUCE)
%000004   input  logic                                atomic_add_en_i,
        
          // ECC Fault Injection & Error Status
%000001   input  logic [BANK_SEL_W-1:0]               err_inject_bank_i,
%000001   input  logic [ECC_W-1:0]                    err_inject_mask_i,
%000001   output logic                                sec_err_o,
%000000   output logic                                ded_err_o
        );
        
          // ---------------------------------------------------------------------------
          // 1. Multi-Port Request Extraction & Bank Arbitration
          //    Priority: Broadcast > MFU Global DMA > IPU Core 0..3
          // ---------------------------------------------------------------------------
~000037   logic [NUM_BANKS-1:0]                 bank_req_en;
%000003   logic [NUM_BANKS-1:0]                 bank_req_we;
~000037   logic [NUM_BANKS-1:0][ROW_ADDR_W-1:0] bank_req_row;
          logic [NUM_BANKS-1:0][DATA_W-1:0]     bank_req_wdata_raw;
        
%000000   logic                                 bcast_half_sel;
~000010   logic [ROW_ADDR_W-1:0]                bcast_row_addr;
        
          assign bcast_row_addr = bcast_addr_i[ROW_ADDR_W-1:0];
          assign bcast_half_sel = bcast_addr_i[ROW_ADDR_W];
        
 000682   always_comb begin
 000682     bank_req_en        = '0;
 000682     bank_req_we        = '0;
 000682     bank_req_row       = '0;
 000682     bank_req_wdata_raw = '0;
 000682     dma_req_grant_o    = 1'b0;
 000682     ipu_req_grant_o    = '0;
        
 000670     if (bcast_en_i) begin
              // Broadcast reads 4 consecutive 64-bit banks (256-bit total) in parallel
 000288       for (int k = 0; k < 4; k++) begin
 000288         bank_req_en[{bcast_half_sel, 2'(k)}]  = 1'b1;
 000288         bank_req_we[{bcast_half_sel, 2'(k)}]  = 1'b0;
 000288         bank_req_row[{bcast_half_sel, 2'(k)}] = bcast_row_addr;
              end
 000670     end else begin
              // MFU Global DMA Port
~000565       if (dma_req_valid_i) begin
~000108         bank_req_en[dma_req_addr_i[ADDR_W-1:ROW_ADDR_W]]        = 1'b1;
~000108         bank_req_we[dma_req_addr_i[ADDR_W-1:ROW_ADDR_W]]        = dma_req_we_i;
~000108         bank_req_row[dma_req_addr_i[ADDR_W-1:ROW_ADDR_W]]       = dma_req_addr_i[ROW_ADDR_W-1:0];
~000108         bank_req_wdata_raw[dma_req_addr_i[ADDR_W-1:ROW_ADDR_W]] = dma_req_wdata_i;
~000108         dma_req_grant_o                                         = 1'b1;
              end
              // 4 IPU Core Ports
 002680       for (int i = 0; i < NUM_IPUS; i++) begin
~002680         if (ipu_req_valid_i[i]) begin
~000018           if (!bank_req_en[ipu_req_addr_i[i][ADDR_W-1:ROW_ADDR_W]]) begin
~000018             bank_req_en[ipu_req_addr_i[i][ADDR_W-1:ROW_ADDR_W]]        = 1'b1;
~000018             bank_req_we[ipu_req_addr_i[i][ADDR_W-1:ROW_ADDR_W]]        = ipu_req_we_i[i];
~000018             bank_req_row[ipu_req_addr_i[i][ADDR_W-1:ROW_ADDR_W]]       = ipu_req_addr_i[i][ROW_ADDR_W-1:0];
~000018             bank_req_wdata_raw[ipu_req_addr_i[i][ADDR_W-1:ROW_ADDR_W]] = ipu_req_wdata_i[i];
~000018             ipu_req_grant_o[i]                                         = 1'b1;
                  end
                end
              end
            end
          end
          // ---------------------------------------------------------------------------
          // 2. In-Memory Atomic Accumulation & 8 Physical SRAM Macro Banks
          // ---------------------------------------------------------------------------
          logic [NUM_BANKS-1:0][DATA_W-1:0]     bank_eff_wdata;
          logic [NUM_BANKS-1:0][DATA_W-1:0]     bank_rdata;
~000036   logic [NUM_BANKS-1:0]                 bank_rvalid;
%000001   logic [NUM_BANKS-1:0]                 bank_sec_err;
%000000   logic [NUM_BANKS-1:0]                 bank_ded_err;
%000001   logic [NUM_BANKS-1:0][7:0]            bank_syndrome;
%000000   logic [NUM_BANKS-1:0]                 bank_bist_done;
%000000   logic [NUM_BANKS-1:0]                 bank_bist_fail;
%000000   logic [NUM_BANKS-1:0][ROW_ADDR_W-1:0] bank_bist_faddr;
          logic [NUM_BANKS-1:0][DATA_W-1:0]     bank_spare_data;
%000000   logic [NUM_BANKS-1:0][ROW_ADDR_W-1:0] bank_scrub_addr;
%000001   logic [NUM_BANKS-1:0]                 bank_pwr_ready;
        
          genvar b;
          generate
 000025     for (b = 0; b < NUM_BANKS; b++) begin : gen_shared_sram_banks
%000001       logic [ECC_W-1:0]  bank_err_mask;
              logic [DATA_W-1:0] atomic_acc_cache [0:15];
        
              assign bank_err_mask = (err_inject_bank_i == BANK_SEL_W'(b)) ? err_inject_mask_i : '0;
        
              assign bank_eff_wdata[b] = atomic_add_en_i ?
                                         (atomic_acc_cache[bank_req_row[b][3:0]] + bank_req_wdata_raw[b]) :
                                         bank_req_wdata_raw[b];
        
 009624       always_ff @(posedge clk) begin
 009603         if (bank_req_en[b] && bank_req_we[b]) begin
 000025           atomic_acc_cache[bank_req_row[b][3:0]] <= bank_eff_wdata[b];
                end
              end
        
              mlu_sram_sp_macro #(
                .DEPTH      (BANK_DEPTH),
                .DATA_W     (DATA_W),
                .ECC_W      (ECC_W),
                .ADDR_W     (ROW_ADDR_W),
                .BIST_DEPTH (16)
              ) u_mpu_bank (
                .clk                 (clk),
                .rst_n               (rst_n),
                .req_en_i            (bank_req_en[b]),
                .req_we_i            (bank_req_we[b]),
                .req_addr_i          (bank_req_row[b]),
                .req_wdata_i         (bank_eff_wdata[b]),
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
          // 3. Read Response & Multi-Cast Broadcast Pipeline
          // ---------------------------------------------------------------------------
%000001   logic [NUM_IPUS-1:0]                 ipu_rd_valid_q;
%000001   logic [NUM_IPUS-1:0][BANK_SEL_W-1:0] ipu_rd_bank_q;
%000003   logic                                dma_rd_valid_q;
%000001   logic [BANK_SEL_W-1:0]               dma_rd_bank_q;
~000036   logic                                bcast_valid_q;
%000000   logic                                bcast_half_q;
        
 001203   always_ff @(posedge clk or negedge rst_n) begin
~001200     if (!rst_n) begin
%000003       ipu_rd_valid_q <= '0;
%000003       ipu_rd_bank_q  <= '0;
%000003       dma_rd_valid_q <= 1'b0;
%000003       dma_rd_bank_q  <= '0;
%000003       bcast_valid_q  <= 1'b0;
%000003       bcast_half_q   <= 1'b0;
 001200     end else begin
 001200       bcast_valid_q  <= bcast_en_i;
 001200       bcast_half_q   <= bcast_half_sel;
 001200       dma_rd_valid_q <= dma_req_valid_i && !dma_req_we_i && dma_req_grant_o;
 001200       dma_rd_bank_q  <= dma_req_addr_i[ADDR_W-1:ROW_ADDR_W];
 004800       for (int i = 0; i < NUM_IPUS; i++) begin
 004800         ipu_rd_valid_q[i] <= ipu_req_valid_i[i] && !ipu_req_we_i[i] && ipu_req_grant_o[i];
 004800         ipu_rd_bank_q[i]  <= ipu_req_addr_i[i][ADDR_W-1:ROW_ADDR_W];
              end
            end
          end
        
%000001   always_comb begin
%000004     for (int i = 0; i < NUM_IPUS; i++) begin
%000004       ipu_resp_rdata_o[i] = bank_rdata[ipu_rd_bank_q[i]];
            end
%000001     dma_resp_rdata_o = bank_rdata[dma_rd_bank_q];
%000004     for (int k = 0; k < 4; k++) begin
%000004       bcast_data_o[k*DATA_W +: DATA_W] = bank_rdata[{bcast_half_q, 2'(k)}];
            end
          end
        
          assign ipu_resp_valid_o = ipu_rd_valid_q;
          assign dma_resp_valid_o = dma_rd_valid_q;
          assign bcast_valid_o    = {NUM_IPUS{bcast_valid_q}};
          assign sec_err_o        = |(bank_sec_err & bank_rvalid);
          assign ded_err_o        = |(bank_ded_err & bank_rvalid);
        
%000000   logic unused_mpu_sram_diag;
          assign unused_mpu_sram_diag = &{1'b0, bank_syndrome, bank_bist_done,
                                          bank_bist_fail, bank_bist_faddr,
                                          bank_spare_data, bank_scrub_addr,
                                          bank_pwr_ready};
        
        endmodule : mlu_mpu_shared_sram
        
