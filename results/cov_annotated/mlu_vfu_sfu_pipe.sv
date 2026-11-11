//      // verilator_coverage annotation
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
 002412   input  logic         clk_i,
%000004   input  logic         rst_ni,
        
          // Dispatched VFU Command Interface (from BANG ICU)
~000560   input  logic         cmd_valid_i,
~000561   output logic         cmd_ready_o,
~000280   input  logic [127:0] cmd_inst_i,
        
          // 8-Lane x 16-bit (128-bit) Vector Operands & RoPE Sin/Cos Lookup Table Input
~000494   input  logic [127:0] vec_a_i,
~000428   input  logic [127:0] vec_b_i,
~000423   input  logic [127:0] cos_sin_lut_i,
        
          // 8-Lane x 16-bit (128-bit) Vector Result & Valid Output
~000565   output logic [127:0] vec_out_o,
~000560   output logic         vec_out_valid_o,
        
          // FlashAttention Online Safe Softmax Running State Outputs
~000031   output logic [31:0]  softmax_sum_o,
~000019   output logic [15:0]  softmax_max_o,
        
          // Cambricon-Q Dynamic Statistical Quantizer Outputs
~000022   output logic [15:0]  absmax_o,
~000021   output logic [15:0]  min_val_o,
~000022   output logic [15:0]  max_val_o,
~000025   output logic [15:0]  dyn_scale_o,
        
          // Status & ICU Completion Handshake
~000560   output logic         vfu_busy_o,
~000560   output logic         done_valid_o,
~000280   output logic [7:0]   done_tag_o
        );
        
          // ---------------------------------------------------------------------------
          // 1. Helper Functions: Sign-Extend, Saturating Clamp, PWL Exp/Sigmoid, Rsqrt
          // ---------------------------------------------------------------------------
 067688   function automatic logic signed [31:0] sext16(input logic [15:0] v);
 067688     sext16 = $signed({{16{v[15]}}, v});
          endfunction
        
 030544   function automatic logic signed [15:0] sat_s16(input logic signed [31:0] val);
~001890     if (val > $signed(32'd32767)) begin
~001890       sat_s16 = $signed(16'd32767);
~030544     end else if (val < -$signed(32'd32768)) begin
~001938       sat_s16 = $signed(16'h8000);
 030544     end else begin
 030544       sat_s16 = $signed(val[15:0]);
            end
          endfunction
        
 059134   function automatic logic [15:0] abs_s16(input logic [15:0] xi);
 059134     logic [15:0] neg_xi;
 059134     neg_xi = ~xi + 16'd1;
~000168     if (xi == 16'h8000) begin
~000168       abs_s16 = 16'd32767;
 055914     end else if (xi[15]) begin
 021939       abs_s16 = neg_xi;
 055914     end else begin
 055914       abs_s16 = xi;
            end
          endfunction
        
          // 6-Segment Piecewise-Linear Approximation of exp(d) for d <= 0 in Q8.8
          // Returns unsigned Q8.8 value in [1 .. 256], where 256 == 1.0
 021744   function automatic logic [15:0] pwl_exp_q88(input logic signed [31:0] d32);
 021744     logic signed [31:0] y;
 016613     if (d32 >= $signed(32'd0)) begin
 016613       y = $signed(32'd256);
 002990     end else if (d32 >= -$signed(32'd256)) begin
 002990       y = $signed(32'd256) + (($signed(32'd162) * d32) >>> 8);
~000333     end else if (d32 >= -$signed(32'd512)) begin
~000333       y = $signed(32'd94)  + (($signed(32'd59)  * (d32 + $signed(32'd256))) >>> 8);
~000169     end else if (d32 >= -$signed(32'd768)) begin
~000169       y = $signed(32'd35)  + (($signed(32'd22)  * (d32 + $signed(32'd512))) >>> 8);
 000230     end else if (d32 >= -$signed(32'd1024)) begin
 000230       y = $signed(32'd13)  + (($signed(32'd8)   * (d32 + $signed(32'd768))) >>> 8);
 010548     end else if (d32 >= -$signed(32'd1536)) begin
 000230       y = $signed(32'd5)   + (($signed(32'd2)   * (d32 + $signed(32'd1024))) >>> 8);
 010548     end else begin
 010548       y = $signed(32'd1);
            end
 021744     pwl_exp_q88 = sat_s16((y < $signed(32'd1)) ? $signed(32'd1) :
                                  ((y > $signed(32'd256)) ? $signed(32'd256) : y));
          endfunction
        
          // Piecewise-Linear Approximation of sigmoid(g) in Q8.8 -> [0 .. 256]
 002200   function automatic logic signed [15:0] pwl_sigmoid_q88(input logic [15:0] g_q88);
 002200     logic signed [31:0] g32;
 002200     logic signed [31:0] abs_g;
 002200     logic signed [31:0] pos_sig;
 002200     g32   = sext16(g_q88);
 002200     abs_g = (g32 < $signed(32'd0)) ? -g32 : g32;
 001280     if (abs_g <= $signed(32'd256)) begin
 001280       pos_sig = $signed(32'd128) + (($signed(32'd60) * abs_g) >>> 8);
~000230     end else if (abs_g <= $signed(32'd512)) begin
~000230       pos_sig = $signed(32'd188) + (($signed(32'd38) * (abs_g - $signed(32'd256))) >>> 8);
~001587     end else if (abs_g <= $signed(32'd1024)) begin
~000072       pos_sig = $signed(32'd226) + (($signed(32'd25) * (abs_g - $signed(32'd512))) >>> 9);
~001587     end else begin
~001587       pos_sig = $signed(32'd256);
            end
 002200     pwl_sigmoid_q88 = sat_s16((g32 < $signed(32'd0)) ? ($signed(32'd256) - pos_sig) : pos_sig);
          endfunction
        
          // Fast LUT Seed + 1-Iteration Newton-Raphson Reciprocal Square Root in Q8.8
 002416   function automatic logic signed [15:0] rsqrt_lut_nr_q88(input logic [31:0] var_q88);
 002416     logic [31:0] v_safe;
 002416     logic [31:0] y0;
 002416     logic [63:0] v_y0_sq;
 002416     logic [63:0] term;
 002416     logic [63:0] y1;
 002416     v_safe = (var_q88 == 32'd0) ? 32'd1 : var_q88;
 002186     if      (v_safe < 32'd16)    y0 = 32'd1448;
~000021     else if (v_safe < 32'd64)    y0 = 32'd724;
~000021     else if (v_safe < 32'd128)   y0 = 32'd418;
~000021     else if (v_safe < 32'd192)   y0 = 32'd324;
~000021     else if (v_safe < 32'd320)   y0 = 32'd256;
~000021     else if (v_safe < 32'd512)   y0 = 32'd202;
~000021     else if (v_safe < 32'd768)   y0 = 32'd162;
~000021     else if (v_safe < 32'd1280)  y0 = 32'd128;
~000021     else if (v_safe < 32'd2560)  y0 = 32'd96;
 000230     else if (v_safe < 32'd5120)  y0 = 32'd68;
~001449     else if (v_safe < 32'd10240) y0 = 32'd48;
~001449     else                         y0 = 32'd32;
        
 002416     v_y0_sq = ({32'd0, v_safe} * {32'd0, y0} * {32'd0, y0}) >> 16;
 002416     term    = (v_y0_sq >= 64'd760) ? 64'd8 : (64'd768 - v_y0_sq);
 002416     y1      = ({32'd0, y0} * term) >> 9;
~001428     if (y1 == 64'd0) begin
~001428       rsqrt_lut_nr_q88 = $signed(16'd1);
~002416     end else if (y1 > 64'd32767) begin
%000000       rsqrt_lut_nr_q88 = $signed(16'd32767);
 002416     end else begin
 002416       rsqrt_lut_nr_q88 = $signed(y1[15:0]);
            end
          endfunction
        
 002416   function automatic logic [15:0] calc_dyn_scale(
            input logic [15:0]        absmax_v,
            input mlu_pkg::mlu_prec_e prec_v
          );
 002416     logic [31:0] sc;
 002416     sc = (prec_v == mlu_pkg::PREC_INT4) ? ({16'd0, absmax_v} / 32'd7)
                                                : ({16'd0, absmax_v} / 32'd127);
 002186     if (absmax_v == 16'd0 || sc == 32'd0) begin
 002186       calc_dyn_scale = 16'd1;
~001659     end else if (sc > 32'd65535) begin
%000000       calc_dyn_scale = 16'hFFFF;
 001659     end else begin
 001659       calc_dyn_scale = sc[15:0];
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
        
~000560   vfu_state_e           state_q;
~000240   mlu_pkg::mlu_opcode_e op_q;
~000040   mlu_pkg::mlu_prec_e   prec_q;
~000280   logic [7:0]           tag_q;
~000040   logic                 cont_mode_q;
~000494   logic [127:0]         a_q;
~000428   logic [127:0]         b_q;
~000423   logic [127:0]         lut_q;
        
~000127   logic signed [15:0]   s1_max_q;
~000131   logic signed [15:0]   s1_min_q;
~000127   logic [15:0]          s1_absmax_q;
~000126   logic [15:0]          s1_dyn_scale_q;
~000129   logic signed [15:0]   s1_m_new_q;
~000079   logic [31:0]          s1_l_new_q;
~000232   logic [127:0]         s1_exp_q;
%000005   logic signed [15:0]   s1_rsqrt_q;
        
          assign cmd_ready_o = (state_q == VFU_IDLE);
          assign vfu_busy_o  = (state_q != VFU_IDLE);
        
          // ---------------------------------------------------------------------------
          // 3. Stage 1 Combinational Reductions (Max/Min/AbsMax, Softmax Exp, RMS Var)
          // ---------------------------------------------------------------------------
~000127   logic signed [15:0] comb_max;
~000131   logic signed [15:0] comb_min;
~000127   logic [15:0]        comb_absmax;
~000126   logic [15:0]        comb_dyn_scale;
~000129   logic signed [15:0] comb_m_new;
~000114   logic [15:0]        comb_old_exp;
~000232   logic [127:0]       comb_exp_lane;
~000038   logic [31:0]        comb_l_scaled;
~000083   logic [31:0]        comb_l_new;
~000126   logic [31:0]        comb_sq_sum;
~000127   logic [31:0]        comb_mean_sq;
%000005   logic signed [15:0] comb_rsqrt;
        
 002416   always_comb begin
 002416     comb_max       = $signed(a_q[15:0]);
 002416     comb_min       = $signed(a_q[15:0]);
 002416     comb_absmax    = 16'd0;
 002416     comb_sq_sum    = 32'd0;
 002416     comb_dyn_scale = 16'd1;
 002416     comb_m_new     = $signed(a_q[15:0]);
 002416     comb_old_exp   = 16'd256;
 002416     comb_exp_lane  = 128'd0;
 002416     comb_l_scaled  = 32'd0;
 002416     comb_l_new     = 32'd1;
 002416     comb_mean_sq   = 32'd1;
 002416     comb_rsqrt     = $signed(16'd256);
        
 019328     for (int i = 0; i < 8; i++) begin
 018868       if ($signed(a_q[(i*16) +: 16]) > comb_max) comb_max = $signed(a_q[(i*16) +: 16]);
 018638       if ($signed(a_q[(i*16) +: 16]) < comb_min) comb_min = $signed(a_q[(i*16) +: 16]);
 018408       if (abs_s16(a_q[(i*16) +: 16]) > comb_absmax) comb_absmax = abs_s16(a_q[(i*16) +: 16]);
 019328       comb_sq_sum = comb_sq_sum + (({16'd0, abs_s16(a_q[(i*16) +: 16])} *
 019328                                     {16'd0, abs_s16(a_q[(i*16) +: 16])}) >> 8);
            end
        
 002416     comb_dyn_scale = calc_dyn_scale(comb_absmax, prec_q);
 002416     comb_m_new     = (cont_mode_q && ($signed(softmax_max_o) > comb_max)) ? $signed(softmax_max_o) : comb_max;
 002416     comb_old_exp   = pwl_exp_q88(sext16(softmax_max_o) - sext16(comb_m_new));
 002416     comb_l_scaled  = cont_mode_q ? ((softmax_sum_o * {16'd0, comb_old_exp}) >> 8) : 32'd0;
 002416     comb_l_new     = comb_l_scaled;
        
 019328     for (int i = 0; i < 8; i++) begin
 019328       comb_exp_lane[(i*16) +: 16] = pwl_exp_q88(sext16(a_q[(i*16) +: 16]) - sext16(comb_m_new));
 019328       comb_l_new                  = comb_l_new + {16'd0, comb_exp_lane[(i*16) +: 16]};
            end
~002416     if (comb_l_new == 32'd0) comb_l_new = 32'd1;
        
 002416     comb_mean_sq = (comb_sq_sum >> 3) + 32'd1;
 002416     comb_rsqrt   = rsqrt_lut_nr_q88(comb_mean_sq);
          end
        
          // ---------------------------------------------------------------------------
          // 4. Stage 2 Pure Automatic Function for 8-Lane Vector Output
          // ---------------------------------------------------------------------------
 002416   function automatic logic [127:0] calc_s2_vec(
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
 002416     logic [127:0]       res;
 002416     logic [31:0]        denom_safe;
 002416     logic signed [31:0] sc_safe;
 002416     logic [31:0]        p_val;
 002416     logic signed [31:0] nx;
 002416     logic signed [31:0] silu_v;
 002416     logic signed [31:0] qv;
 002416     res        = 128'd0;
 002416     denom_safe = (l_denom == 32'd0) ? 32'd1 : l_denom;
 002416     sc_safe    = (dscale_v == 16'd0) ? $signed(32'd1) : $signed({16'd0, dscale_v});
 002416     p_val      = 32'd0;
 002416     nx         = $signed(32'd0);
 002416     silu_v     = $signed(32'd0);
 002416     qv         = $signed(32'd0);
        
 002416     unique case (op_v)
~000240       mlu_pkg::OP_BANG_VADD: begin
~001920         for (int i = 0; i < 8; i++)
~001920           res[(i*16) +: 16] = sat_s16(sext16(va[(i*16) +: 16]) + sext16(vb[(i*16) +: 16]));
              end
~000240       mlu_pkg::OP_BANG_VMUL: begin
~001920         for (int i = 0; i < 8; i++)
~001920           res[(i*16) +: 16] = sat_s16((sext16(va[(i*16) +: 16]) * sext16(vb[(i*16) +: 16])) >>> 8);
              end
 000275       mlu_pkg::OP_BANG_SOFTMAX: begin
 002200         for (int i = 0; i < 8; i++) begin
 002200           p_val             = ({16'd0, vexp[(i*16) +: 16]} << 8) / denom_safe;
 002200           res[(i*16) +: 16] = (p_val > 32'd256) ? 16'd256 : p_val[15:0];
                end
              end
 000275       mlu_pkg::OP_BANG_ROPE: begin
 001100         for (int k = 0; k < 4; k++) begin
 001100           res[(2*k*16) +: 16]     = sat_s16((sext16(va[(2*k*16) +: 16])     * sext16(vlut[(2*k*16) +: 16]) -
 001100                                              sext16(va[((2*k+1)*16) +: 16]) * sext16(vlut[((2*k+1)*16) +: 16])) >>> 8);
 001100           res[((2*k+1)*16) +: 16] = sat_s16((sext16(va[(2*k*16) +: 16])     * sext16(vlut[((2*k+1)*16) +: 16]) +
 001100                                              sext16(va[((2*k+1)*16) +: 16]) * sext16(vlut[(2*k*16) +: 16])) >>> 8);
                end
              end
 000275       mlu_pkg::OP_BANG_RMSNORM: begin
 002200         for (int i = 0; i < 8; i++) begin
 002200           nx                = (sext16(va[(i*16) +: 16]) * sext16(rsqrt_v)) >>> 8;
 002200           res[(i*16) +: 16] = sat_s16((nx * sext16(vb[(i*16) +: 16])) >>> 8);
                end
              end
 000275       mlu_pkg::OP_BANG_SWIGLU: begin
 002200         for (int i = 0; i < 8; i++) begin
 002200           silu_v            = (sext16(va[(i*16) +: 16]) * sext16(pwl_sigmoid_q88(va[(i*16) +: 16]))) >>> 8;
 002200           res[(i*16) +: 16] = sat_s16((silu_v * sext16(vb[(i*16) +: 16])) >>> 8);
                end
              end
~000240       mlu_pkg::OP_BANG_QUANT_STAT: begin
~001920         for (int i = 0; i < 8; i++) begin
~001920           qv = sext16(va[(i*16) +: 16]) / sc_safe;
~001840           if (prec_v == mlu_pkg::PREC_INT4) begin
~000960             res[(i*16) +: 16] = (qv > $signed(32'd7)) ? $signed(16'd7) :
                                        ((qv < -$signed(32'd8)) ? -$signed(16'd8) : $signed(qv[15:0]));
~001840           end else begin
~001840             res[(i*16) +: 16] = (qv > $signed(32'd127)) ? $signed(16'd127) :
                                        ((qv < -$signed(32'd128)) ? -$signed(16'd128) : $signed(qv[15:0]));
                  end
                end
              end
~001546       default: res = va;
            endcase
 002416     calc_s2_vec = res;
          endfunction
        
          // ---------------------------------------------------------------------------
          // 5. Sequential Pipeline Control & Output Register Stage
          // ---------------------------------------------------------------------------
~000637   logic [127:0] s2_vec_res;
          assign s2_vec_res = calc_s2_vec(op_q, prec_q, a_q, b_q, lut_q, s1_exp_q,
                                          s1_l_new_q, s1_rsqrt_q, s1_dyn_scale_q);
        
~000280   mlu_pkg::mlu_inst_t dec_cmd;
          assign dec_cmd = cmd_inst_i;
        
          logic _unused_cmd_bits;
          assign _unused_cmd_bits = ^{dec_cmd.engine, dec_cmd.sparse_mode, dec_cmd.src_space,
                                      dec_cmd.dst_space, dec_cmd.dep_mask, dec_cmd.dst_addr,
                                      dec_cmd.src0_addr, dec_cmd.src1_or_strd[15:1], dec_cmd.len_or_dims};
        
 002412   always_ff @(posedge clk_i or negedge rst_ni) begin
~002400     if (!rst_ni) begin
~000012       state_q         <= VFU_IDLE;
~000012       op_q            <= mlu_pkg::OP_NOP;
~000012       prec_q          <= mlu_pkg::PREC_FP16;
~000012       tag_q           <= 8'd0;
~000012       cont_mode_q     <= 1'b0;
~000012       a_q             <= '0;
~000012       b_q             <= '0;
~000012       lut_q           <= '0;
~000012       s1_max_q        <= $signed(16'd0);
~000012       s1_min_q        <= $signed(16'd0);
~000012       s1_absmax_q     <= 16'd0;
~000012       s1_dyn_scale_q  <= 16'd1;
~000012       s1_m_new_q      <= $signed(16'h8000);
~000012       s1_l_new_q      <= 32'd0;
~000012       s1_exp_q        <= '0;
~000012       s1_rsqrt_q      <= $signed(16'd256);
~000012       vec_out_o       <= 128'd0;
~000012       vec_out_valid_o <= 1'b0;
~000012       softmax_sum_o   <= 32'd0;
~000012       softmax_max_o   <= 16'h8000;
~000012       absmax_o        <= 16'd0;
~000012       min_val_o       <= 16'd0;
~000012       max_val_o       <= 16'd0;
~000012       dyn_scale_o     <= 16'd1;
~000012       done_valid_o    <= 1'b0;
~000012       done_tag_o      <= 8'd0;
 002400     end else begin
 002400       vec_out_valid_o <= 1'b0;
 002400       done_valid_o    <= 1'b0;
        
 002400       unique case (state_q)
 002384         VFU_IDLE: begin
~002376           if (cmd_valid_i && cmd_ready_o) begin
~000560             op_q        <= dec_cmd.opcode;
~000560             prec_q      <= dec_cmd.prec;
~000560             tag_q       <= dec_cmd.tag_id;
~000560             cont_mode_q <= dec_cmd.src1_or_strd[0];
~000560             a_q         <= vec_a_i;
~000560             b_q         <= vec_b_i;
~000560             lut_q       <= cos_sin_lut_i;
~000560             state_q     <= VFU_S1;
                  end
                end
        
~000560         VFU_S1: begin
~000560           s1_max_q       <= comb_max;
~000560           s1_min_q       <= comb_min;
~000560           s1_absmax_q    <= comb_absmax;
~000560           s1_dyn_scale_q <= comb_dyn_scale;
~000560           s1_m_new_q     <= comb_m_new;
~000560           s1_l_new_q     <= comb_l_new;
~000560           s1_exp_q       <= comb_exp_lane;
~000560           s1_rsqrt_q     <= comb_rsqrt;
~000560           state_q        <= VFU_S2;
                end
        
~000560         VFU_S2: begin
~000560           vec_out_o       <= s2_vec_res;
~000560           vec_out_valid_o <= 1'b1;
~000560           done_valid_o    <= 1'b1;
~000560           done_tag_o      <= tag_q;
        
~000480           if (op_q == mlu_pkg::OP_BANG_SOFTMAX) begin
~000080             softmax_max_o <= s1_m_new_q;
~000080             softmax_sum_o <= s1_l_new_q;
                  end
        
~000480           if (op_q == mlu_pkg::OP_BANG_QUANT_STAT) begin
~000080             absmax_o    <= s1_absmax_q;
~000080             min_val_o   <= s1_min_q;
~000080             max_val_o   <= s1_max_q;
~000080             dyn_scale_o <= s1_dyn_scale_q;
                  end
        
~000560           state_q <= VFU_IDLE;
                end
        
%000000         default: state_q <= VFU_IDLE;
              endcase
            end
          end
        
        endmodule : mlu_vfu_sfu_pipe
        
