//      // verilator_coverage annotation
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
 038592   input  logic                clk,
~000064   input  logic                rst_n,
        
          // Functional SRAM Port
 000809   input  logic                req_en_i,
~000465   input  logic                req_we_i,
~000850   input  logic [ADDR_W-1:0]   req_addr_i,
~000695   input  logic [DATA_W-1:0]   req_wdata_i,
~000064   input  logic [DATA_W/8-1:0] req_wmask_i,
~000231   output logic [DATA_W-1:0]   rdata_o,
 000468   output logic                rvalid_o,
        
          // ECC Diagnostics & Fault Injection
~000032   input  logic [ECC_W-1:0]    err_inject_mask_i,
~000044   output logic                sec_err_o,
~000043   output logic                ded_err_o,
~000062   output logic [7:0]          syndrome_o,
        
          // Hardware March-C- BIST Interface
%000008   input  logic                bist_en_i,
%000001   output logic                bist_done_o,
%000001   output logic                bist_fail_o,
~000022   output logic [ADDR_W-1:0]   bist_fail_addr_o,
        
          // Fuse-Programmable Spare-Row Redundancy Repair Interface
%000008   input  logic                repair_en_i,
%000001   input  logic [ADDR_W-1:0]   repair_bad_addr_i,
%000001   output logic [DATA_W-1:0]   repair_spare_data_q,
        
          // Autonomous Background ECC Scrubbing Interface
%000008   input  logic                scrub_en_i,
%000003   output logic [ADDR_W-1:0]   scrub_addr_o,
        
          // Low-Power Control & Status
%000008   input  logic                slp_i,
%000008   input  logic                dslp_i,
%000008   input  logic                sd_i,
~000064   output logic                pwr_ready_o
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
        
%000002   pwr_state_e pwr_state_q, pwr_state_d;
        
 038656   always_comb begin
 038656     pwr_state_d = pwr_state_q;
%000005     if (sd_i) begin
%000005       pwr_state_d = PWR_SHUTDOWN;
%000005     end else if (dslp_i) begin
%000005       pwr_state_d = PWR_DEEP_SLEEP;
~038656     end else if (slp_i) begin
%000005       pwr_state_d = PWR_LIGHT_SLEEP;
 038656     end else begin
 038656       case (pwr_state_q)
%000003         PWR_DEEP_SLEEP, PWR_SHUTDOWN: pwr_state_d = PWR_WAKEUP;
%000001         PWR_LIGHT_SLEEP, PWR_WAKEUP:  pwr_state_d = PWR_ACTIVE;
 038656         default:                      pwr_state_d = PWR_ACTIVE;
              endcase
            end
          end
        
 038592   always_ff @(posedge clk or negedge rst_n) begin
 038400     if (!rst_n) pwr_state_q <= PWR_ACTIVE;
 038400     else        pwr_state_q <= pwr_state_d;
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
        
%000006   bist_state_e       bist_state_q;
~000078   logic [ADDR_W-1:0] bist_addr_q;
~000127   logic              bist_sub_q; // 0 = Read cycle, 1 = Check & Write cycle
 038592   always_ff @(posedge clk or negedge rst_n) begin
 000192     if (!rst_n) begin
 000192       bist_state_q     <= BIST_IDLE;
 000192       bist_addr_q      <= '0;
 000192       bist_sub_q       <= 1'b0;
 000192       bist_done_o      <= 1'b0;
 000192       bist_fail_o      <= 1'b0;
 000192       bist_fail_addr_o <= '0;
 038400     end else if (!bist_en_i) begin
 038400       bist_state_q     <= BIST_IDLE;
 038400       bist_addr_q      <= '0;
 038400       bist_sub_q       <= 1'b0;
 038400       bist_done_o      <= 1'b0;
 038400       bist_fail_o      <= 1'b0;
 038400       bist_fail_addr_o <= '0;
~000315     end else if (pwr_ready_o) begin
~000315       case (bist_state_q)
%000002         BIST_IDLE: begin
%000002           bist_state_q <= BIST_M0;
%000002           bist_addr_q  <= '0;
%000002           bist_sub_q   <= 1'b0;
                end
~000032         BIST_M0: begin
~000030           if (bist_addr_q == BIST_LAST_ADDR) begin
%000002             bist_state_q <= BIST_M1;
%000002             bist_addr_q  <= '0;
%000002             bist_sub_q   <= 1'b0;
~000030           end else begin
~000030             bist_addr_q  <= bist_addr_q + 1'b1;
                  end
                end
~000160         BIST_M1, BIST_M2, BIST_M5: begin
~000080           if (!bist_sub_q) begin
~000080             bist_sub_q <= 1'b1;
~000080           end else begin
~000048             if ((rdata_o != ((bist_state_q == BIST_M2) ? {DATA_W{1'b1}} : {DATA_W{1'b0}})) || ded_err_o) begin
~000032               bist_fail_o      <= 1'b1;
~000032               bist_fail_addr_o <= bist_addr_q;
                    end
~000080             bist_sub_q <= 1'b0;
~000075             if (bist_addr_q == BIST_LAST_ADDR) begin
%000002               if (bist_state_q == BIST_M1) begin
%000002                 bist_state_q <= BIST_M2;
%000002                 bist_addr_q  <= '0;
%000002               end else if (bist_state_q == BIST_M2) begin
%000002                 bist_state_q <= BIST_M3;
%000002                 bist_addr_q  <= BIST_LAST_ADDR;
%000001               end else begin
%000001                 bist_state_q <= BIST_DONE;
                      end
~000075             end else begin
~000075               bist_addr_q <= bist_addr_q + 1'b1;
                    end
                  end
                end
~000093         BIST_M3, BIST_M4: begin
~000047           if (!bist_sub_q) begin
~000047             bist_sub_q <= 1'b1;
~000046           end else begin
~000032             if ((rdata_o != ((bist_state_q == BIST_M4) ? {DATA_W{1'b1}} : {DATA_W{1'b0}})) || ded_err_o) begin
~000014               bist_fail_o      <= 1'b1;
~000014               bist_fail_addr_o <= bist_addr_q;
                    end
~000046             bist_sub_q <= 1'b0;
~000044             if (bist_addr_q == '0) begin
%000002               bist_state_q <= (bist_state_q == BIST_M3) ? BIST_M4 : BIST_M5;
%000002               bist_addr_q  <= (bist_state_q == BIST_M3) ? BIST_LAST_ADDR : '0;
~000044             end else begin
~000044               bist_addr_q  <= bist_addr_q - 1'b1;
                    end
                  end
                end
~000028         BIST_DONE: begin
~000028           bist_done_o <= 1'b1;
                end
%000000         default: bist_state_q <= BIST_IDLE;
              endcase
            end
          end
          // ---------------------------------------------------------------------------
          // 3. Autonomous Background ECC Scrubbing Pointer
          // ---------------------------------------------------------------------------
%000003   logic [ADDR_W-1:0] scrub_ptr_q;
%000006   logic              scrub_wb_phase_q;
        
 038592   always_ff @(posedge clk or negedge rst_n) begin
 000192     if (!rst_n) begin
 000192       scrub_ptr_q      <= '0;
 000192       scrub_wb_phase_q <= 1'b0;
~038400     end else if (pwr_ready_o && scrub_en_i && !bist_en_i && !req_en_i) begin
%000006       if (!scrub_wb_phase_q) begin
%000006         scrub_wb_phase_q <= 1'b1;
%000006       end else begin
%000006         scrub_wb_phase_q <= 1'b0;
%000006         scrub_ptr_q      <= scrub_ptr_q + 1'b1;
              end
 038400     end else begin
 038400       scrub_wb_phase_q <= 1'b0;
            end
          end
        
          assign scrub_addr_o = scrub_ptr_q;
        
          // ---------------------------------------------------------------------------
          // 4. Effective SRAM Port Mux (BIST > Functional > Background Scrub)
          // ---------------------------------------------------------------------------
 000809   logic                eff_en;
~000465   logic                eff_we;
~000850   logic [ADDR_W-1:0]   eff_addr;
~000695   logic [DATA_W-1:0]   eff_wdata;
~000064   logic [DATA_W/8-1:0] eff_wmask;
        
 038848   always_comb begin
 038848     eff_en    = 1'b0;
 038848     eff_we    = 1'b0;
 038848     eff_addr  = req_addr_i;
 038848     eff_wdata = req_wdata_i;
 038848     eff_wmask = req_wmask_i;
        
~038848     if (pwr_ready_o) begin
~000648       if (bist_en_i) begin
~000648         eff_addr  = bist_addr_q;
~000648         eff_wmask = {(DATA_W/8){1'b1}};
~000648         case (bist_state_q)
~000080           BIST_M0: begin
~000080             eff_en    = 1'b1;
~000080             eff_we    = 1'b1;
~000080             eff_wdata = '0;
                  end
~000309           BIST_M1, BIST_M3: begin
~000309             eff_en    = 1'b1;
~000309             eff_we    = bist_sub_q;
~000309             eff_wdata = {DATA_W{1'b1}};
                  end
~000192           BIST_M2, BIST_M4: begin
~000192             eff_en    = 1'b1;
~000192             eff_we    = bist_sub_q;
~000192             eff_wdata = '0;
                  end
~000032           BIST_M5: begin
~000032             eff_en    = !bist_sub_q;
~000032             eff_we    = 1'b0;
                  end
~000035           default: eff_en = 1'b0;
                endcase
 005418       end else if (req_en_i) begin
 005418         eff_en    = 1'b1;
 005418         eff_we    = req_we_i;
 005418         eff_addr  = req_addr_i;
 005418         eff_wdata = req_wdata_i;
 005418         eff_wmask = req_wmask_i;
~038136       end else if (scrub_en_i) begin
~000015         eff_en    = !scrub_wb_phase_q || sec_err_o;
~000015         eff_we    = scrub_wb_phase_q && sec_err_o;
~000015         eff_addr  = scrub_ptr_q;
~000015         eff_wdata = rdata_o;
~000015         eff_wmask = {(DATA_W/8){1'b1}};
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
~000454   logic [ECC_W-1:0]  sram_rd_word_q;
%000003   logic [ECC_W-1:0]  spare_row_q;
%000008   logic              hit_spare_row;
%000001   logic              hit_spare_row_q;
~000454   logic [ECC_W-1:0]  rd_codeword_mux;
~000695   logic [DATA_W-1:0] enc_din;
~001328   logic [ECC_W-1:0]  enc_codeword;
        
          assign hit_spare_row = repair_en_i && (eff_addr == repair_bad_addr_i);
        
 038944   always_comb begin
 038944     enc_din = '0;
 311552     for (int byte_idx = 0; byte_idx < DATA_W/8; byte_idx++) begin
~311552       if (eff_wmask[byte_idx]) begin
 311552         enc_din[byte_idx*8 +: 8] = eff_wdata[byte_idx*8 +: 8];
~000016       end else begin
~000016         enc_din[byte_idx*8 +: 8] = rdata_o[byte_idx*8 +: 8];
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
        
 038592   always_ff @(posedge clk) begin
 037880     if (eff_en) begin
 001379       if (eff_we && !hit_spare_row) begin
 000563         mem_array[eff_addr[PHYS_ADDR_W-1:0]] <= enc_codeword;
              end
 001942       sram_rd_word_q <= mem_array[eff_addr[PHYS_ADDR_W-1:0]];
            end
          end
        
 038592   always_ff @(posedge clk or negedge rst_n) begin
 038400     if (!rst_n) begin
 000192       spare_row_q     <= '0;
 000192       hit_spare_row_q <= 1'b0;
 000192       rvalid_o        <= 1'b0;
 038400     end else begin
 038400       rvalid_o <= eff_en && !eff_we && (!bist_en_i) && (req_en_i);
 037688       if (eff_en) begin
~001942         if (eff_we && hit_spare_row) begin
%000001           spare_row_q <= enc_codeword;
                end
 001379         if (!eff_we) begin
 001379           hit_spare_row_q <= hit_spare_row;
                end
              end
            end
          end
        
          assign repair_spare_data_q = spare_row_q[DATA_W-1:0];
        
        endmodule : mlu_sram_sp_macro
        
