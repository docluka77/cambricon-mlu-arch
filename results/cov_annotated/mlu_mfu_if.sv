//      // verilator_coverage annotation
        // =============================================================================
        // File: uvm_tb/uvm_mfu_dma_decomp/mlu_mfu_if.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: SystemVerilog Interface & DUT Wrapper for Accellera IEEE 1800.2-2020
        //              UVM Verification of mlu_mfu_dma_engine (All 6 BANG DMA Opcodes &
        //              Cambricon-S/LLM 8-Bit Zero-Bitmap Decompression).
        // =============================================================================
        `ifndef MLU_MFU_IF_SV
        `define MLU_MFU_IF_SV
        
        `include "mlu_pkg.sv"
        
 002764 interface mlu_mfu_if (input logic clk);
%000001   logic         rst_ni;
 000320   logic         cmd_valid_i;
 000321   logic         cmd_ready_o;
~000243   logic [127:0] cmd_inst_i;
~000087   logic [63:0]  idx_offset_i;
 000143   logic [7:0]   decomp_bitmap_i;
        
 000978   logic         rd_req_valid_o;
 000059   logic [2:0]   rd_req_space_o;
~000394   logic [31:0]  rd_req_addr_o;
 000978   logic         rd_resp_valid_i;
 000413   logic [63:0]  rd_resp_data_i;
        
 000978   logic         wr_req_valid_o;
 000064   logic [2:0]   wr_req_space_o;
~000332   logic [31:0]  wr_req_addr_o;
 000358   logic [63:0]  wr_req_data_o;
        
 000021   logic         nram_transpose_mode_o;
 000320   logic         mfu_busy_o;
~000198   logic [31:0]  compressed_bytes_rd_o;
~000272   logic [31:0]  uncompressed_bytes_wr_o;
 000320   logic         done_valid_o;
~000160   logic [7:0]   done_tag_o;
        
          // Monitor tracking signals for active command & beat read phase
~000243   logic [127:0] mon_cmd_inst;
~000087   logic [63:0]  mon_idx_offset;
 000143   logic [7:0]   mon_decomp_bitmap;
 000413   logic [63:0]  mon_raw_rd_data;
~000387   logic [31:0]  mon_latched_rd_addr;
 000059   logic [2:0]   mon_latched_rd_space;
~000562   logic [15:0]  mon_beat_idx;
        endinterface : mlu_mfu_if
        
        module mlu_mfu_dut_wrap (mlu_mfu_if bus);
          mlu_mfu_dma_engine u_dut (
            .clk_i                   (bus.clk),
            .rst_ni                  (bus.rst_ni),
            .cmd_valid_i             (bus.cmd_valid_i),
            .cmd_ready_o             (bus.cmd_ready_o),
            .cmd_inst_i              (bus.cmd_inst_i),
            .idx_offset_i            (bus.idx_offset_i),
            .decomp_bitmap_i         (bus.decomp_bitmap_i),
            .rd_req_valid_o          (bus.rd_req_valid_o),
            .rd_req_space_o          (bus.rd_req_space_o),
            .rd_req_addr_o           (bus.rd_req_addr_o),
            .rd_resp_valid_i         (bus.rd_resp_valid_i),
            .rd_resp_data_i          (bus.rd_resp_data_i),
            .wr_req_valid_o          (bus.wr_req_valid_o),
            .wr_req_space_o          (bus.wr_req_space_o),
            .wr_req_addr_o           (bus.wr_req_addr_o),
            .wr_req_data_o           (bus.wr_req_data_o),
            .nram_transpose_mode_o   (bus.nram_transpose_mode_o),
            .mfu_busy_o              (bus.mfu_busy_o),
            .compressed_bytes_rd_o   (bus.compressed_bytes_rd_o),
            .uncompressed_bytes_wr_o (bus.uncompressed_bytes_wr_o),
            .done_valid_o            (bus.done_valid_o),
            .done_tag_o              (bus.done_tag_o)
          );
        endmodule : mlu_mfu_dut_wrap
        
        `endif // MLU_MFU_IF_SV
        
