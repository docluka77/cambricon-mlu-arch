// =============================================================================
// File: rtl/mlu_vfu_sfu_pipe.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Stage 5 — Vector Function Unit (VFU) & Special Function Unit (SFU)
//              8-Lane 16-bit (Q8.8 / INT16) Pipeline implementing all 7 BANG ISA
//              Vector & LLM Operations:
//              - OP_BANG_VADD       : 8-lane saturating vector addition
//              - OP_BANG_VMUL       : 8-lane Q8.8 fixed-point vector multiplication
//              - OP_BANG_SOFTMAX    : FlashAttention Online Safe Softmax (Max + PWL Exp + Norm)
//              - OP_BANG_ROPE       : Rotary Position Embedding (4x Complex Pair Rotation)
//              - OP_BANG_RMSNORM    : Root-Mean-Square LayerNorm (LUT + Newton-Raphson Rsqrt)
//              - OP_BANG_SWIGLU     : Fused SiLU(Gate) * Up-Projection Activation
//              - OP_BANG_QUANT_STAT : Cambricon-Q Dynamic Min/Max/AbsMax & Scale Analyzer
// =============================================================================
`include "mlu_pkg.sv"

module mlu_vfu_sfu_pipe (
  input  logic         clk_i,
  input  logic         rst_ni,

  // Dispatched VFU Command Interface (from BANG ICU)
  input  logic         cmd_valid_i,
  output logic         cmd_ready_o,
  input  logic [127:0] cmd_inst_i,

  // 8-Lane x 16-bit (128-bit) Vector Operands & RoPE Sin/Cos Lookup Table Input
  input  logic [127:0] vec_a_i,
  input  logic [127:0] vec_b_i,
  input  logic [127:0] cos_sin_lut_i,

  // 8-Lane x 16-bit (128-bit) Vector Result & Valid Output
  output logic [127:0] vec_out_o,
  output logic         vec_out_valid_o,

  // FlashAttention Online Safe Softmax Running State Outputs
  output logic [31:0]  softmax_sum_o,
  output logic [15:0]  softmax_max_o,

  // Cambricon-Q Dynamic Statistical Quantizer Outputs
  output logic [15:0]  absmax_o,
  output logic [15:0]  min_val_o,
  output logic [15:0]  max_val_o,
  output logic [15:0]  dyn_scale_o,

  // Status & ICU Completion Handshake
  output logic         vfu_busy_o,
  output logic         done_valid_o,
  output logic [7:0]   done_tag_o
);

  // ---------------------------------------------------------------------------
  // 1. Helper Functions: Sign-Extend, Saturating Clamp, PWL Exp/Sigmoid, Rsqrt
  // ---------------------------------------------------------------------------
  function automatic logic signed [31:0] sext16(input logic [15:0] v);
    sext16 = $signed({{16{v[15]}}, v});
  endfunction

  function automatic logic signed [15:0] sat_s16(input logic signed [31:0] val);
    if (val > $signed(32'd32767)) begin
      sat_s16 = $signed(16'd32767);
    end else if (val < -$signed(32'd32768)) begin
      sat_s16 = $signed(16'h8000);
    end else begin
      sat_s16 = $signed(val[15:0]);
    end
  endfunction

  function automatic logic [15:0] abs_s16(input logic [15:0] xi);
    logic [15:0] neg_xi;
    neg_xi = ~xi + 16'd1;
    if (xi == 16'h8000) begin
      abs_s16 = 16'd32767;
    end else if (xi[15]) begin
      abs_s16 = neg_xi;
    end else begin
      abs_s16 = xi;
    end
  endfunction

  // 6-Segment Piecewise-Linear Approximation of exp(d) for d <= 0 in Q8.8
  // Returns unsigned Q8.8 value in [1 .. 256], where 256 == 1.0
  function automatic logic [15:0] pwl_exp_q88(input logic signed [31:0] d32);
    logic signed [31:0] y;
    if (d32 >= $signed(32'd0)) begin
      y = $signed(32'd256);
    end else if (d32 >= -$signed(32'd256)) begin
      y = $signed(32'd256) + (($signed(32'd162) * d32) >>> 8);
    end else if (d32 >= -$signed(32'd512)) begin
      y = $signed(32'd94)  + (($signed(32'd59)  * (d32 + $signed(32'd256))) >>> 8);
    end else if (d32 >= -$signed(32'd768)) begin
      y = $signed(32'd35)  + (($signed(32'd22)  * (d32 + $signed(32'd512))) >>> 8);
    end else if (d32 >= -$signed(32'd1024)) begin
      y = $signed(32'd13)  + (($signed(32'd8)   * (d32 + $signed(32'd768))) >>> 8);
    end else if (d32 >= -$signed(32'd1536)) begin
      y = $signed(32'd5)   + (($signed(32'd2)   * (d32 + $signed(32'd1024))) >>> 8);
    end else begin
      y = $signed(32'd1);
    end
    pwl_exp_q88 = sat_s16((y < $signed(32'd1)) ? $signed(32'd1) :
                          ((y > $signed(32'd256)) ? $signed(32'd256) : y));
  endfunction

  // Piecewise-Linear Approximation of sigmoid(g) in Q8.8 -> [0 .. 256]
  function automatic logic signed [15:0] pwl_sigmoid_q88(input logic [15:0] g_q88);
    logic signed [31:0] g32;
    logic signed [31:0] abs_g;
    logic signed [31:0] pos_sig;
    g32   = sext16(g_q88);
    abs_g = (g32 < $signed(32'd0)) ? -g32 : g32;
    if (abs_g <= $signed(32'd256)) begin
      pos_sig = $signed(32'd128) + (($signed(32'd60) * abs_g) >>> 8);
    end else if (abs_g <= $signed(32'd512)) begin
      pos_sig = $signed(32'd188) + (($signed(32'd38) * (abs_g - $signed(32'd256))) >>> 8);
    end else if (abs_g <= $signed(32'd1024)) begin
      pos_sig = $signed(32'd226) + (($signed(32'd25) * (abs_g - $signed(32'd512))) >>> 9);
    end else begin
      pos_sig = $signed(32'd256);
    end
    pwl_sigmoid_q88 = sat_s16((g32 < $signed(32'd0)) ? ($signed(32'd256) - pos_sig) : pos_sig);
  endfunction

  // Fast LUT Seed + 1-Iteration Newton-Raphson Reciprocal Square Root in Q8.8
  function automatic logic signed [15:0] rsqrt_lut_nr_q88(input logic [31:0] var_q88);
    logic [31:0] v_safe;
    logic [31:0] y0;
    logic [63:0] v_y0_sq;
    logic [63:0] term;
    logic [63:0] y1;
    v_safe = (var_q88 == 32'd0) ? 32'd1 : var_q88;
    if      (v_safe < 32'd16)    y0 = 32'd1448;
    else if (v_safe < 32'd64)    y0 = 32'd724;
    else if (v_safe < 32'd128)   y0 = 32'd418;
    else if (v_safe < 32'd192)   y0 = 32'd324;
    else if (v_safe < 32'd320)   y0 = 32'd256;
    else if (v_safe < 32'd512)   y0 = 32'd202;
    else if (v_safe < 32'd768)   y0 = 32'd162;
    else if (v_safe < 32'd1280)  y0 = 32'd128;
    else if (v_safe < 32'd2560)  y0 = 32'd96;
    else if (v_safe < 32'd5120)  y0 = 32'd68;
    else if (v_safe < 32'd10240) y0 = 32'd48;
    else                         y0 = 32'd32;

    v_y0_sq = ({32'd0, v_safe} * {32'd0, y0} * {32'd0, y0}) >> 16;
    term    = (v_y0_sq >= 64'd760) ? 64'd8 : (64'd768 - v_y0_sq);
    y1      = ({32'd0, y0} * term) >> 9;
    if (y1 == 64'd0) begin
      rsqrt_lut_nr_q88 = $signed(16'd1);
    end else if (y1 > 64'd32767) begin
      rsqrt_lut_nr_q88 = $signed(16'd32767);
    end else begin
      rsqrt_lut_nr_q88 = $signed(y1[15:0]);
    end
  endfunction

  function automatic logic [15:0] calc_dyn_scale(
    input logic [15:0]        absmax_v,
    input mlu_pkg::mlu_prec_e prec_v
  );
    logic [31:0] sc;
    sc = (prec_v == mlu_pkg::PREC_INT4) ? ({16'd0, absmax_v} / 32'd7)
                                        : ({16'd0, absmax_v} / 32'd127);
    if (absmax_v == 16'd0 || sc == 32'd0) begin
      calc_dyn_scale = 16'd1;
    end else if (sc > 32'd65535) begin
      calc_dyn_scale = 16'hFFFF;
    end else begin
      calc_dyn_scale = sc[15:0];
    end
  endfunction

  // ---------------------------------------------------------------------------
  // 2. Pipeline State & Latched Operands (2-Cycle Deterministic Execution)
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    VFU_IDLE = 2'b00,
    VFU_S1   = 2'b01,
    VFU_S2   = 2'b10
  } vfu_state_e;

  vfu_state_e           state_q;
  mlu_pkg::mlu_opcode_e op_q;
  mlu_pkg::mlu_prec_e   prec_q;
  logic [7:0]           tag_q;
  logic                 cont_mode_q;
  logic [127:0]         a_q;
  logic [127:0]         b_q;
  logic [127:0]         lut_q;

  logic signed [15:0]   s1_max_q;
  logic signed [15:0]   s1_min_q;
  logic [15:0]          s1_absmax_q;
  logic [15:0]          s1_dyn_scale_q;
  logic signed [15:0]   s1_m_new_q;
  logic [31:0]          s1_l_new_q;
  logic [127:0]         s1_exp_q;
  logic signed [15:0]   s1_rsqrt_q;

  assign cmd_ready_o = (state_q == VFU_IDLE);
  assign vfu_busy_o  = (state_q != VFU_IDLE);

  // ---------------------------------------------------------------------------
  // 3. Stage 1 Combinational Reductions (Max/Min/AbsMax, Softmax Exp, RMS Var)
  // ---------------------------------------------------------------------------
  logic signed [15:0] comb_max;
  logic signed [15:0] comb_min;
  logic [15:0]        comb_absmax;
  logic [15:0]        comb_dyn_scale;
  logic signed [15:0] comb_m_new;
  logic [15:0]        comb_old_exp;
  logic [127:0]       comb_exp_lane;
  logic [31:0]        comb_l_scaled;
  logic [31:0]        comb_l_new;
  logic [31:0]        comb_sq_sum;
  logic [31:0]        comb_mean_sq;
  logic signed [15:0] comb_rsqrt;

  always_comb begin
    comb_max       = $signed(a_q[15:0]);
    comb_min       = $signed(a_q[15:0]);
    comb_absmax    = 16'd0;
    comb_sq_sum    = 32'd0;
    comb_dyn_scale = 16'd1;
    comb_m_new     = $signed(a_q[15:0]);
    comb_old_exp   = 16'd256;
    comb_exp_lane  = 128'd0;
    comb_l_scaled  = 32'd0;
    comb_l_new     = 32'd1;
    comb_mean_sq   = 32'd1;
    comb_rsqrt     = $signed(16'd256);

    for (int i = 0; i < 8; i++) begin
      if ($signed(a_q[(i*16) +: 16]) > comb_max) comb_max = $signed(a_q[(i*16) +: 16]);
      if ($signed(a_q[(i*16) +: 16]) < comb_min) comb_min = $signed(a_q[(i*16) +: 16]);
      if (abs_s16(a_q[(i*16) +: 16]) > comb_absmax) comb_absmax = abs_s16(a_q[(i*16) +: 16]);
      comb_sq_sum = comb_sq_sum + (({16'd0, abs_s16(a_q[(i*16) +: 16])} *
                                    {16'd0, abs_s16(a_q[(i*16) +: 16])}) >> 8);
    end

    comb_dyn_scale = calc_dyn_scale(comb_absmax, prec_q);
    comb_m_new     = (cont_mode_q && ($signed(softmax_max_o) > comb_max)) ? $signed(softmax_max_o) : comb_max;
    comb_old_exp   = pwl_exp_q88(sext16(softmax_max_o) - sext16(comb_m_new));
    comb_l_scaled  = cont_mode_q ? ((softmax_sum_o * {16'd0, comb_old_exp}) >> 8) : 32'd0;
    comb_l_new     = comb_l_scaled;

    for (int i = 0; i < 8; i++) begin
      comb_exp_lane[(i*16) +: 16] = pwl_exp_q88(sext16(a_q[(i*16) +: 16]) - sext16(comb_m_new));
      comb_l_new                  = comb_l_new + {16'd0, comb_exp_lane[(i*16) +: 16]};
    end
    if (comb_l_new == 32'd0) comb_l_new = 32'd1;

    comb_mean_sq = (comb_sq_sum >> 3) + 32'd1;
    comb_rsqrt   = rsqrt_lut_nr_q88(comb_mean_sq);
  end

  // ---------------------------------------------------------------------------
  // 4. Stage 2 Pure Automatic Function for 8-Lane Vector Output
  // ---------------------------------------------------------------------------
  function automatic logic [127:0] calc_s2_vec(
    input mlu_pkg::mlu_opcode_e op_v,
    input mlu_pkg::mlu_prec_e   prec_v,
    input logic [127:0]         va,
    input logic [127:0]         vb,
    input logic [127:0]         vlut,
    input logic [127:0]         vexp,
    input logic [31:0]          l_denom,
    input logic signed [15:0]   rsqrt_v,
    input logic [15:0]          dscale_v
  );
    logic [127:0]       res;
    logic [31:0]        denom_safe;
    logic signed [31:0] sc_safe;
    logic [31:0]        p_val;
    logic signed [31:0] nx;
    logic signed [31:0] silu_v;
    logic signed [31:0] qv;
    res        = 128'd0;
    denom_safe = (l_denom == 32'd0) ? 32'd1 : l_denom;
    sc_safe    = (dscale_v == 16'd0) ? $signed(32'd1) : $signed({16'd0, dscale_v});
    p_val      = 32'd0;
    nx         = $signed(32'd0);
    silu_v     = $signed(32'd0);
    qv         = $signed(32'd0);

    unique case (op_v)
      mlu_pkg::OP_BANG_VADD: begin
        for (int i = 0; i < 8; i++)
          res[(i*16) +: 16] = sat_s16(sext16(va[(i*16) +: 16]) + sext16(vb[(i*16) +: 16]));
      end
      mlu_pkg::OP_BANG_VMUL: begin
        for (int i = 0; i < 8; i++)
          res[(i*16) +: 16] = sat_s16((sext16(va[(i*16) +: 16]) * sext16(vb[(i*16) +: 16])) >>> 8);
      end
      mlu_pkg::OP_BANG_SOFTMAX: begin
        for (int i = 0; i < 8; i++) begin
          p_val             = ({16'd0, vexp[(i*16) +: 16]} << 8) / denom_safe;
          res[(i*16) +: 16] = (p_val > 32'd256) ? 16'd256 : p_val[15:0];
        end
      end
      mlu_pkg::OP_BANG_ROPE: begin
        for (int k = 0; k < 4; k++) begin
          res[(2*k*16) +: 16]     = sat_s16((sext16(va[(2*k*16) +: 16])     * sext16(vlut[(2*k*16) +: 16]) -
                                             sext16(va[((2*k+1)*16) +: 16]) * sext16(vlut[((2*k+1)*16) +: 16])) >>> 8);
          res[((2*k+1)*16) +: 16] = sat_s16((sext16(va[(2*k*16) +: 16])     * sext16(vlut[((2*k+1)*16) +: 16]) +
                                             sext16(va[((2*k+1)*16) +: 16]) * sext16(vlut[(2*k*16) +: 16])) >>> 8);
        end
      end
      mlu_pkg::OP_BANG_RMSNORM: begin
        for (int i = 0; i < 8; i++) begin
          nx                = (sext16(va[(i*16) +: 16]) * sext16(rsqrt_v)) >>> 8;
          res[(i*16) +: 16] = sat_s16((nx * sext16(vb[(i*16) +: 16])) >>> 8);
        end
      end
      mlu_pkg::OP_BANG_SWIGLU: begin
        for (int i = 0; i < 8; i++) begin
          silu_v            = (sext16(va[(i*16) +: 16]) * sext16(pwl_sigmoid_q88(va[(i*16) +: 16]))) >>> 8;
          res[(i*16) +: 16] = sat_s16((silu_v * sext16(vb[(i*16) +: 16])) >>> 8);
        end
      end
      mlu_pkg::OP_BANG_QUANT_STAT: begin
        for (int i = 0; i < 8; i++) begin
          qv = sext16(va[(i*16) +: 16]) / sc_safe;
          if (prec_v == mlu_pkg::PREC_INT4) begin
            res[(i*16) +: 16] = (qv > $signed(32'd7)) ? $signed(16'd7) :
                                ((qv < -$signed(32'd8)) ? -$signed(16'd8) : $signed(qv[15:0]));
          end else begin
            res[(i*16) +: 16] = (qv > $signed(32'd127)) ? $signed(16'd127) :
                                ((qv < -$signed(32'd128)) ? -$signed(16'd128) : $signed(qv[15:0]));
          end
        end
      end
      default: res = va;
    endcase
    calc_s2_vec = res;
  endfunction

  // ---------------------------------------------------------------------------
  // 5. Sequential Pipeline Control & Output Register Stage
  // ---------------------------------------------------------------------------
  logic [127:0] s2_vec_res;
  assign s2_vec_res = calc_s2_vec(op_q, prec_q, a_q, b_q, lut_q, s1_exp_q,
                                  s1_l_new_q, s1_rsqrt_q, s1_dyn_scale_q);

  mlu_pkg::mlu_inst_t dec_cmd;
  assign dec_cmd = cmd_inst_i;

  logic _unused_cmd_bits;
  assign _unused_cmd_bits = ^{dec_cmd.engine, dec_cmd.sparse_mode, dec_cmd.src_space,
                              dec_cmd.dst_space, dec_cmd.dep_mask, dec_cmd.dst_addr,
                              dec_cmd.src0_addr, dec_cmd.src1_or_strd[15:1], dec_cmd.len_or_dims};

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q         <= VFU_IDLE;
      op_q            <= mlu_pkg::OP_NOP;
      prec_q          <= mlu_pkg::PREC_FP16;
      tag_q           <= 8'd0;
      cont_mode_q     <= 1'b0;
      a_q             <= '0;
      b_q             <= '0;
      lut_q           <= '0;
      s1_max_q        <= $signed(16'd0);
      s1_min_q        <= $signed(16'd0);
      s1_absmax_q     <= 16'd0;
      s1_dyn_scale_q  <= 16'd1;
      s1_m_new_q      <= $signed(16'h8000);
      s1_l_new_q      <= 32'd0;
      s1_exp_q        <= '0;
      s1_rsqrt_q      <= $signed(16'd256);
      vec_out_o       <= 128'd0;
      vec_out_valid_o <= 1'b0;
      softmax_sum_o   <= 32'd0;
      softmax_max_o   <= 16'h8000;
      absmax_o        <= 16'd0;
      min_val_o       <= 16'd0;
      max_val_o       <= 16'd0;
      dyn_scale_o     <= 16'd1;
      done_valid_o    <= 1'b0;
      done_tag_o      <= 8'd0;
    end else begin
      vec_out_valid_o <= 1'b0;
      done_valid_o    <= 1'b0;

      unique case (state_q)
        VFU_IDLE: begin
          if (cmd_valid_i && cmd_ready_o) begin
            op_q        <= dec_cmd.opcode;
            prec_q      <= dec_cmd.prec;
            tag_q       <= dec_cmd.tag_id;
            cont_mode_q <= dec_cmd.src1_or_strd[0];
            a_q         <= vec_a_i;
            b_q         <= vec_b_i;
            lut_q       <= cos_sin_lut_i;
            state_q     <= VFU_S1;
          end
        end

        VFU_S1: begin
          s1_max_q       <= comb_max;
          s1_min_q       <= comb_min;
          s1_absmax_q    <= comb_absmax;
          s1_dyn_scale_q <= comb_dyn_scale;
          s1_m_new_q     <= comb_m_new;
          s1_l_new_q     <= comb_l_new;
          s1_exp_q       <= comb_exp_lane;
          s1_rsqrt_q     <= comb_rsqrt;
          state_q        <= VFU_S2;
        end

        VFU_S2: begin
          vec_out_o       <= s2_vec_res;
          vec_out_valid_o <= 1'b1;
          done_valid_o    <= 1'b1;
          done_tag_o      <= tag_q;

          if (op_q == mlu_pkg::OP_BANG_SOFTMAX) begin
            softmax_max_o <= s1_m_new_q;
            softmax_sum_o <= s1_l_new_q;
          end

          if (op_q == mlu_pkg::OP_BANG_QUANT_STAT) begin
            absmax_o    <= s1_absmax_q;
            min_val_o   <= s1_min_q;
            max_val_o   <= s1_max_q;
            dyn_scale_o <= s1_dyn_scale_q;
          end

          state_q <= VFU_IDLE;
        end

        default: state_q <= VFU_IDLE;
      endcase
    end
  end

endmodule : mlu_vfu_sfu_pipe
