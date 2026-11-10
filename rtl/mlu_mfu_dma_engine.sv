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
  input  logic         clk_i,
  input  logic         rst_ni,

  // Dispatched MFU DMA Command Interface (from BANG ICU)
  input  logic         cmd_valid_i,
  output logic         cmd_ready_o,
  input  logic [127:0] cmd_inst_i,

  // Indirect Gather/Scatter Index Offset Vector (4 x 16-bit byte offsets)
  input  logic [63:0]  idx_offset_i,

  // Cambricon-S / Cambricon-LLM 8-Bit Zero-Mask Bitmap for Decompression DMA
  input  logic [7:0]   decomp_bitmap_i,

  // Memory Read Request & Response Channel
  output logic         rd_req_valid_o,
  output logic [2:0]   rd_req_space_o,
  output logic [31:0]  rd_req_addr_o,
  input  logic         rd_resp_valid_i,
  input  logic [63:0]  rd_resp_data_i,

  // Memory Write Request Channel
  output logic         wr_req_valid_o,
  output logic [2:0]   wr_req_space_o,
  output logic [31:0]  wr_req_addr_o,
  output logic [63:0]  wr_req_data_o,

  // NRAM 2D Transpose Crossbar Control & Status Telemetry
  output logic         nram_transpose_mode_o,
  output logic         mfu_busy_o,
  output logic [31:0]  compressed_bytes_rd_o,
  output logic [31:0]  uncompressed_bytes_wr_o,

  // ICU Completion Handshake
  output logic         done_valid_o,
  output logic [7:0]   done_tag_o
);

  // ---------------------------------------------------------------------------
  // 1. Hardware Zero-Bitmap Decompressor & Popcount Helper Functions
  // ---------------------------------------------------------------------------
  function automatic logic [3:0] popcnt8(input logic [7:0] bmp);
    logic [3:0] cnt;
    cnt = 4'd0;
    for (int i = 0; i < 8; i++) begin
      cnt = cnt + {3'd0, bmp[i]};
    end
    popcnt8 = cnt;
  endfunction

  // Expands packed non-zero byte stream (comp_word) using 8-bit bitmap (bmp):
  // If bmp[k] == 1, byte k receives comp_word[nz_idx*8 +: 8], else 8'h00.
  function automatic logic [63:0] expand_zero_bitmap(
    input logic [63:0] comp_word,
    input logic [7:0]  bmp
  );
    logic [63:0] dense_word;
    logic [2:0]  nz_idx;
    dense_word = 64'd0;
    nz_idx     = 3'd0;
    for (int k = 0; k < 8; k++) begin
      if (bmp[k]) begin
        dense_word[(k*8) +: 8] = comp_word[({3'd0, nz_idx} * 8) +: 8];
        nz_idx = nz_idx + 3'd1;
      end else begin
        dense_word[(k*8) +: 8] = 8'h00;
      end
    end
    expand_zero_bitmap = dense_word;
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

  dma_state_e               state_q;
  mlu_pkg::mlu_opcode_e     op_q;
  mlu_pkg::mlu_mem_space_e  src_space_q;
  mlu_pkg::mlu_mem_space_e  dst_space_q;
  logic [7:0]               tag_q;
  logic [31:0]              src_base_q;
  logic [31:0]              dst_base_q;
  logic [15:0]              total_beats_q;
  logic [15:0]              beat_cnt_q;
  logic [7:0]               num_rows_q;
  logic [7:0]               row_beats_q;
  logic [7:0]               src_stride_q;
  logic [7:0]               dst_stride_q;
  logic [7:0]               row_idx_q;
  logic [7:0]               col_idx_q;
  logic [63:0]              wr_data_q;

  assign cmd_ready_o           = (state_q == DMA_IDLE);
  assign mfu_busy_o            = (state_q != DMA_IDLE);
  assign nram_transpose_mode_o = (state_q != DMA_IDLE) && (op_q == mlu_pkg::OP_BANG_TRANSPOSE);

  // ---------------------------------------------------------------------------
  // 3. Combinational Read & Write Address Calculation across All 6 DMA Modes
  // ---------------------------------------------------------------------------
  logic [15:0] curr_idx_off;
  logic [31:0] curr_rd_addr;
  logic [31:0] curr_wr_addr;

  always_comb begin
    curr_idx_off = idx_offset_i[({14'd0, beat_cnt_q[1:0]} * 16) +: 16];
    curr_rd_addr = src_base_q + ({16'd0, beat_cnt_q} << 3);
    curr_wr_addr = dst_base_q + ({16'd0, beat_cnt_q} << 3);

    unique case (op_q)
      mlu_pkg::OP_BANG_MEMCPY_1D,
      mlu_pkg::OP_BANG_DECOMP_DMA: begin
        curr_rd_addr = src_base_q + ({16'd0, beat_cnt_q} << 3);
        curr_wr_addr = dst_base_q + ({16'd0, beat_cnt_q} << 3);
      end

      mlu_pkg::OP_BANG_MEMCPY_2D: begin
        curr_rd_addr = src_base_q +
                       ((({24'd0, row_idx_q} * {24'd0, src_stride_q}) + {24'd0, col_idx_q}) << 3);
        curr_wr_addr = dst_base_q +
                       ((({24'd0, row_idx_q} * {24'd0, dst_stride_q}) + {24'd0, col_idx_q}) << 3);
      end

      mlu_pkg::OP_BANG_GATHER: begin
        curr_rd_addr = src_base_q + {16'd0, curr_idx_off};
        curr_wr_addr = dst_base_q + ({16'd0, beat_cnt_q} << 3);
      end

      mlu_pkg::OP_BANG_SCATTER: begin
        curr_rd_addr = src_base_q + ({16'd0, beat_cnt_q} << 3);
        curr_wr_addr = dst_base_q + {16'd0, curr_idx_off};
      end

      mlu_pkg::OP_BANG_TRANSPOSE: begin
        curr_rd_addr = src_base_q + ({16'd0, beat_cnt_q} << 3);
        curr_wr_addr = dst_base_q + ({16'd0, beat_cnt_q[2:0], beat_cnt_q[15:3]} << 3);
      end

      default: begin
        curr_rd_addr = src_base_q + ({16'd0, beat_cnt_q} << 3);
        curr_wr_addr = dst_base_q + ({16'd0, beat_cnt_q} << 3);
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
  mlu_pkg::mlu_inst_t dec_cmd;
  assign dec_cmd = cmd_inst_i;

  logic _unused_dma_cmd;
  assign _unused_dma_cmd = ^{dec_cmd.engine, dec_cmd.prec, dec_cmd.sparse_mode, dec_cmd.dep_mask};

  logic [7:0] init_rows;
  logic [7:0] init_cols;
  assign init_rows = (dec_cmd.len_or_dims[15:8] == 8'd0) ? 8'd1 : dec_cmd.len_or_dims[15:8];
  assign init_cols = (dec_cmd.len_or_dims[7:0]  == 8'd0) ? 8'd1 : dec_cmd.len_or_dims[7:0];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q                 <= DMA_IDLE;
      op_q                    <= mlu_pkg::OP_NOP;
      src_space_q             <= mlu_pkg::MEM_SPACE_GDRAM;
      dst_space_q             <= mlu_pkg::MEM_SPACE_NRAM;
      tag_q                   <= 8'd0;
      src_base_q              <= 32'd0;
      dst_base_q              <= 32'd0;
      total_beats_q           <= 16'd1;
      beat_cnt_q              <= 16'd0;
      num_rows_q              <= 8'd1;
      row_beats_q             <= 8'd1;
      src_stride_q            <= 8'd1;
      dst_stride_q            <= 8'd1;
      row_idx_q               <= 8'd0;
      col_idx_q               <= 8'd0;
      wr_data_q               <= 64'd0;
      compressed_bytes_rd_o   <= 32'd0;
      uncompressed_bytes_wr_o <= 32'd0;
      done_valid_o            <= 1'b0;
      done_tag_o              <= 8'd0;
    end else begin
      done_valid_o <= 1'b0;

      unique case (state_q)
        DMA_IDLE: begin
          if (cmd_valid_i && cmd_ready_o) begin
            op_q        <= dec_cmd.opcode;
            src_space_q <= dec_cmd.src_space;
            dst_space_q <= dec_cmd.dst_space;
            tag_q       <= dec_cmd.tag_id;
            src_base_q  <= dec_cmd.src0_addr;
            dst_base_q  <= dec_cmd.dst_addr;
            beat_cnt_q  <= 16'd0;
            row_idx_q   <= 8'd0;
            col_idx_q   <= 8'd0;
            num_rows_q  <= init_rows;
            row_beats_q <= init_cols;
            src_stride_q <= (dec_cmd.src1_or_strd[15:8] == 8'd0) ? init_cols : dec_cmd.src1_or_strd[15:8];
            dst_stride_q <= (dec_cmd.src1_or_strd[7:0]  == 8'd0) ? init_cols : dec_cmd.src1_or_strd[7:0];

            if (dec_cmd.opcode == mlu_pkg::OP_BANG_MEMCPY_2D) begin
              total_beats_q <= {8'd0, init_rows} * {8'd0, init_cols};
            end else if (dec_cmd.opcode == mlu_pkg::OP_BANG_TRANSPOSE) begin
              total_beats_q <= (dec_cmd.len_or_dims == 16'd0) ? 16'd8 : dec_cmd.len_or_dims;
            end else begin
              total_beats_q <= (dec_cmd.len_or_dims == 16'd0) ? 16'd1 : dec_cmd.len_or_dims;
            end
            state_q <= DMA_RD_REQ;
          end
        end

        DMA_RD_REQ: begin
          if (rd_resp_valid_i) begin
            if (op_q == mlu_pkg::OP_BANG_DECOMP_DMA) begin
              wr_data_q               <= expand_zero_bitmap(rd_resp_data_i, decomp_bitmap_i);
              compressed_bytes_rd_o   <= compressed_bytes_rd_o + {28'd0, popcnt8(decomp_bitmap_i)};
              uncompressed_bytes_wr_o <= uncompressed_bytes_wr_o + 32'd8;
            end else begin
              wr_data_q <= rd_resp_data_i;
            end
            state_q <= DMA_WR_REQ;
          end else begin
            state_q <= DMA_WAIT_RESP;
          end
        end

        DMA_WAIT_RESP: begin
          if (rd_resp_valid_i) begin
            if (op_q == mlu_pkg::OP_BANG_DECOMP_DMA) begin
              wr_data_q               <= expand_zero_bitmap(rd_resp_data_i, decomp_bitmap_i);
              compressed_bytes_rd_o   <= compressed_bytes_rd_o + {28'd0, popcnt8(decomp_bitmap_i)};
              uncompressed_bytes_wr_o <= uncompressed_bytes_wr_o + 32'd8;
            end else begin
              wr_data_q <= rd_resp_data_i;
            end
            state_q <= DMA_WR_REQ;
          end
        end

        DMA_WR_REQ: begin
          if (beat_cnt_q + 16'd1 >= total_beats_q) begin
            done_valid_o <= 1'b1;
            done_tag_o   <= tag_q;
            state_q      <= DMA_IDLE;
          end else begin
            beat_cnt_q <= beat_cnt_q + 16'd1;
            if (col_idx_q + 8'd1 >= row_beats_q) begin
              col_idx_q <= 8'd0;
              if (row_idx_q + 8'd1 < num_rows_q) begin
                row_idx_q <= row_idx_q + 8'd1;
              end
            end else begin
              col_idx_q <= col_idx_q + 8'd1;
            end
            state_q <= DMA_RD_REQ;
          end
        end

        default: state_q <= DMA_IDLE;
      endcase
    end
  end

endmodule : mlu_mfu_dma_engine
