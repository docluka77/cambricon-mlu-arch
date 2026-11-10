// =============================================================================
// File: rtl/mlu_tfu_fractal_mac.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Stage 4 — Tensor Function Unit (TFU): Fractal Multi-Precision
//              Sparse & Quantized MAC Engine. Supports INT4 (64x), INT8 (32x),
//              FP8 E4M3/E5M2 (32x), FP16/BF16 (16x), and TF32/FP32 (8x) dot
//              products, Cambricon-S 2:4 & 4x4 Block Sparsity, and Cambricon-Q
//              Statistical Quantized Matrix Multiplication (OP_BANG_QUANT_MM).
// =============================================================================
`include "mlu_pkg.sv"

module mlu_tfu_fractal_mac (
  input  logic         clk_i,
  input  logic         rst_ni,

  // Dispatched TFU Command Interface (from BANG ICU)
  input  logic         cmd_valid_i,
  output logic         cmd_ready_o,
  input  logic [127:0] cmd_inst_i,

  // NRAM Activation & WRAM Weight + Sparsity Metadata Stream
  input  logic         stream_valid_i,
  output logic         stream_ready_o,
  input  logic [255:0] nram_act_i,
  input  logic [255:0] wram_wt_i,
  input  logic [31:0]  wram_sparse_meta_i,

  // Cambricon-Q Dynamic Quantization Parameters (Scale Q8.8 & Signed Zero-Point)
  input  logic [15:0]  quant_scale_i,
  input  logic [7:0]   quant_zp_i,

  // Status, Output Tile Result, and ICU Completion Interface
  output logic         tfu_busy_o,
  output logic [255:0] result_data_o,
  output logic         result_valid_o,
  output logic         done_valid_o,
  output logic [7:0]   done_tag_o,

  // Hardware Sparsity & Compute Telemetry Counters
  output logic [31:0]  zero_skip_cnt_o,
  output logic [31:0]  total_mac_ops_o
);

  // ---------------------------------------------------------------------------
  // 1. Command State Machine & Latched Instruction Fields
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    TFU_IDLE   = 2'b00,
    TFU_STREAM = 2'b01,
    TFU_WB     = 2'b10
  } tfu_state_e;

  tfu_state_e                state_q;
  mlu_pkg::mlu_opcode_e      op_q;
  mlu_pkg::mlu_prec_e        prec_q;
  mlu_pkg::mlu_sparse_mode_e sparse_q;
  logic [7:0]                tag_q;
  logic [15:0]               beats_rem_q;
  logic [3:0]                beat_idx_q;
  logic [7:0][31:0]          acc_tile_q;

  mlu_pkg::mlu_inst_t cmd_inst_dec;
  assign cmd_inst_dec   = cmd_inst_i;
  assign cmd_ready_o    = (state_q == TFU_IDLE);
  assign stream_ready_o = (state_q == TFU_STREAM);
  assign tfu_busy_o     = (state_q != TFU_IDLE);

  // ---------------------------------------------------------------------------
  // 2. Cambricon-S 2:4 Structured Sparsity & Step-Index Activation Gather Mux
  // ---------------------------------------------------------------------------
  logic [255:0] eff_act_bytes;
  logic         block_is_zero;

  // In SPARSE_BLOCK_4X4 mode, bit [beat_idx_q] of wram_sparse_meta_i[15:0] is the
  // non-zero bitmap flag for the current 4x4 block (0 = all-zero block -> skip).
  assign block_is_zero = (sparse_q == mlu_pkg::SPARSE_BLOCK_4X4) &&
                         (!wram_sparse_meta_i[{1'b0, beat_idx_q}] || (wram_wt_i == 256'd0));

  always_comb begin
    eff_act_bytes = nram_act_i;
    if (sparse_q == mlu_pkg::SPARSE_2_OF_4 || sparse_q == mlu_pkg::SPARSE_INDEXED) begin
      // 16 groups of 2:4 selection across lower 16 lanes (and mirrored to upper 16 lanes)
      for (int g = 0; g < 8; g++) begin
        eff_act_bytes[(g * 16) +: 8]           = nram_act_i[({24'd0, g[2:0], wram_sparse_meta_i[(g * 4) +: 2], 3'b000}) +: 8];
        eff_act_bytes[(g * 16 + 8) +: 8]       = nram_act_i[({24'd0, g[2:0], wram_sparse_meta_i[(g * 4 + 2) +: 2], 3'b000}) +: 8];
        eff_act_bytes[(128 + g * 16) +: 8]     = nram_act_i[({24'd0, g[2:0], wram_sparse_meta_i[(g * 4) +: 2], 3'b000}) +: 8];
        eff_act_bytes[(128 + g * 16 + 8) +: 8] = nram_act_i[({24'd0, g[2:0], wram_sparse_meta_i[(g * 4 + 2) +: 2], 3'b000}) +: 8];
      end
    end
  end

  // ---------------------------------------------------------------------------
  // 3. Multi-Precision Fractal Dot-Product Helper Functions (Q25.6 Output Scale)
  // ---------------------------------------------------------------------------
  // Decode 8-bit FP8 E4M3 (1s-4e-3m, bias=7) to signed 32-bit (scale 2^9)
  function automatic logic signed [31:0] decode_fp8_e4m3(input logic [7:0] val);
    logic        s;
    logic [3:0]  e;
    logic [2:0]  m;
    logic [30:0] mag;
    s = val[7];
    e = val[6:3];
    m = val[2:0];
    if (e == 4'd0) begin
      mag = {28'd0, m};
    end else begin
      mag = ({27'd0, 1'b1, m}) << (e - 4'd1);
    end
    decode_fp8_e4m3 = s ? -$signed({1'b0, mag}) : $signed({1'b0, mag});
  endfunction

  // Decode 8-bit FP8 E5M2 (1s-5e-2m, bias=15) to signed 32-bit
  function automatic logic signed [31:0] decode_fp8_e5m2(input logic [7:0] val);
    logic        s;
    logic [4:0]  e;
    logic [1:0]  m;
    logic [4:0]  sh;
    logic [30:0] mag;
    s  = val[7];
    e  = val[6:2];
    m  = val[1:0];
    sh = (e > 5'd24) ? 5'd17 : ((e > 5'd7) ? (e - 5'd7) : 5'd0);
    if (e == 5'd0) begin
      mag = {29'd0, m};
    end else begin
      mag = ({28'd0, 1'b1, m}) << sh;
    end
    decode_fp8_e5m2 = s ? -$signed({1'b0, mag}) : $signed({1'b0, mag});
  endfunction

  // Decode 16-bit FP16 (1s-5e-10m, bias=15) or BF16 (1s-8e-7m, bias=127)
  // into signed 32-bit aligned value (scale 2^14 at exp=bias)
  function automatic logic signed [31:0] decode_fp16_bf16(
    input logic [15:0] val,
    input logic        is_bf16
  );
    logic        s;
    logic [7:0]  e;
    logic [6:0]  m;
    logic [30:0] mag;
    s = val[15];
    if (is_bf16) begin
      e = val[14:7];
      m = val[6:0];
      if (e < 8'd120) begin
        mag = 31'd0;
      end else if (e >= 8'd138) begin
        mag = 31'h3FFF_FFFF;
      end else begin
        mag = ({23'd0, 1'b1, m}) << (e - 8'd120);
      end
    end else begin
      e = {3'b000, val[14:10]};
      m = val[9:3] | {6'd0, |val[2:0]};
      if (e < 8'd8) begin
        mag = 31'd0;
      end else if (e >= 8'd26) begin
        mag = 31'h3FFF_FFFF;
      end else begin
        mag = ({23'd0, 1'b1, m}) << (e - 8'd8);
      end
    end
    decode_fp16_bf16 = s ? -$signed({1'b0, mag}) : $signed({1'b0, mag});
  endfunction

  // ---------------------------------------------------------------------------
  // 4. Parallel Fractal MAC Tree Across All 8 Precision Modes
  // ---------------------------------------------------------------------------
  logic signed [31:0] dot_prod_comb;
  logic [31:0]        mac_ops_beat;

  always_comb begin
    dot_prod_comb = 32'sd0;
    mac_ops_beat  = 32'd32;
    if (!block_is_zero) begin
      unique case (prec_q)
        mlu_pkg::PREC_INT4: begin
          mac_ops_beat = 32'd64;
          for (int i = 0; i < 64; i++) begin
            dot_prod_comb = dot_prod_comb +
              ($signed({{28{eff_act_bytes[i * 4 + 3]}}, eff_act_bytes[(i * 4) +: 4]}) *
               $signed({{28{wram_wt_i[i * 4 + 3]}}, wram_wt_i[(i * 4) +: 4]}));
          end
        end
        mlu_pkg::PREC_INT8: begin
          mac_ops_beat = 32'd32;
          for (int i = 0; i < 32; i++) begin
            dot_prod_comb = dot_prod_comb +
              ($signed({{24{eff_act_bytes[i * 8 + 7]}}, eff_act_bytes[(i * 8) +: 8]}) *
               $signed({{24{wram_wt_i[i * 8 + 7]}}, wram_wt_i[(i * 8) +: 8]}));
          end
        end
        mlu_pkg::PREC_FP8_E4M3: begin
          mac_ops_beat = 32'd32;
          for (int i = 0; i < 32; i++) begin
            dot_prod_comb = dot_prod_comb +
              ((decode_fp8_e4m3(eff_act_bytes[(i * 8) +: 8]) *
                decode_fp8_e4m3(wram_wt_i[(i * 8) +: 8])) >>> 12);
          end
        end
        mlu_pkg::PREC_FP8_E5M2: begin
          mac_ops_beat = 32'd32;
          for (int i = 0; i < 32; i++) begin
            dot_prod_comb = dot_prod_comb +
              ((decode_fp8_e5m2(eff_act_bytes[(i * 8) +: 8]) *
                decode_fp8_e5m2(wram_wt_i[(i * 8) +: 8])) >>> 14);
          end
        end
        mlu_pkg::PREC_FP16, mlu_pkg::PREC_BF16: begin
          mac_ops_beat = 32'd16;
          for (int i = 0; i < 16; i++) begin
            dot_prod_comb = dot_prod_comb +
              ((decode_fp16_bf16(eff_act_bytes[(i * 16) +: 16], (prec_q == mlu_pkg::PREC_BF16)) *
                decode_fp16_bf16(wram_wt_i[(i * 16) +: 16], (prec_q == mlu_pkg::PREC_BF16))) >>> 22);
          end
        end
        default: begin
          mac_ops_beat = 32'd8;
          for (int i = 0; i < 8; i++) begin
            dot_prod_comb = dot_prod_comb +
              ((decode_fp16_bf16(eff_act_bytes[(i * 32 + 16) +: 16], 1'b1) *
                decode_fp16_bf16(wram_wt_i[(i * 32 + 16) +: 16], 1'b1) +
                $signed({16'd0, eff_act_bytes[(i * 32) +: 16] & wram_wt_i[(i * 32) +: 16]}) * 32'sd0) >>> 22);
          end
        end
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // 5. Cambricon-Q Statistical Quantizer (Scale Q8.8 + Zero-Point + Saturate)
  // ---------------------------------------------------------------------------
  function automatic logic signed [7:0] cambricon_q_quantize(
    input logic signed [31:0] acc_in,
    input logic [15:0]        scale_q8_8,
    input logic [7:0]         zp_in
  );
    logic signed [47:0] mult_full;
    logic signed [39:0] rounded;
    logic signed [39:0] shifted;
    mult_full = acc_in * $signed({1'b0, scale_q8_8});
    rounded   = $signed(mult_full[47:8]) + $signed({39'd0, (mult_full[7] && (|mult_full[6:0] || mult_full[8]))});
    shifted   = rounded + $signed({{32{zp_in[7]}}, zp_in});
    if (shifted > 40'sd127) begin
      cambricon_q_quantize = 8'sd127;
    end else if (shifted < -40'sd128) begin
      cambricon_q_quantize = -8'sd128;
    end else begin
      cambricon_q_quantize = shifted[7:0];
    end
  endfunction

  // Output data formatting:
  // If OP_BANG_QUANT_MM, lower 64 bits pack 8 quantized INT8 tile results and
  // upper 192 bits hold raw 32-bit accumulators [5:0]; otherwise all 8 x 32-bit
  // accumulators are driven on result_data_o[255:0].
  always_comb begin
    if (op_q == mlu_pkg::OP_BANG_QUANT_MM) begin
      for (int c = 0; c < 8; c++) begin
        result_data_o[(c * 8) +: 8] = cambricon_q_quantize($signed(acc_tile_q[c]), quant_scale_i, quant_zp_i);
      end
      for (int c = 0; c < 6; c++) begin
        result_data_o[(64 + c * 32) +: 32] = acc_tile_q[c];
      end
    end else begin
      for (int c = 0; c < 8; c++) begin
        result_data_o[(c * 32) +: 32] = acc_tile_q[c];
      end
    end
  end

  assign result_valid_o = (state_q == TFU_WB);
  assign done_valid_o   = (state_q == TFU_WB);
  assign done_tag_o     = tag_q;

  // ---------------------------------------------------------------------------
  // 6. Sequential Execution Pipeline & Telemetry Counters
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q         <= TFU_IDLE;
      op_q            <= mlu_pkg::OP_NOP;
      prec_q          <= mlu_pkg::PREC_INT8;
      sparse_q        <= mlu_pkg::SPARSE_DENSE;
      tag_q           <= 8'd0;
      beats_rem_q     <= 16'd0;
      beat_idx_q      <= 4'd0;
      for (int c = 0; c < 8; c++) begin
        acc_tile_q[c] <= 32'sd0;
      end
      zero_skip_cnt_o <= 32'd0;
      total_mac_ops_o <= 32'd0;
    end else begin
      unique case (state_q)
        TFU_IDLE: begin
          if (cmd_valid_i) begin
            op_q        <= cmd_inst_dec.opcode;
            prec_q      <= cmd_inst_dec.prec;
            sparse_q    <= cmd_inst_dec.sparse_mode;
            tag_q       <= cmd_inst_dec.tag_id;
            beats_rem_q <= (cmd_inst_dec.len_or_dims == 16'd0) ? 16'd1 : cmd_inst_dec.len_or_dims;
            beat_idx_q  <= 4'd0;
            for (int c = 0; c < 8; c++) begin
              acc_tile_q[c] <= 32'sd0;
            end
            state_q     <= TFU_STREAM;
          end
        end

        TFU_STREAM: begin
          if (stream_valid_i) begin
            if (block_is_zero) begin
              zero_skip_cnt_o <= zero_skip_cnt_o + 32'd1;
            end else begin
              acc_tile_q[0] <= acc_tile_q[0] + dot_prod_comb;
              if (beat_idx_q[2:0] != 3'd0) begin
                acc_tile_q[beat_idx_q[2:0]] <= acc_tile_q[beat_idx_q[2:0]] + dot_prod_comb;
              end
              total_mac_ops_o <= total_mac_ops_o + mac_ops_beat;
            end

            beat_idx_q <= beat_idx_q + 4'd1;
            if (beats_rem_q <= 16'd1) begin
              state_q <= TFU_WB;
            end else begin
              beats_rem_q <= beats_rem_q - 16'd1;
            end
          end
        end

        TFU_WB: begin
          state_q <= TFU_IDLE;
        end

        default: state_q <= TFU_IDLE;
      endcase
    end
  end

  wire _unused_ok = &{1'b0, cmd_inst_dec.engine, cmd_inst_dec.src_space,
                      cmd_inst_dec.dst_space, cmd_inst_dec.dep_mask,
                      cmd_inst_dec.dst_addr, cmd_inst_dec.src0_addr,
                      cmd_inst_dec.src1_or_strd};

endmodule : mlu_tfu_fractal_mac
