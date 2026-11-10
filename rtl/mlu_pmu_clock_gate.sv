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
  input  logic        clk_i,
  input  logic        rst_ni,

  // Engine & Memory Activity Monitors
  input  logic [4:0]  eng_busy_i,
  input  logic [4:0]  icu_dispatch_mask_i,
  input  logic [2:0]  mem_active_i,

  // Software Dynamic Power Gate Hint (from ICU OP_PWR_GATE_CFG)
  input  logic        pwr_gate_cfg_valid_i,
  input  logic [7:0]  idle_threshold_i,

  // Glitch-Free Clock-Gate Enables & SRAM Sleep Controls
  output logic [4:0]  eng_clk_en_o,
  output logic [2:0]  sram_slp_o,
  output logic [2:0]  sram_dslp_o,
  output logic [2:0]  sram_wake_ready_o,

  // Cycle-Accurate Energy Telemetry Counters
  output logic [31:0] active_mac_cycles_o,
  output logic [31:0] gated_saved_cycles_o,
  output logic [31:0] sram_sleep_cycles_o
);

  // ---------------------------------------------------------------------------
  // 1. Programmable Idle Threshold & Per-Domain Idle Timers
  // ---------------------------------------------------------------------------
  logic [7:0]       idle_thresh_q;
  logic [8:0]       deep_thresh_w;
  logic [4:0][8:0]  eng_idle_cnt_q;
  logic [2:0][8:0]  mem_idle_cnt_q;
  logic [2:0]       sram_slp_q;
  logic [2:0]       sram_dslp_q;

  // Deep-sleep threshold is 2x light-sleep threshold (minimum 4 cycles)
  assign deep_thresh_w = ({1'b0, idle_thresh_q} == 9'd0) ? 9'd4 : ({idle_thresh_q, 1'b0});

  // 0-Cycle Immediate Wakeup Combinational Clock-Gate Enable
  always_comb begin
    for (int e = 0; e < 5; e++) begin
      if (eng_busy_i[e] || icu_dispatch_mask_i[e]) begin
        eng_clk_en_o[e] = 1'b1;
      end else if (eng_idle_cnt_q[e] >= {1'b0, idle_thresh_q}) begin
        eng_clk_en_o[e] = 1'b0;
      end else begin
        eng_clk_en_o[e] = 1'b1;
      end
    end
  end

  // Memory wakeup demand: explicit memory access or incoming engine dispatch
  logic [2:0] mem_wake_req;
  assign mem_wake_req[0] = mem_active_i[0] || (|icu_dispatch_mask_i[2:0]); // NRAM
  assign mem_wake_req[1] = mem_active_i[1] || icu_dispatch_mask_i[0] || icu_dispatch_mask_i[2]; // WRAM
  assign mem_wake_req[2] = mem_active_i[2] || (|icu_dispatch_mask_i[4:2]); // Shared SRAM

  assign sram_slp_o        = sram_slp_q;
  assign sram_dslp_o       = sram_dslp_q;
  assign sram_wake_ready_o = ~(sram_slp_q | sram_dslp_q);

  // ---------------------------------------------------------------------------
  // 2. Per-Cycle Gated Engine & Sleeping Memory Domain Summations
  // ---------------------------------------------------------------------------
  logic [31:0] gated_eng_inc;
  logic [31:0] sleep_mem_inc;

  always_comb begin
    gated_eng_inc = 32'd0;
    for (int e = 0; e < 5; e++) begin
      if (!eng_clk_en_o[e]) begin
        gated_eng_inc = gated_eng_inc + 32'd1;
      end
    end

    sleep_mem_inc = 32'd0;
    for (int m = 0; m < 3; m++) begin
      if (sram_slp_q[m] || sram_dslp_q[m]) begin
        sleep_mem_inc = sleep_mem_inc + 32'd1;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // 3. Sequential Timers, 1-Cycle SRAM Wake Control, and Telemetry Counters
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      idle_thresh_q        <= DEFAULT_IDLE_THRESH;
      eng_idle_cnt_q       <= '0;
      mem_idle_cnt_q       <= '0;
      sram_slp_q           <= 3'b000;
      sram_dslp_q          <= 3'b000;
      active_mac_cycles_o  <= 32'd0;
      gated_saved_cycles_o <= 32'd0;
      sram_sleep_cycles_o  <= 32'd0;
    end else begin
      if (pwr_gate_cfg_valid_i) begin
        idle_thresh_q <= (idle_threshold_i == 8'd0) ? 8'd1 : idle_threshold_i;
      end

      // Engine idle timers
      for (int e = 0; e < 5; e++) begin
        if (eng_busy_i[e] || icu_dispatch_mask_i[e]) begin
          eng_idle_cnt_q[e] <= 9'd0;
        end else if (eng_idle_cnt_q[e] < 9'h1FE) begin
          eng_idle_cnt_q[e] <= eng_idle_cnt_q[e] + 9'd1;
        end
      end

      // Memory domain idle timers & 1-cycle wake sleep state machine
      for (int m = 0; m < 3; m++) begin
        if (mem_wake_req[m]) begin
          mem_idle_cnt_q[m] <= 9'd0;
          sram_slp_q[m]     <= 1'b0;
          sram_dslp_q[m]    <= 1'b0;
        end else begin
          if (mem_idle_cnt_q[m] < 9'h1FE) begin
            mem_idle_cnt_q[m] <= mem_idle_cnt_q[m] + 9'd1;
          end
          if (mem_idle_cnt_q[m] + 9'd1 >= deep_thresh_w) begin
            sram_slp_q[m]  <= 1'b0;
            sram_dslp_q[m] <= 1'b1;
          end else if (mem_idle_cnt_q[m] + 9'd1 >= {1'b0, idle_thresh_q}) begin
            sram_slp_q[m]  <= 1'b1;
            sram_dslp_q[m] <= 1'b0;
          end
        end
      end

      // Telemetry counters
      if (eng_busy_i[0]) begin
        active_mac_cycles_o <= active_mac_cycles_o + 32'd1;
      end
      gated_saved_cycles_o <= gated_saved_cycles_o + gated_eng_inc;
      sram_sleep_cycles_o  <= sram_sleep_cycles_o  + sleep_mem_inc;
    end
  end

endmodule : mlu_pmu_clock_gate
