//      // verilator_coverage annotation
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
 002412   input  logic         clk_i,
%000004   input  logic         rst_ni,
        
          // Dispatched TFU Command Interface (from BANG ICU)
~000200   input  logic         cmd_valid_i,
~000201   output logic         cmd_ready_o,
~000100   input  logic [127:0] cmd_inst_i,
        
          // NRAM Activation & WRAM Weight + Sparsity Metadata Stream
~000200   input  logic         stream_valid_i,
~000200   output logic         stream_ready_o,
~002448   input  logic [255:0] nram_act_i,
~002466   input  logic [255:0] wram_wt_i,
~000247   input  logic [31:0]  wram_sparse_meta_i,
        
          // Cambricon-Q Dynamic Quantization Parameters (Scale Q8.8 & Signed Zero-Point)
~000100   input  logic [15:0]  quant_scale_i,
~000100   input  logic [7:0]   quant_zp_i,
        
          // Status, Output Tile Result, and ICU Completion Interface
~000200   output logic         tfu_busy_o,
~000617   output logic [255:0] result_data_o,
~000200   output logic         result_valid_o,
~000200   output logic         done_valid_o,
~000100   output logic [7:0]   done_tag_o,
        
          // Hardware Sparsity & Compute Telemetry Counters
~000050   output logic [31:0]  zero_skip_cnt_o,
~000195   output logic [31:0]  total_mac_ops_o
        );
        
          // ---------------------------------------------------------------------------
          // 1. Command State Machine & Latched Instruction Fields
          // ---------------------------------------------------------------------------
          typedef enum logic [1:0] {
            TFU_IDLE   = 2'b00,
            TFU_STREAM = 2'b01,
            TFU_WB     = 2'b10
          } tfu_state_e;
        
~000200   tfu_state_e                state_q;
~000066   mlu_pkg::mlu_opcode_e      op_q;
~000101   mlu_pkg::mlu_prec_e        prec_q;
~000072   mlu_pkg::mlu_sparse_mode_e sparse_q;
~000100   logic [7:0]                tag_q;
~000400   logic [15:0]               beats_rem_q;
~000400   logic [3:0]                beat_idx_q;
~000225   logic [7:0][31:0]          acc_tile_q;
        
~000100   mlu_pkg::mlu_inst_t cmd_inst_dec;
          assign cmd_inst_dec   = cmd_inst_i;
          assign cmd_ready_o    = (state_q == TFU_IDLE);
          assign stream_ready_o = (state_q == TFU_STREAM);
          assign tfu_busy_o     = (state_q != TFU_IDLE);
        
          // ---------------------------------------------------------------------------
          // 2. Cambricon-S 2:4 Structured Sparsity & Step-Index Activation Gather Mux
          // ---------------------------------------------------------------------------
~002751   logic [255:0] eff_act_bytes;
~000136   logic         block_is_zero;
        
          // In SPARSE_BLOCK_4X4 mode, bit [beat_idx_q] of wram_sparse_meta_i[15:0] is the
          // non-zero bitmap flag for the current 4x4 block (0 = all-zero block -> skip).
          assign block_is_zero = (sparse_q == mlu_pkg::SPARSE_BLOCK_4X4) &&
                                 (!wram_sparse_meta_i[{1'b0, beat_idx_q}] || (wram_wt_i == 256'd0));
        
 004804   always_comb begin
 004804     eff_act_bytes = nram_act_i;
 002407     if (sparse_q == mlu_pkg::SPARSE_2_OF_4 || sparse_q == mlu_pkg::SPARSE_INDEXED) begin
              // 16 groups of 2:4 selection across lower 16 lanes (and mirrored to upper 16 lanes)
 019176       for (int g = 0; g < 8; g++) begin
 019176         eff_act_bytes[(g * 16) +: 8]           = nram_act_i[({24'd0, g[2:0], wram_sparse_meta_i[(g * 4) +: 2], 3'b000}) +: 8];
 019176         eff_act_bytes[(g * 16 + 8) +: 8]       = nram_act_i[({24'd0, g[2:0], wram_sparse_meta_i[(g * 4 + 2) +: 2], 3'b000}) +: 8];
 019176         eff_act_bytes[(128 + g * 16) +: 8]     = nram_act_i[({24'd0, g[2:0], wram_sparse_meta_i[(g * 4) +: 2], 3'b000}) +: 8];
 019176         eff_act_bytes[(128 + g * 16 + 8) +: 8] = nram_act_i[({24'd0, g[2:0], wram_sparse_meta_i[(g * 4 + 2) +: 2], 3'b000}) +: 8];
              end
            end
          end
        
          // ---------------------------------------------------------------------------
          // 3. Multi-Precision Fractal Dot-Product Helper Functions (Q25.6 Output Scale)
          // ---------------------------------------------------------------------------
          // Decode 8-bit FP8 E4M3 (1s-4e-3m, bias=7) to signed 32-bit (scale 2^9)
~021632   function automatic logic signed [31:0] decode_fp8_e4m3(input logic [7:0] val);
~021632     logic        s;
~021632     logic [3:0]  e;
~021632     logic [2:0]  m;
~021632     logic [30:0] mag;
~021632     s = val[7];
~021632     e = val[6:3];
~021632     m = val[2:0];
~020181     if (e == 4'd0) begin
~001451       mag = {28'd0, m};
~020181     end else begin
~020181       mag = ({27'd0, 1'b1, m}) << (e - 4'd1);
            end
~021632     decode_fp8_e4m3 = s ? -$signed({1'b0, mag}) : $signed({1'b0, mag});
          endfunction
        
          // Decode 8-bit FP8 E5M2 (1s-5e-2m, bias=15) to signed 32-bit
~036352   function automatic logic signed [31:0] decode_fp8_e5m2(input logic [7:0] val);
~036352     logic        s;
~036352     logic [4:0]  e;
~036352     logic [1:0]  m;
~036352     logic [4:0]  sh;
~036352     logic [30:0] mag;
~036352     s  = val[7];
~036352     e  = val[6:2];
~036352     m  = val[1:0];
~036352     sh = (e > 5'd24) ? 5'd17 : ((e > 5'd7) ? (e - 5'd7) : 5'd0);
~035211     if (e == 5'd0) begin
~001141       mag = {29'd0, m};
~035211     end else begin
~035211       mag = ({28'd0, 1'b1, m}) << sh;
            end
~036352     decode_fp8_e5m2 = s ? -$signed({1'b0, mag}) : $signed({1'b0, mag});
          endfunction
        
          // Decode 16-bit FP16 (1s-5e-10m, bias=15) or BF16 (1s-8e-7m, bias=127)
          // into signed 32-bit aligned value (scale 2^14 at exp=bias)
 050464   function automatic logic signed [31:0] decode_fp16_bf16(
            input logic [15:0] val,
            input logic        is_bf16
          );
 050464     logic        s;
 050464     logic [7:0]  e;
 050464     logic [6:0]  m;
 050464     logic [30:0] mag;
 050464     s = val[15];
 032288     if (is_bf16) begin
 032288       e = val[14:7];
 032288       m = val[6:0];
 015121       if (e < 8'd120) begin
 015121         mag = 31'd0;
~014837       end else if (e >= 8'd138) begin
~014837         mag = 31'h3FFF_FFFF;
~002330       end else begin
~002330         mag = ({23'd0, 1'b1, m}) << (e - 8'd120);
              end
 018176     end else begin
 018176       e = {3'b000, val[14:10]};
 018176       m = val[9:3] | {6'd0, |val[2:0]};
 011040       if (e < 8'd8) begin
 011040         mag = 31'd0;
~010451       end else if (e >= 8'd26) begin
~003422         mag = 31'h3FFF_FFFF;
~010451       end else begin
~010451         mag = ({23'd0, 1'b1, m}) << (e - 8'd8);
              end
            end
 050464     decode_fp16_bf16 = s ? -$signed({1'b0, mag}) : $signed({1'b0, mag});
          endfunction
        
          // ---------------------------------------------------------------------------
          // 4. Parallel Fractal MAC Tree Across All 8 Precision Modes
          // ---------------------------------------------------------------------------
~000359   logic signed [31:0] dot_prod_comb;
~000097   logic [31:0]        mac_ops_beat;
        
 004804   always_comb begin
 004804     dot_prod_comb = 32'sd0;
 004804     mac_ops_beat  = 32'd32;
 004067     if (!block_is_zero) begin
 004067       unique case (prec_q)
 000569         mlu_pkg::PREC_INT4: begin
 000569           mac_ops_beat = 32'd64;
 036416           for (int i = 0; i < 64; i++) begin
 036416             dot_prod_comb = dot_prod_comb +
 036416               ($signed({{28{eff_act_bytes[i * 4 + 3]}}, eff_act_bytes[(i * 4) +: 4]}) *
 036416                $signed({{28{wram_wt_i[i * 4 + 3]}}, wram_wt_i[(i * 4) +: 4]}));
                  end
                end
 001287         mlu_pkg::PREC_INT8: begin
 001287           mac_ops_beat = 32'd32;
 041184           for (int i = 0; i < 32; i++) begin
 041184             dot_prod_comb = dot_prod_comb +
 041184               ($signed({{24{eff_act_bytes[i * 8 + 7]}}, eff_act_bytes[(i * 8) +: 8]}) *
 041184                $signed({{24{wram_wt_i[i * 8 + 7]}}, wram_wt_i[(i * 8) +: 8]}));
                  end
                end
~000338         mlu_pkg::PREC_FP8_E4M3: begin
~000338           mac_ops_beat = 32'd32;
~010816           for (int i = 0; i < 32; i++) begin
~010816             dot_prod_comb = dot_prod_comb +
~010816               ((decode_fp8_e4m3(eff_act_bytes[(i * 8) +: 8]) *
~010816                 decode_fp8_e4m3(wram_wt_i[(i * 8) +: 8])) >>> 12);
                  end
                end
~000568         mlu_pkg::PREC_FP8_E5M2: begin
~000568           mac_ops_beat = 32'd32;
~018176           for (int i = 0; i < 32; i++) begin
~018176             dot_prod_comb = dot_prod_comb +
~018176               ((decode_fp8_e5m2(eff_act_bytes[(i * 8) +: 8]) *
~018176                 decode_fp8_e5m2(wram_wt_i[(i * 8) +: 8])) >>> 14);
                  end
                end
 001136         mlu_pkg::PREC_FP16, mlu_pkg::PREC_BF16: begin
 001136           mac_ops_beat = 32'd16;
 018176           for (int i = 0; i < 16; i++) begin
 018176             dot_prod_comb = dot_prod_comb +
 018176               ((decode_fp16_bf16(eff_act_bytes[(i * 16) +: 16], (prec_q == mlu_pkg::PREC_BF16)) *
 018176                 decode_fp16_bf16(wram_wt_i[(i * 16) +: 16], (prec_q == mlu_pkg::PREC_BF16))) >>> 22);
                  end
                end
~000882         default: begin
~000882           mac_ops_beat = 32'd8;
~007056           for (int i = 0; i < 8; i++) begin
~007056             dot_prod_comb = dot_prod_comb +
~007056               ((decode_fp16_bf16(eff_act_bytes[(i * 32 + 16) +: 16], 1'b1) *
~007056                 decode_fp16_bf16(wram_wt_i[(i * 32 + 16) +: 16], 1'b1) +
~007056                 $signed({16'd0, eff_act_bytes[(i * 32) +: 16] & wram_wt_i[(i * 32) +: 16]}) * 32'sd0) >>> 22);
                  end
                end
              endcase
            end
          end
        
          // ---------------------------------------------------------------------------
          // 5. Cambricon-Q Statistical Quantizer (Scale Q8.8 + Zero-Point + Saturate)
          // ---------------------------------------------------------------------------
 004752   function automatic logic signed [7:0] cambricon_q_quantize(
            input logic signed [31:0] acc_in,
            input logic [15:0]        scale_q8_8,
            input logic [7:0]         zp_in
          );
 004752     logic signed [47:0] mult_full;
 004752     logic signed [39:0] rounded;
 004752     logic signed [39:0] shifted;
 004752     mult_full = acc_in * $signed({1'b0, scale_q8_8});
 004752     rounded   = $signed(mult_full[47:8]) + $signed({39'd0, (mult_full[7] && (|mult_full[6:0] || mult_full[8]))});
 004752     shifted   = rounded + $signed({{32{zp_in[7]}}, zp_in});
~000646     if (shifted > 40'sd127) begin
~000646       cambricon_q_quantize = 8'sd127;
~003387     end else if (shifted < -40'sd128) begin
~000719       cambricon_q_quantize = -8'sd128;
 003387     end else begin
 003387       cambricon_q_quantize = shifted[7:0];
            end
          endfunction
        
          // Output data formatting:
          // If OP_BANG_QUANT_MM, lower 64 bits pack 8 quantized INT8 tile results and
          // upper 192 bits hold raw 32-bit accumulators [5:0]; otherwise all 8 x 32-bit
          // accumulators are driven on result_data_o[255:0].
 002416   always_comb begin
 002021     if (op_q == mlu_pkg::OP_BANG_QUANT_MM) begin
 004752       for (int c = 0; c < 8; c++) begin
 004752         result_data_o[(c * 8) +: 8] = cambricon_q_quantize($signed(acc_tile_q[c]), quant_scale_i, quant_zp_i);
              end
 003564       for (int c = 0; c < 6; c++) begin
 003564         result_data_o[(64 + c * 32) +: 32] = acc_tile_q[c];
              end
 002021     end else begin
 016168       for (int c = 0; c < 8; c++) begin
 016168         result_data_o[(c * 32) +: 32] = acc_tile_q[c];
              end
            end
          end
        
          assign result_valid_o = (state_q == TFU_WB);
          assign done_valid_o   = (state_q == TFU_WB);
          assign done_tag_o     = tag_q;
        
          // ---------------------------------------------------------------------------
          // 6. Sequential Execution Pipeline & Telemetry Counters
          // ---------------------------------------------------------------------------
 002412   always_ff @(posedge clk_i or negedge rst_ni) begin
~002400     if (!rst_ni) begin
~000012       state_q         <= TFU_IDLE;
~000012       op_q            <= mlu_pkg::OP_NOP;
~000012       prec_q          <= mlu_pkg::PREC_INT8;
~000012       sparse_q        <= mlu_pkg::SPARSE_DENSE;
~000012       tag_q           <= 8'd0;
~000012       beats_rem_q     <= 16'd0;
~000012       beat_idx_q      <= 4'd0;
~000096       for (int c = 0; c < 8; c++) begin
 000096         acc_tile_q[c] <= 32'sd0;
              end
~000012       zero_skip_cnt_o <= 32'd0;
~000012       total_mac_ops_o <= 32'd0;
 002400     end else begin
 002400       unique case (state_q)
 002355         TFU_IDLE: begin
~002346           if (cmd_valid_i) begin
~000200             op_q        <= cmd_inst_dec.opcode;
~000200             prec_q      <= cmd_inst_dec.prec;
~000200             sparse_q    <= cmd_inst_dec.sparse_mode;
~000200             tag_q       <= cmd_inst_dec.tag_id;
~000200             beats_rem_q <= (cmd_inst_dec.len_or_dims == 16'd0) ? 16'd1 : cmd_inst_dec.len_or_dims;
~000200             beat_idx_q  <= 4'd0;
~001600             for (int c = 0; c < 8; c++) begin
 001600               acc_tile_q[c] <= 32'sd0;
                    end
~000200             state_q     <= TFU_STREAM;
                  end
                end
        
 000800         TFU_STREAM: begin
~000800           if (stream_valid_i) begin
~000700             if (block_is_zero) begin
~000100               zero_skip_cnt_o <= zero_skip_cnt_o + 32'd1;
 000700             end else begin
 000700               acc_tile_q[0] <= acc_tile_q[0] + dot_prod_comb;
~000550               if (beat_idx_q[2:0] != 3'd0) begin
 000550                 acc_tile_q[beat_idx_q[2:0]] <= acc_tile_q[beat_idx_q[2:0]] + dot_prod_comb;
                      end
 000700               total_mac_ops_o <= total_mac_ops_o + mac_ops_beat;
                    end
        
 000800             beat_idx_q <= beat_idx_q + 4'd1;
~000600             if (beats_rem_q <= 16'd1) begin
~000200               state_q <= TFU_WB;
 000600             end else begin
 000600               beats_rem_q <= beats_rem_q - 16'd1;
                    end
                  end
                end
        
~000200         TFU_WB: begin
~000200           state_q <= TFU_IDLE;
                end
        
%000000         default: state_q <= TFU_IDLE;
              endcase
            end
          end
        
          wire _unused_ok = &{1'b0, cmd_inst_dec.engine, cmd_inst_dec.src_space,
                              cmd_inst_dec.dst_space, cmd_inst_dec.dep_mask,
                              cmd_inst_dec.dst_addr, cmd_inst_dec.src0_addr,
                              cmd_inst_dec.src1_or_strd};
        
        endmodule : mlu_tfu_fractal_mac
        
