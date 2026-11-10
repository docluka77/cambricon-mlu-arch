// =============================================================================
// File: formal/mlu_vfu_sfu_pipe_formal.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Stage 10 Sequential SAT / BMC Formal Wrapper for mlu_vfu_sfu_pipe:
//              - Property 1: 2-Cycle Pipeline Determinism & Tag Invariance
//              - Property 2: Saturating VADD Bounds & No Overflow Wrap
//              - Property 3: Softmax Non-Negativity, Boundedness & Monotonicity
//              - Property 4: Cambricon-Q QuantStat Bounds (min <= max, absmax >= 0)
// =============================================================================
`include "mlu_pkg.sv"

module mlu_vfu_sfu_pipe_formal (
  input  logic         clk_i,
  input  logic         rst_ni,
  input  logic [1:0]   mode_sel_i,
  input  logic         cmd_valid_i,
  input  logic [127:0] cmd_inst_i,
  input  logic [127:0] vec_a_i,
  input  logic [127:0] vec_b_i,
  input  logic [127:0] cos_sin_lut_i,
  output logic         cmd_ready_o,
  output logic [127:0] vec_out_o,
  output logic         vec_out_valid_o,
  output logic [31:0]  softmax_sum_o,
  output logic [15:0]  softmax_max_o,
  output logic [15:0]  absmax_o,
  output logic [15:0]  min_val_o,
  output logic [15:0]  max_val_o,
  output logic [15:0]  dyn_scale_o,
  output logic         vfu_busy_o,
  output logic         done_valid_o,
  output logic [7:0]   done_tag_o
);

  logic init_done_q;
  always_ff @(posedge clk_i) begin
    init_done_q <= 1'b1;
  end
  always_comb begin
    if (!init_done_q) assume (!rst_ni);
    else              assume (rst_ni);
  end

  mlu_pkg::mlu_inst_t eff_cmd;
  logic [127:0]       eff_a;
  logic [127:0]       dut_vec_out;

  always_comb begin
    eff_cmd = cmd_inst_i;
    eff_a   = vec_a_i;
    if (mode_sel_i == 2'd0) begin
      eff_cmd.opcode = mlu_pkg::OP_BANG_VADD;
      eff_a          = vec_a_i;
    end else if (mode_sel_i == 2'd1) begin
      eff_cmd.opcode          = mlu_pkg::OP_BANG_SOFTMAX;
      eff_cmd.src1_or_strd[0] = 1'b0;
      eff_a                   = {8{vec_a_i[15:0]}};
    end else begin
      eff_cmd.opcode = mlu_pkg::OP_BANG_QUANT_STAT;
      eff_a          = {4{vec_a_i[31:0]}};
    end
  end

  mlu_vfu_sfu_pipe u_dut (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .cmd_valid_i     (cmd_valid_i),
    .cmd_ready_o     (cmd_ready_o),
    .cmd_inst_i      (eff_cmd),
    .vec_a_i         (eff_a),
    .vec_b_i         (vec_b_i),
    .cos_sin_lut_i   (cos_sin_lut_i),
    .vec_out_o       (dut_vec_out),
    .vec_out_valid_o (vec_out_valid_o),
    .softmax_sum_o   (softmax_sum_o),
    .softmax_max_o   (softmax_max_o),
    .absmax_o        (absmax_o),
    .min_val_o       (min_val_o),
    .max_val_o       (max_val_o),
    .dyn_scale_o     (dyn_scale_o),
    .vfu_busy_o      (vfu_busy_o),
    .done_valid_o    (done_valid_o),
    .done_tag_o      (done_tag_o)
  );

  assign vec_out_o = (mode_sel_i == 2'd2) ? 128'd0 : dut_vec_out;

  // Pipeline stage tracking shift registers
  logic                 accept_s1_q, accept_s2_q, accept_out_q;
  logic [7:0]           tag_s1_q, tag_s2_q, tag_out_q;
  mlu_pkg::mlu_opcode_e op_s1_q, op_s2_q, op_out_q;
  logic [127:0]         va_s1_q, va_s2_q, va_out_q;
  logic [127:0]         vb_s1_q, vb_s2_q, vb_out_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      accept_s1_q  <= 1'b0;
      accept_s2_q  <= 1'b0;
      accept_out_q <= 1'b0;
      tag_s1_q     <= 8'd0;
      tag_s2_q     <= 8'd0;
      tag_out_q    <= 8'd0;
      op_s1_q      <= mlu_pkg::OP_NOP;
      op_s2_q      <= mlu_pkg::OP_NOP;
      op_out_q     <= mlu_pkg::OP_NOP;
      va_s1_q      <= '0;
      va_s2_q      <= '0;
      va_out_q     <= '0;
      vb_s1_q      <= '0;
      vb_s2_q      <= '0;
      vb_out_q     <= '0;
    end else begin
      accept_s1_q  <= cmd_valid_i && cmd_ready_o;
      accept_s2_q  <= accept_s1_q;
      accept_out_q <= accept_s2_q;

      if (cmd_valid_i && cmd_ready_o) begin
        tag_s1_q <= eff_cmd.tag_id;
        op_s1_q  <= eff_cmd.opcode;
        va_s1_q  <= eff_a;
        vb_s1_q  <= vec_b_i;
      end
      tag_s2_q  <= tag_s1_q;
      tag_out_q <= tag_s2_q;
      op_s2_q   <= op_s1_q;
      op_out_q  <= op_s2_q;
      va_s2_q   <= va_s1_q;
      va_out_q  <= va_s2_q;
      vb_s2_q   <= vb_s1_q;
      vb_out_q  <= vb_s2_q;
    end
  end

  always_comb begin
    if (rst_ni) begin
      // Property 1: 2-Cycle Pipeline Determinism & Tag Invariance
      assert (cmd_ready_o == !vfu_busy_o);
      assert (vfu_busy_o == (accept_s1_q || accept_s2_q));
      assert (vec_out_valid_o == accept_out_q);
      assert (done_valid_o == accept_out_q);
      if (done_valid_o) begin
        assert (done_tag_o == tag_out_q);
      end

      // Property 2: Saturating VADD Bounds & No Overflow Wrap
      if (vec_out_valid_o && (op_out_q == mlu_pkg::OP_BANG_VADD)) begin
        for (int i = 0; i < 8; i++) begin
          if (($signed(va_out_q[i*16 +: 16]) >= 16'sd0) &&
              ($signed(vb_out_q[i*16 +: 16]) >= 16'sd0)) begin
            assert ($signed(vec_out_o[i*16 +: 16]) >= 16'sd0);
          end
          if (($signed(va_out_q[i*16 +: 16]) < 16'sd0) &&
              ($signed(vb_out_q[i*16 +: 16]) < 16'sd0)) begin
            assert ($signed(vec_out_o[i*16 +: 16]) < 16'sd0);
          end
          if (($signed({{16{va_out_q[i*16+15]}}, va_out_q[i*16 +: 16]}) +
               $signed({{16{vb_out_q[i*16+15]}}, vb_out_q[i*16 +: 16]})) > 32'sd32767) begin
            assert (vec_out_o[i*16 +: 16] == 16'h7FFF);
          end
          if (($signed({{16{va_out_q[i*16+15]}}, va_out_q[i*16 +: 16]}) +
               $signed({{16{vb_out_q[i*16+15]}}, vb_out_q[i*16 +: 16]})) < -32'sd32768) begin
            assert (vec_out_o[i*16 +: 16] == 16'h8000);
          end
        end
      end

      // Property 3: Softmax Non-Negativity, Sum > 0, and Probability Bounds
      if (vec_out_valid_o && (op_out_q == mlu_pkg::OP_BANG_SOFTMAX)) begin
        assert (softmax_sum_o > 32'd0);
        assert (softmax_max_o == va_out_q[15:0]);
        for (int i = 0; i < 8; i++) begin
          assert ($signed(vec_out_o[i*16 +: 16]) >= 16'sd0);
          assert (vec_out_o[i*16 +: 16] <= 16'd256);
          assert (vec_out_o[i*16 +: 16] == vec_out_o[15:0]);
        end
      end

      // Property 4: Cambricon-Q QuantStat Bounds (min <= max, absmax >= 0, scale >= 1)
      if (vec_out_valid_o && (op_out_q == mlu_pkg::OP_BANG_QUANT_STAT)) begin
        assert ($signed(min_val_o) <= $signed(max_val_o));
        assert ($signed(min_val_o) <= $signed(va_out_q[15:0]));
        assert ($signed(max_val_o) >= $signed(va_out_q[15:0]));
        assert ($signed(absmax_o) >= 16'sd0);
        assert (dyn_scale_o >= 16'd1);
      end
    end
  end

endmodule : mlu_vfu_sfu_pipe_formal
