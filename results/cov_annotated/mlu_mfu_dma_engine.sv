//      // verilator_coverage annotation
        // =============================================================================
        // File: rtl/mlu_mfu_dma_engine.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: Stage 6 — Memory Function Unit (MFU): Asynchronous 1D/2D Strided,
        //              Indirect Gather/Scatter, On-the-Fly Transpose, & Cambricon-S/LLM
        //              Zero-Bitmap Hardware Decompression DMA Engine across GDRAM, SRAM,
        //              NRAM, and WRAM memory spaces.
        // =============================================================================
        `include "mlu_pkg.sv"
        
        module mlu_mfu_dma_engine (
 002764   input  logic         clk_i,
%000004   input  logic         rst_ni,
        
          // Dispatched MFU DMA Command Interface (from BANG ICU)
~000320   input  logic         cmd_valid_i,
~000321   output logic         cmd_ready_o,
~000243   input  logic [127:0] cmd_inst_i,
        
          // Indirect Gather/Scatter Index Offset Vector (4 x 16-bit byte offsets)
~000087   input  logic [63:0]  idx_offset_i,
        
          // Cambricon-S / Cambricon-LLM 8-Bit Zero-Mask Bitmap for Decompression DMA
~000143   input  logic [7:0]   decomp_bitmap_i,
        
          // Memory Read Request & Response Channel
 000978   output logic         rd_req_valid_o,
~000059   output logic [2:0]   rd_req_space_o,
~000394   output logic [31:0]  rd_req_addr_o,
 000978   input  logic         rd_resp_valid_i,
~000413   input  logic [63:0]  rd_resp_data_i,
        
          // Memory Write Request Channel
 000978   output logic         wr_req_valid_o,
~000064   output logic [2:0]   wr_req_space_o,
~000332   output logic [31:0]  wr_req_addr_o,
~000358   output logic [63:0]  wr_req_data_o,
        
          // NRAM 2D Transpose Crossbar Control & Status Telemetry
~000021   output logic         nram_transpose_mode_o,
~000320   output logic         mfu_busy_o,
~000198   output logic [31:0]  compressed_bytes_rd_o,
~000272   output logic [31:0]  uncompressed_bytes_wr_o,
        
          // ICU Completion Handshake
~000320   output logic         done_valid_o,
~000160   output logic [7:0]   done_tag_o
        );
        
          // ---------------------------------------------------------------------------
          // 1. Hardware Zero-Bitmap Decompressor & Popcount Helper Functions
          // ---------------------------------------------------------------------------
~000543   function automatic logic [3:0] popcnt8(input logic [7:0] bmp);
~000543     logic [3:0] cnt;
~000543     cnt = 4'd0;
~004344     for (int i = 0; i < 8; i++) begin
 004344       cnt = cnt + {3'd0, bmp[i]};
            end
~000543     popcnt8 = cnt;
          endfunction
        
          // Expands packed non-zero byte stream (comp_word) using 8-bit bitmap (bmp):
          // If bmp[k] == 1, byte k receives comp_word[nz_idx*8 +: 8], else 8'h00.
~000543   function automatic logic [63:0] expand_zero_bitmap(
            input logic [63:0] comp_word,
            input logic [7:0]  bmp
          );
~000543     logic [63:0] dense_word;
~000543     logic [2:0]  nz_idx;
~000543     dense_word = 64'd0;
~000543     nz_idx     = 3'd0;
~004344     for (int k = 0; k < 8; k++) begin
 002290       if (bmp[k]) begin
 002290         dense_word[(k*8) +: 8] = comp_word[({3'd0, nz_idx} * 8) +: 8];
 002290         nz_idx = nz_idx + 3'd1;
 002054       end else begin
 002054         dense_word[(k*8) +: 8] = 8'h00;
              end
            end
~000543     expand_zero_bitmap = dense_word;
          endfunction
        
          // ---------------------------------------------------------------------------
          // 2. DMA Engine FSM & Latched Command Descriptor Registers
          // ---------------------------------------------------------------------------
          typedef enum logic [1:0] {
            DMA_IDLE      = 2'b00,
            DMA_RD_REQ    = 2'b01,
            DMA_WAIT_RESP = 2'b10,
            DMA_WR_REQ    = 2'b11
          } dma_state_e;
        
 000978   dma_state_e               state_q;
~000064   mlu_pkg::mlu_opcode_e     op_q;
~000059   mlu_pkg::mlu_mem_space_e  src_space_q;
~000064   mlu_pkg::mlu_mem_space_e  dst_space_q;
~000160   logic [7:0]               tag_q;
~000085   logic [31:0]              src_base_q;
~000083   logic [31:0]              dst_base_q;
~000083   logic [15:0]              total_beats_q;
~000416   logic [15:0]              beat_cnt_q;
~000010   logic [7:0]               num_rows_q;
~000084   logic [7:0]               row_beats_q;
~000087   logic [7:0]               src_stride_q;
~000087   logic [7:0]               dst_stride_q;
~000014   logic [7:0]               row_idx_q;
~000405   logic [7:0]               col_idx_q;
~000358   logic [63:0]              wr_data_q;
        
          assign cmd_ready_o           = (state_q == DMA_IDLE);
          assign mfu_busy_o            = (state_q != DMA_IDLE);
          assign nram_transpose_mode_o = (state_q != DMA_IDLE) && (op_q == mlu_pkg::OP_BANG_TRANSPOSE);
        
          // ---------------------------------------------------------------------------
          // 3. Combinational Read & Write Address Calculation across All 6 DMA Modes
          // ---------------------------------------------------------------------------
~000330   logic [15:0] curr_idx_off;
~000394   logic [31:0] curr_rd_addr;
~000332   logic [31:0] curr_wr_addr;
        
 003725   always_comb begin
 003725     curr_idx_off = idx_offset_i[({14'd0, beat_cnt_q[1:0]} * 16) +: 16];
 003725     curr_rd_addr = src_base_q + ({16'd0, beat_cnt_q} << 3);
 003725     curr_wr_addr = dst_base_q + ({16'd0, beat_cnt_q} << 3);
        
 003725     unique case (op_q)
              mlu_pkg::OP_BANG_MEMCPY_1D,
 002464       mlu_pkg::OP_BANG_DECOMP_DMA: begin
 002464         curr_rd_addr = src_base_q + ({16'd0, beat_cnt_q} << 3);
 002464         curr_wr_addr = dst_base_q + ({16'd0, beat_cnt_q} << 3);
              end
        
 000515       mlu_pkg::OP_BANG_MEMCPY_2D: begin
 000515         curr_rd_addr = src_base_q +
 000515                        ((({24'd0, row_idx_q} * {24'd0, src_stride_q}) + {24'd0, col_idx_q}) << 3);
 000515         curr_wr_addr = dst_base_q +
 000515                        ((({24'd0, row_idx_q} * {24'd0, dst_stride_q}) + {24'd0, col_idx_q}) << 3);
              end
        
 000200       mlu_pkg::OP_BANG_GATHER: begin
 000200         curr_rd_addr = src_base_q + {16'd0, curr_idx_off};
 000200         curr_wr_addr = dst_base_q + ({16'd0, beat_cnt_q} << 3);
              end
        
 000465       mlu_pkg::OP_BANG_SCATTER: begin
 000465         curr_rd_addr = src_base_q + ({16'd0, beat_cnt_q} << 3);
 000465         curr_wr_addr = dst_base_q + {16'd0, curr_idx_off};
              end
        
 000508       mlu_pkg::OP_BANG_TRANSPOSE: begin
 000508         curr_rd_addr = src_base_q + ({16'd0, beat_cnt_q} << 3);
 000508         curr_wr_addr = dst_base_q + ({16'd0, beat_cnt_q[2:0], beat_cnt_q[15:3]} << 3);
              end
        
~000356       default: begin
~000356         curr_rd_addr = src_base_q + ({16'd0, beat_cnt_q} << 3);
~000356         curr_wr_addr = dst_base_q + ({16'd0, beat_cnt_q} << 3);
              end
            endcase
          end
        
          assign rd_req_valid_o = (state_q == DMA_RD_REQ);
          assign rd_req_space_o = src_space_q;
          assign rd_req_addr_o  = curr_rd_addr;
        
          assign wr_req_valid_o = (state_q == DMA_WR_REQ);
          assign wr_req_space_o = dst_space_q;
          assign wr_req_addr_o  = curr_wr_addr;
          assign wr_req_data_o  = wr_data_q;
        
          // ---------------------------------------------------------------------------
          // 4. Sequential DMA Control & Decompression Telemetry Counters
          // ---------------------------------------------------------------------------
~000160   mlu_pkg::mlu_inst_t dec_cmd;
          assign dec_cmd = cmd_inst_i;
        
          logic _unused_dma_cmd;
          assign _unused_dma_cmd = ^{dec_cmd.engine, dec_cmd.prec, dec_cmd.sparse_mode, dec_cmd.dep_mask};
        
~000010   logic [7:0] init_rows;
~000084   logic [7:0] init_cols;
          assign init_rows = (dec_cmd.len_or_dims[15:8] == 8'd0) ? 8'd1 : dec_cmd.len_or_dims[15:8];
          assign init_cols = (dec_cmd.len_or_dims[7:0]  == 8'd0) ? 8'd1 : dec_cmd.len_or_dims[7:0];
        
 002764   always_ff @(posedge clk_i or negedge rst_ni) begin
~002760     if (!rst_ni) begin
~000012       state_q                 <= DMA_IDLE;
~000012       op_q                    <= mlu_pkg::OP_NOP;
~000012       src_space_q             <= mlu_pkg::MEM_SPACE_GDRAM;
~000012       dst_space_q             <= mlu_pkg::MEM_SPACE_NRAM;
~000012       tag_q                   <= 8'd0;
~000012       src_base_q              <= 32'd0;
~000012       dst_base_q              <= 32'd0;
~000012       total_beats_q           <= 16'd1;
~000012       beat_cnt_q              <= 16'd0;
~000012       num_rows_q              <= 8'd1;
~000012       row_beats_q             <= 8'd1;
~000012       src_stride_q            <= 8'd1;
~000012       dst_stride_q            <= 8'd1;
~000012       row_idx_q               <= 8'd0;
~000012       col_idx_q               <= 8'd0;
~000012       wr_data_q               <= 64'd0;
~000012       compressed_bytes_rd_o   <= 32'd0;
~000012       uncompressed_bytes_wr_o <= 32'd0;
~000012       done_valid_o            <= 1'b0;
~000012       done_tag_o              <= 8'd0;
 002760     end else begin
 002760       done_valid_o <= 1'b0;
        
 002760       unique case (state_q)
 002304         DMA_IDLE: begin
~002296           if (cmd_valid_i && cmd_ready_o) begin
~000320             op_q        <= dec_cmd.opcode;
~000320             src_space_q <= dec_cmd.src_space;
~000320             dst_space_q <= dec_cmd.dst_space;
~000320             tag_q       <= dec_cmd.tag_id;
~000320             src_base_q  <= dec_cmd.src0_addr;
~000320             dst_base_q  <= dec_cmd.dst_addr;
~000320             beat_cnt_q  <= 16'd0;
~000320             row_idx_q   <= 8'd0;
~000320             col_idx_q   <= 8'd0;
~000320             num_rows_q  <= init_rows;
~000320             row_beats_q <= init_cols;
~000320             src_stride_q <= (dec_cmd.src1_or_strd[15:8] == 8'd0) ? init_cols : dec_cmd.src1_or_strd[15:8];
~000320             dst_stride_q <= (dec_cmd.src1_or_strd[7:0]  == 8'd0) ? init_cols : dec_cmd.src1_or_strd[7:0];
        
~000022             if (dec_cmd.opcode == mlu_pkg::OP_BANG_MEMCPY_2D) begin
~000022               total_beats_q <= {8'd0, init_rows} * {8'd0, init_cols};
~000277             end else if (dec_cmd.opcode == mlu_pkg::OP_BANG_TRANSPOSE) begin
~000021               total_beats_q <= (dec_cmd.len_or_dims == 16'd0) ? 16'd8 : dec_cmd.len_or_dims;
~000277             end else begin
~000277               total_beats_q <= (dec_cmd.len_or_dims == 16'd0) ? 16'd1 : dec_cmd.len_or_dims;
                    end
~000320             state_q <= DMA_RD_REQ;
                  end
                end
        
 000978         DMA_RD_REQ: begin
~000495           if (rd_resp_valid_i) begin
~000284             if (op_q == mlu_pkg::OP_BANG_DECOMP_DMA) begin
~000211               wr_data_q               <= expand_zero_bitmap(rd_resp_data_i, decomp_bitmap_i);
~000211               compressed_bytes_rd_o   <= compressed_bytes_rd_o + {28'd0, popcnt8(decomp_bitmap_i)};
~000211               uncompressed_bytes_wr_o <= uncompressed_bytes_wr_o + 32'd8;
~000284             end else begin
~000284               wr_data_q <= rd_resp_data_i;
                    end
~000495             state_q <= DMA_WR_REQ;
 000483           end else begin
 000483             state_q <= DMA_WAIT_RESP;
                  end
                end
        
 000483         DMA_WAIT_RESP: begin
~000483           if (rd_resp_valid_i) begin
~000332             if (op_q == mlu_pkg::OP_BANG_DECOMP_DMA) begin
~000332               wr_data_q               <= expand_zero_bitmap(rd_resp_data_i, decomp_bitmap_i);
~000332               compressed_bytes_rd_o   <= compressed_bytes_rd_o + {28'd0, popcnt8(decomp_bitmap_i)};
~000332               uncompressed_bytes_wr_o <= uncompressed_bytes_wr_o + 32'd8;
 000151             end else begin
 000151               wr_data_q <= rd_resp_data_i;
                    end
 000483             state_q <= DMA_WR_REQ;
                  end
                end
        
 000978         DMA_WR_REQ: begin
~000658           if (beat_cnt_q + 16'd1 >= total_beats_q) begin
~000320             done_valid_o <= 1'b1;
~000320             done_tag_o   <= tag_q;
~000320             state_q      <= DMA_IDLE;
 000658           end else begin
 000658             beat_cnt_q <= beat_cnt_q + 16'd1;
~000635             if (col_idx_q + 8'd1 >= row_beats_q) begin
~000023               col_idx_q <= 8'd0;
~000023               if (row_idx_q + 8'd1 < num_rows_q) begin
~000023                 row_idx_q <= row_idx_q + 8'd1;
                      end
 000635             end else begin
 000635               col_idx_q <= col_idx_q + 8'd1;
                    end
 000658             state_q <= DMA_RD_REQ;
                  end
                end
        
%000000         default: state_q <= DMA_IDLE;
              endcase
            end
          end
        
        endmodule : mlu_mfu_dma_engine
        
