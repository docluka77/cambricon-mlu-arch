//      // verilator_coverage annotation
        // =============================================================================
        // File: rtl/mlu_pmu_clock_gate.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: Stage 3B — Fine-Grained Dynamic Clock/Power Gating & Energy
        //              Telemetry Controller (PMU). Monitors 5 execution engines and
        //              3 memory domains (NRAM, WRAM, SRAM), generates 0-cycle wake
        //              clock-gate enables and 1-cycle SRAM light/deep sleep controls,
        //              and tracks cycle-accurate energy savings counters.
        // =============================================================================
        `include "mlu_pkg.sv"
        
        module mlu_pmu_clock_gate #(
          parameter logic [7:0] DEFAULT_IDLE_THRESH = 8'd8
        ) (
 002412   input  logic        clk_i,
%000004   input  logic        rst_ni,
        
          // Engine & Memory Activity Monitors
~000069   input  logic [4:0]  eng_busy_i,
~000069   input  logic [4:0]  icu_dispatch_mask_i,
~000127   input  logic [2:0]  mem_active_i,
        
          // Software Dynamic Power Gate Hint (from ICU OP_PWR_GATE_CFG)
%000001   input  logic        pwr_gate_cfg_valid_i,
%000004   input  logic [7:0]  idle_threshold_i,
        
          // Glitch-Free Clock-Gate Enables & SRAM Sleep Controls
~000045   output logic [4:0]  eng_clk_en_o,
 000078   output logic [2:0]  sram_slp_o,
 000077   output logic [2:0]  sram_dslp_o,
 000078   output logic [2:0]  sram_wake_ready_o,
        
          // Cycle-Accurate Energy Telemetry Counters
~000045   output logic [31:0] active_mac_cycles_o,
~000993   output logic [31:0] gated_saved_cycles_o,
~001009   output logic [31:0] sram_sleep_cycles_o
        );
        
          // ---------------------------------------------------------------------------
          // 1. Programmable Idle Threshold & Per-Domain Idle Timers
          // ---------------------------------------------------------------------------
%000004   logic [7:0]       idle_thresh_q;
%000004   logic [8:0]       deep_thresh_w;
~001192   logic [4:0][8:0]  eng_idle_cnt_q;
~001180   logic [2:0][8:0]  mem_idle_cnt_q;
 000078   logic [2:0]       sram_slp_q;
 000077   logic [2:0]       sram_dslp_q;
        
          // Deep-sleep threshold is 2x light-sleep threshold (minimum 4 cycles)
          assign deep_thresh_w = ({1'b0, idle_thresh_q} == 9'd0) ? 9'd4 : ({idle_thresh_q, 1'b0});
        
          // 0-Cycle Immediate Wakeup Combinational Clock-Gate Enable
 002686   always_comb begin
 013430     for (int e = 0; e < 5; e++) begin
 001962       if (eng_busy_i[e] || icu_dispatch_mask_i[e]) begin
 001962         eng_clk_en_o[e] = 1'b1;
 012303       end else if (eng_idle_cnt_q[e] >= {1'b0, idle_thresh_q}) begin
 012303         eng_clk_en_o[e] = 1'b0;
 000847       end else begin
 000847         eng_clk_en_o[e] = 1'b1;
              end
            end
          end
        
          // Memory wakeup demand: explicit memory access or incoming engine dispatch
 000178   logic [2:0] mem_wake_req;
          assign mem_wake_req[0] = mem_active_i[0] || (|icu_dispatch_mask_i[2:0]); // NRAM
          assign mem_wake_req[1] = mem_active_i[1] || icu_dispatch_mask_i[0] || icu_dispatch_mask_i[2]; // WRAM
          assign mem_wake_req[2] = mem_active_i[2] || (|icu_dispatch_mask_i[4:2]); // Shared SRAM
        
          assign sram_slp_o        = sram_slp_q;
          assign sram_dslp_o       = sram_dslp_q;
          assign sram_wake_ready_o = ~(sram_slp_q | sram_dslp_q);
        
          // ---------------------------------------------------------------------------
          // 2. Per-Cycle Gated Engine & Sleeping Memory Domain Summations
          // ---------------------------------------------------------------------------
~000177   logic [31:0] gated_eng_inc;
~000085   logic [31:0] sleep_mem_inc;
        
 002686   always_comb begin
 002686     gated_eng_inc = 32'd0;
 013430     for (int e = 0; e < 5; e++) begin
 012303       if (!eng_clk_en_o[e]) begin
 012303         gated_eng_inc = gated_eng_inc + 32'd1;
              end
            end
        
 002686     sleep_mem_inc = 32'd0;
 008058     for (int m = 0; m < 3; m++) begin
 006624       if (sram_slp_q[m] || sram_dslp_q[m]) begin
 006624         sleep_mem_inc = sleep_mem_inc + 32'd1;
              end
            end
          end
        
          // ---------------------------------------------------------------------------
          // 3. Sequential Timers, 1-Cycle SRAM Wake Control, and Telemetry Counters
          // ---------------------------------------------------------------------------
 002412   always_ff @(posedge clk_i or negedge rst_ni) begin
~002400     if (!rst_ni) begin
~000012       idle_thresh_q        <= DEFAULT_IDLE_THRESH;
~000012       eng_idle_cnt_q       <= '0;
~000012       mem_idle_cnt_q       <= '0;
~000012       sram_slp_q           <= 3'b000;
~000012       sram_dslp_q          <= 3'b000;
~000012       active_mac_cycles_o  <= 32'd0;
~000012       gated_saved_cycles_o <= 32'd0;
~000012       sram_sleep_cycles_o  <= 32'd0;
 002400     end else begin
~002400       if (pwr_gate_cfg_valid_i) begin
%000001         idle_thresh_q <= (idle_threshold_i == 8'd0) ? 8'd1 : idle_threshold_i;
              end
        
              // Engine idle timers
 012000       for (int e = 0; e < 5; e++) begin
 000809         if (eng_busy_i[e] || icu_dispatch_mask_i[e]) begin
 000809           eng_idle_cnt_q[e] <= 9'd0;
~011098         end else if (eng_idle_cnt_q[e] < 9'h1FE) begin
 011098           eng_idle_cnt_q[e] <= eng_idle_cnt_q[e] + 9'd1;
                end
              end
        
              // Memory domain idle timers & 1-cycle wake sleep state machine
 007200       for (int m = 0; m < 3; m++) begin
 006860         if (mem_wake_req[m]) begin
 001023           mem_idle_cnt_q[m] <= 9'd0;
 001023           sram_slp_q[m]     <= 1'b0;
 001023           sram_dslp_q[m]    <= 1'b0;
 006860         end else begin
~006860           if (mem_idle_cnt_q[m] < 9'h1FE) begin
 006860             mem_idle_cnt_q[m] <= mem_idle_cnt_q[m] + 9'd1;
                  end
 005556           if (mem_idle_cnt_q[m] + 9'd1 >= deep_thresh_w) begin
 005556             sram_slp_q[m]  <= 1'b0;
 005556             sram_dslp_q[m] <= 1'b1;
 000664           end else if (mem_idle_cnt_q[m] + 9'd1 >= {1'b0, idle_thresh_q}) begin
 000640             sram_slp_q[m]  <= 1'b1;
 000640             sram_dslp_q[m] <= 1'b0;
                  end
                end
              end
        
              // Telemetry counters
 002355       if (eng_busy_i[0]) begin
 000090         active_mac_cycles_o <= active_mac_cycles_o + 32'd1;
              end
 002400       gated_saved_cycles_o <= gated_saved_cycles_o + gated_eng_inc;
 002400       sram_sleep_cycles_o  <= sram_sleep_cycles_o  + sleep_mem_inc;
            end
          end
        
        endmodule : mlu_pmu_clock_gate
        
