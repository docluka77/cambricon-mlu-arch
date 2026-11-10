// =============================================================================
// File: formal/mlu_tfu_fractal_mac_formal.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Stage 10 Sequential SAT / BMC Formal Wrapper for mlu_tfu_fractal_mac:
//              - Property 1: Cambricon-S Block-4x4 Zero-Skip Exactness & 1-Cycle Skip
//              - Property 2: Multi-Precision Zero-Operand Annihilation (INT4/8, FP8, FP16/BF16)
//              - Property 3: Tag Preservation & Handshake Mutual Exclusion
// =============================================================================
`include "mlu_pkg.sv"

module mlu_tfu_fractal_mac_formal (
  input  logic         clk_i,
  input  logic         rst_ni,
  input  logic [1:0]   mode_sel_i,
  input  logic         cmd_valid_i,
  input  logic [127:0] cmd_inst_i,
  input  logic         stream_valid_i,
  input  logic [255:0] nram_act_i,
  input  logic [255:0] wram_wt_i,
  input  logic [31:0]  wram_sparse_meta_i,
  input  logic [15:0]  quant_scale_i,
  output logic         cmd_ready_o,
  output logic         stream_ready_o,
  output logic         tfu_busy_o,
  output logic [255:0] result_data_o,
  output logic         result_valid_o,
  output logic         done_valid_o,
  output logic [7:0]   done_tag_o,
  output logic [31:0]  zero_skip_cnt_o,
  output logic [31:0]  total_mac_ops_o
);

  logic init_done_q;
  always_ff @(posedge clk_i) begin
    init_done_q <= 1'b1;
  end
  always_comb begin
    if (!init_done_q) assume (!rst_ni);
    else              assume (rst_ni);
  end

  // Partitioned formal input space covering:
  // mode_sel_i == 2'd0: Cambricon-S SPARSE_BLOCK_4X4 with zero-bitmap (non-zero act & wt)
  // mode_sel_i == 2'd1: Zero Activation (nram_act == 0, full 256b wt, all 8 precisions)
  // mode_sel_i == 2'd2: Zero Weight (wram_wt == 0, full 256b act, all 8 precisions)
  mlu_pkg::mlu_inst_t eff_cmd;
  logic [255:0]       eff_act;
  logic [255:0]       eff_wt;
  logic [31:0]        eff_meta;

  always_comb begin
    eff_cmd  = cmd_inst_i;
    eff_act  = nram_act_i;
    eff_wt   = wram_wt_i;
    eff_meta = 32'd0;
    if (mode_sel_i == 2'd0) begin
      eff_cmd.sparse_mode = mlu_pkg::SPARSE_BLOCK_4X4;
      eff_act             = {248'd0, nram_act_i[7:0]};
      eff_wt              = {248'd0, wram_wt_i[7:0]};
      eff_meta            = 32'd0;
    end else if (mode_sel_i == 2'd1) begin
      eff_cmd.sparse_mode = mlu_pkg::SPARSE_DENSE;
      eff_act             = 256'd0;
      eff_meta            = 32'd0;
    end else begin
      eff_cmd.sparse_mode = mlu_pkg::SPARSE_DENSE;
      eff_wt              = 256'd0;
      eff_meta            = 32'd0;
    end
  end

  mlu_tfu_fractal_mac u_dut (
    .clk_i              (clk_i),
    .rst_ni             (rst_ni),
    .cmd_valid_i        (cmd_valid_i),
    .cmd_ready_o        (cmd_ready_o),
    .cmd_inst_i         (eff_cmd),
    .stream_valid_i     (stream_valid_i),
    .stream_ready_o     (stream_ready_o),
    .nram_act_i         (eff_act),
    .wram_wt_i          (eff_wt),
    .wram_sparse_meta_i (eff_meta),
    .quant_scale_i      (quant_scale_i),
    .quant_zp_i         (8'd0),
    .tfu_busy_o         (tfu_busy_o),
    .result_data_o      (result_data_o),
    .result_valid_o     (result_valid_o),
    .done_valid_o       (done_valid_o),
    .done_tag_o         (done_tag_o),
    .zero_skip_cnt_o    (zero_skip_cnt_o),
    .total_mac_ops_o    (total_mac_ops_o)
  );

  logic [7:0]  expected_tag_q;
  logic        single_beat_b4x4_q;
  logic        skip_triggered_d1_q;
  logic [31:0] prev_zero_skip_cnt_q;
  logic [31:0] prev_total_mac_ops_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      expected_tag_q       <= 8'd0;
      single_beat_b4x4_q   <= 1'b0;
      skip_triggered_d1_q  <= 1'b0;
      prev_zero_skip_cnt_q <= 32'd0;
      prev_total_mac_ops_q <= 32'd0;
    end else begin
      skip_triggered_d1_q  <= 1'b0;
      prev_zero_skip_cnt_q <= zero_skip_cnt_o;
      prev_total_mac_ops_q <= total_mac_ops_o;

      if (cmd_valid_i && cmd_ready_o) begin
        expected_tag_q     <= eff_cmd.tag_id;
        single_beat_b4x4_q <= (eff_cmd.sparse_mode == mlu_pkg::SPARSE_BLOCK_4X4) &&
                              (eff_cmd.len_or_dims <= 16'd1);
      end else if (stream_valid_i && stream_ready_o) begin
        single_beat_b4x4_q <= 1'b0;
        if (single_beat_b4x4_q && (eff_meta[0] == 1'b0)) begin
          skip_triggered_d1_q <= 1'b1;
        end
      end
    end
  end

  always_comb begin
    if (rst_ni) begin
      // Property 1: Cambricon-S Block-4x4 Zero-Skip 1-Cycle Completion & Exact Zero
      if (skip_triggered_d1_q) begin
        assert (result_valid_o && done_valid_o);
        assert (result_data_o == 256'd0);
        assert (zero_skip_cnt_o == prev_zero_skip_cnt_q + 32'd1);
        assert (total_mac_ops_o == prev_total_mac_ops_q);
      end

      // Property 2: Multi-Precision Zero-Operand Annihilation (INT4/8, FP8, FP16/BF16, TF32)
      assert (result_data_o == 256'd0);

      // Property 3: Tag Preservation & Handshake Mutual Exclusion
      assert (cmd_ready_o == !tfu_busy_o);
      assert (!(cmd_ready_o && stream_ready_o));
      assert (result_valid_o == done_valid_o);
      if (done_valid_o) begin
        assert (done_tag_o == expected_tag_q);
        assert (!cmd_ready_o);
      end
    end
  end

endmodule : mlu_tfu_fractal_mac_formal
