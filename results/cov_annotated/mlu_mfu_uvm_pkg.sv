//      // verilator_coverage annotation
        // =============================================================================
        // File: uvm_tb/uvm_mfu_dma_decomp/mlu_mfu_uvm_pkg.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: Accellera IEEE 1800.2-2020 UVM Verification Package for Suite 5:
        //              mlu_mfu_dma_engine (All 6 BANG DMA Opcodes & Zero-Bitmap Decomp).
        // =============================================================================
        `ifndef MLU_MFU_UVM_PKG_SV
        `define MLU_MFU_UVM_PKG_SV
        
        `timescale 1ns/1ps
        `include "uvm_macros.svh"
        `include "mlu_pkg.sv"
        
        package mlu_mfu_uvm_pkg;
          import uvm_pkg::*;
          import mlu_pkg::*;
        
          // ---------------------------------------------------------------------------
          // DPI-C Bit-Exact Reference Model Imports
          // ---------------------------------------------------------------------------
          import "DPI-C" function void             dpi_mfu_set_status(int status);
          import "DPI-C" function int              dpi_mfu_get_status();
          import "DPI-C" function int unsigned     dpi_mfu_get_calls();
          import "DPI-C" function void             dpi_mfu_ref_reset();
          import "DPI-C" function void             dpi_mfu_ref_eval_beat(
            int unsigned     opcode,
            int unsigned     src_base,
            int unsigned     dst_base,
            int unsigned     src1_or_strd,
            int unsigned     len_or_dims,
            int unsigned     beat_idx,
            longint unsigned idx_offset,
            int unsigned     decomp_bitmap,
            longint unsigned raw_rd_data
          );
          import "DPI-C" function int unsigned     dpi_mfu_exp_rd_addr();
          import "DPI-C" function int unsigned     dpi_mfu_exp_wr_addr();
          import "DPI-C" function longint unsigned dpi_mfu_exp_wr_data();
          import "DPI-C" function int unsigned     dpi_mfu_exp_comp_bytes();
          import "DPI-C" function int unsigned     dpi_mfu_exp_uncomp_bytes();
          import "DPI-C" function int unsigned     dpi_mfu_exp_tr_mode();
        
          // ---------------------------------------------------------------------------
          // 1. UVM Sequence Item: mfu_seq_item
          // ---------------------------------------------------------------------------
%000000   class mfu_seq_item extends uvm_sequence_item;
~000320     `uvm_object_utils(mfu_seq_item)
        
            int unsigned    txn_id;
            mlu_opcode_e    opcode;
            mlu_mem_space_e src_space;
            mlu_mem_space_e dst_space;
            bit [7:0]       tag_id;
            bit [31:0]      src_base;
            bit [31:0]      dst_base;
            bit [15:0]      src1_or_strd;
            bit [15:0]      len_or_dims;
            bit [63:0]      idx_offset;
            bit [7:0]       decomp_bitmap;
            bit [63:0]      seed64;
            bit             resp_delay_en;
        
            // Observed per-beat fields
            int unsigned    beat_idx;
            logic [63:0]    raw_rd_data;
            logic [31:0]    act_rd_addr;
            logic [2:0]     act_rd_space;
            logic [31:0]    act_wr_addr;
            logic [2:0]     act_wr_space;
            logic [63:0]    act_wr_data;
            logic [31:0]    act_comp_bytes;
            logic [31:0]    act_uncomp_bytes;
            logic           act_tr_mode;
        
~001298     function new(string name = "mfu_seq_item");
 001298       super.new(name);
            endfunction
          endclass : mfu_seq_item
        
          // ---------------------------------------------------------------------------
          // 2. UVM Sequence: mfu_sequence (All 6 DMA Opcodes + All 256 Sparsity Bitmaps)
          // ---------------------------------------------------------------------------
          class mfu_sequence extends uvm_sequence #(mfu_seq_item);
%000001     `uvm_object_utils(mfu_sequence)
        
%000001     int unsigned     num_cmds   = 320;
%000001     longint unsigned prng_state = 64'h5906_90DF_A123_4567;
        
%000001     function new(string name = "mfu_sequence");
%000001       super.new(name);
            endfunction
        
 000960     function longint unsigned next_rand64();
 000960       prng_state ^= (prng_state << 13);
 000960       prng_state ^= (prng_state >> 7);
 000960       prng_state ^= (prng_state << 17);
 000960       return prng_state;
            endfunction
        
%000001     task body();
%000001       mlu_opcode_e ops[6] = '{
%000001         OP_BANG_MEMCPY_1D, OP_BANG_MEMCPY_2D, OP_BANG_GATHER,
%000001         OP_BANG_SCATTER,   OP_BANG_DECOMP_DMA, OP_BANG_TRANSPOSE
              };
%000001       mlu_mem_space_e spaces[4] = '{
%000001         MEM_SPACE_GDRAM, MEM_SPACE_SRAM, MEM_SPACE_NRAM, MEM_SPACE_WRAM
              };
        
~000320       for (int unsigned t = 0; t < num_cmds; t++) begin
 000320         mfu_seq_item item = mfu_seq_item::type_id::create("item");
 000320         longint unsigned r0 = next_rand64();
 000320         longint unsigned r1 = next_rand64();
        
 000320         start_item(item);
 000320         item.txn_id        = t;
                // First 256 commands include full sweep of all 256 bitmaps (0x00..0xFF) on DECOMP_DMA
                // interleaved with all 6 DMA opcodes
 000256         if (t < 256) begin
 000256           item.opcode        = (t % 4 == 0) ? ops[(t / 4) % 6] : OP_BANG_DECOMP_DMA;
 000256           item.decomp_bitmap = 8'(t & 8'hFF);
 000064         end else begin
 000064           item.opcode        = ops[t % 6];
 000064           item.decomp_bitmap = r0[7:0];
                end
        
 000320         item.src_space     = spaces[r0[9:8]];
 000320         item.dst_space     = spaces[r0[11:10]];
 000320         item.tag_id        = 8'(t & 8'hFF);
 000320         item.src_base      = {16'h0010, r0[31:19], 3'b000};
 000320         item.dst_base      = {16'h0020, r0[47:35], 3'b000};
 000320         item.idx_offset    = {r1[63:51], 3'b000, r1[47:35], 3'b000,
 000320                               r1[31:19], 3'b000, r1[15:3],  3'b000};
 000320         item.seed64        = next_rand64();
 000320         item.resp_delay_en = bit'(t[0]);
        
 000022         if (item.opcode == OP_BANG_MEMCPY_2D) begin
 000022           bit [7:0] rows = 8'(1 + (r0[51:50])); // 1..4 rows
 000022           bit [7:0] cols = 8'(1 + (r0[53:52])); // 1..4 cols
 000022           bit [7:0] s_st = cols + 8'(r0[55:54]);
 000022           bit [7:0] d_st = cols + 8'(r0[57:56]);
 000022           item.len_or_dims  = {rows, cols};
 000022           item.src1_or_strd = {s_st, d_st};
 000277         end else if (item.opcode == OP_BANG_TRANSPOSE) begin
 000021           item.len_or_dims  = 16'd8;
 000021           item.src1_or_strd = 16'd0;
 000277         end else begin
 000277           item.len_or_dims  = 16'(1 + (r0[51:50])); // 1..4 beats
 000277           item.src1_or_strd = 16'd0;
                end
 000320         finish_item(item);
              end
            endtask
          endclass : mfu_sequence
        
          // ---------------------------------------------------------------------------
          // 3. UVM Sequencer: mfu_sequencer
          // ---------------------------------------------------------------------------
          class mfu_sequencer extends uvm_sequencer #(mfu_seq_item);
%000001     `uvm_component_utils(mfu_sequencer)
%000001     function new(string name = "mfu_sequencer", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
          endclass : mfu_sequencer
        
          // ---------------------------------------------------------------------------
          // 4. UVM Driver: mfu_driver
          // ---------------------------------------------------------------------------
          class mfu_driver extends uvm_driver #(mfu_seq_item);
%000001     `uvm_component_utils(mfu_driver)
        
            virtual mlu_mfu_if vif;
%000001     int unsigned driven_cmds = 0;
        
%000001     function new(string name = "mfu_driver", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       if (!uvm_config_db#(virtual mlu_mfu_if)::get(this, "", "vif", vif))
%000000         `uvm_fatal("NO_VIF", "Virtual interface mlu_mfu_if missing in mfu_driver")
            endfunction
        
%000000     task run_phase(uvm_phase phase);
%000000       mfu_seq_item item;
%000000       mlu_inst_t   inst;
%000000       logic [63:0] beat_data;
        
%000000       vif.rst_ni          = 1'b0;
%000000       vif.cmd_valid_i     = 1'b0;
%000000       vif.cmd_inst_i      = '0;
%000000       vif.idx_offset_i    = '0;
%000000       vif.decomp_bitmap_i = '0;
%000000       vif.rd_resp_valid_i = 1'b0;
%000000       vif.rd_resp_data_i  = '0;
%000000       vif.mon_beat_idx    = 16'd0;
%000004       repeat (4) @(posedge vif.clk);
%000000       #1ns;
%000000       vif.rst_ni = 1'b1;
%000000       @(posedge vif.clk);
%000000       #1ns;
        
 000320       forever begin
 000320         seq_item_port.get_next_item(item);
%000000         while (!vif.cmd_ready_o) begin
%000000           @(posedge vif.clk);
%000000           #1ns;
                end
        
 000320         inst              = '0;
 000320         inst.opcode       = item.opcode;
 000320         inst.engine       = ENG_MFU_DMA;
 000320         inst.src_space    = item.src_space;
 000320         inst.dst_space    = item.dst_space;
 000320         inst.tag_id       = item.tag_id;
 000320         inst.src0_addr    = item.src_base;
 000320         inst.dst_addr     = item.dst_base;
 000320         inst.src1_or_strd = item.src1_or_strd;
 000320         inst.len_or_dims  = item.len_or_dims;
        
 000320         vif.cmd_valid_i       = 1'b1;
 000320         vif.cmd_inst_i        = inst;
 000320         vif.idx_offset_i      = item.idx_offset;
 000320         vif.decomp_bitmap_i   = item.decomp_bitmap;
 000320         vif.mon_cmd_inst      = inst;
 000320         vif.mon_idx_offset    = item.idx_offset;
 000320         vif.mon_decomp_bitmap = item.decomp_bitmap;
 000320         vif.mon_beat_idx      = 16'd0;
        
 000320         @(posedge vif.clk);
 000320         #1ns;
 000320         vif.cmd_valid_i = 1'b0;
        
 000658         forever begin
 000658           vif.mon_latched_rd_addr  = vif.rd_req_addr_o;
 000658           vif.mon_latched_rd_space = vif.rd_req_space_o;
 000658           beat_data = item.seed64 ^ (64'(vif.mon_beat_idx) * 64'h0102_0304_0506_0708);
 000658           vif.mon_raw_rd_data = beat_data;
        
 000495           if (item.resp_delay_en) begin
 000483             vif.rd_resp_valid_i = 1'b0;
 000483             @(posedge vif.clk);
 000483             #1ns;
                  end
        
 000658           vif.rd_resp_valid_i = 1'b1;
 000658           vif.rd_resp_data_i  = beat_data;
 000658           @(posedge vif.clk);
 000658           #1ns;
 000658           vif.rd_resp_valid_i = 1'b0;
        
                  // Now in DMA_WR_REQ; monitor samples at negedge clk inside this cycle
 000658           @(posedge vif.clk);
 000658           #1ns;
 000658           vif.mon_beat_idx = vif.mon_beat_idx + 16'd1;
~000658           if (vif.done_valid_o) break;
                end
        
 000320         driven_cmds++;
 000320         seq_item_port.item_done();
              end
            endtask
          endclass : mfu_driver
        
          // ---------------------------------------------------------------------------
          // 5. UVM Monitor: mfu_monitor (with Functional Covergroup)
          // ---------------------------------------------------------------------------
          class mfu_monitor extends uvm_monitor;
%000001     `uvm_component_utils(mfu_monitor)
        
            virtual mlu_mfu_if vif;
            uvm_analysis_port #(mfu_seq_item) ap;
%000001     int unsigned seen_beats = 0;
        
            covergroup mfu_cg with function sample(
              bit [5:0] op,
              bit [2:0] s_space,
              bit [2:0] d_space,
              bit [1:0] bmp_cat
            );
              option.per_instance = 1;
              cp_op: coverpoint op {
 000053         bins b_memcpy_1d  = {OP_BANG_MEMCPY_1D};
 000106         bins b_memcpy_2d  = {OP_BANG_MEMCPY_2D};
 000058         bins b_gather     = {OP_BANG_GATHER};
 000050         bins b_scatter    = {OP_BANG_SCATTER};
 000543         bins b_decomp_dma = {OP_BANG_DECOMP_DMA};
 000168         bins b_transpose  = {OP_BANG_TRANSPOSE};
              }
              cp_bmp: coverpoint bmp_cat {
%000004         bins bmp_all_zero = {2'd0};
 000970         bins bmp_sparse   = {2'd1};
%000004         bins bmp_dense    = {2'd2};
              }
            endgroup
        
%000001     function new(string name = "mfu_monitor", uvm_component parent = null);
%000001       super.new(name, parent);
%000001       ap     = new("ap", this);
%000001       mfu_cg = new();
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       if (!uvm_config_db#(virtual mlu_mfu_if)::get(this, "", "vif", vif))
%000000         `uvm_fatal("NO_VIF", "Virtual interface mlu_mfu_if missing in mfu_monitor")
            endfunction
        
%000000     task run_phase(uvm_phase phase);
 002763       forever begin
 002763         @(negedge vif.clk);
 001785         if (vif.rst_ni && vif.wr_req_valid_o) begin
 000978           mfu_seq_item item = mfu_seq_item::type_id::create("mon_beat");
 000978           mlu_inst_t   inst = vif.mon_cmd_inst;
 000978           bit [1:0]    bcat = (vif.mon_decomp_bitmap == 8'h00) ? 2'd0 :
                                      ((vif.mon_decomp_bitmap == 8'hFF) ? 2'd2 : 2'd1);
        
 000978           item.txn_id           = seen_beats;
 000978           item.opcode           = inst.opcode;
 000978           item.src_space        = inst.src_space;
 000978           item.dst_space        = inst.dst_space;
 000978           item.tag_id           = inst.tag_id;
 000978           item.src_base         = inst.src0_addr;
 000978           item.dst_base         = inst.dst_addr;
 000978           item.src1_or_strd     = inst.src1_or_strd;
 000978           item.len_or_dims      = inst.len_or_dims;
 000978           item.idx_offset       = vif.mon_idx_offset;
 000978           item.decomp_bitmap    = vif.mon_decomp_bitmap;
 000978           item.beat_idx         = int'(vif.mon_beat_idx);
 000978           item.raw_rd_data      = vif.mon_raw_rd_data;
 000978           item.act_rd_addr      = vif.mon_latched_rd_addr;
 000978           item.act_rd_space     = vif.mon_latched_rd_space;
 000978           item.act_wr_addr      = vif.wr_req_addr_o;
 000978           item.act_wr_space     = vif.wr_req_space_o;
 000978           item.act_wr_data      = vif.wr_req_data_o;
 000978           item.act_comp_bytes   = vif.compressed_bytes_rd_o;
 000978           item.act_uncomp_bytes = vif.uncompressed_bytes_wr_o;
 000978           item.act_tr_mode      = vif.nram_transpose_mode_o;
        
 000978           mfu_cg.sample(inst.opcode, inst.src_space, inst.dst_space, bcat);
 000978           seen_beats++;
 000978           ap.write(item);
                end
              end
            endtask
          endclass : mfu_monitor
        
          // ---------------------------------------------------------------------------
          // 6. UVM Agent: mfu_agent
          // ---------------------------------------------------------------------------
          class mfu_agent extends uvm_agent;
%000001     `uvm_component_utils(mfu_agent)
        
            mfu_sequencer sequencer;
            mfu_driver    driver;
            mfu_monitor   monitor;
        
%000001     function new(string name = "mfu_agent", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       sequencer = mfu_sequencer::type_id::create("sequencer", this);
%000001       driver    = mfu_driver::type_id::create("driver", this);
%000001       monitor   = mfu_monitor::type_id::create("monitor", this);
            endfunction
        
%000001     function void connect_phase(uvm_phase phase);
%000001       super.connect_phase(phase);
%000001       driver.seq_item_port.connect(sequencer.seq_item_export);
            endfunction
          endclass : mfu_agent
        
          // ---------------------------------------------------------------------------
          // 7. UVM Scoreboard: mfu_scoreboard (Bit-Exact DPI-C Reference Check)
          // ---------------------------------------------------------------------------
          class mfu_scoreboard extends uvm_scoreboard;
%000001     `uvm_component_utils(mfu_scoreboard)
        
            uvm_analysis_imp #(mfu_seq_item, mfu_scoreboard) analysis_export;
%000001     int unsigned checked_beats = 0;
%000001     int unsigned mismatches    = 0;
        
%000001     function new(string name = "mfu_scoreboard", uvm_component parent = null);
%000001       super.new(name, parent);
%000001       analysis_export = new("analysis_export", this);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       dpi_mfu_ref_reset();
            endfunction
        
 000978     function void write(mfu_seq_item item);
 000978       logic [31:0] exp_rd_addr, exp_wr_addr, exp_comp, exp_uncomp;
 000978       logic [63:0] exp_wr_data;
 000978       logic        exp_tr_mode;
        
 000978       dpi_mfu_ref_eval_beat(
 000978         int'(item.opcode),
 000978         item.src_base,
 000978         item.dst_base,
 000978         int'(item.src1_or_strd),
 000978         int'(item.len_or_dims),
 000978         item.beat_idx,
 000978         item.idx_offset,
 000978         int'(item.decomp_bitmap),
 000978         item.raw_rd_data
              );
        
 000978       exp_rd_addr = dpi_mfu_exp_rd_addr();
 000978       exp_wr_addr = dpi_mfu_exp_wr_addr();
 000978       exp_wr_data = dpi_mfu_exp_wr_data();
 000978       exp_comp    = dpi_mfu_exp_comp_bytes();
 000978       exp_uncomp  = dpi_mfu_exp_uncomp_bytes();
 000978       exp_tr_mode = 1'(dpi_mfu_exp_tr_mode());
        
~000978       if (item.act_rd_addr      !== exp_rd_addr ||
                  item.act_wr_addr      !== exp_wr_addr ||
                  item.act_wr_data      !== exp_wr_data ||
                  item.act_comp_bytes   !== exp_comp    ||
                  item.act_uncomp_bytes !== exp_uncomp  ||
                  item.act_tr_mode      !== exp_tr_mode ||
                  item.act_rd_space     !== item.src_space ||
%000000           item.act_wr_space     !== item.dst_space) begin
%000000         mismatches++;
                `uvm_error("MFU_MISMATCH", $sformatf(
                  "beat=%0d op=%02x rd_addr=%08x/%08x wr_addr=%08x/%08x wr_data=%016x/%016x comp=%0d/%0d uncomp=%0d/%0d tr=%0b/%0b",
                  item.txn_id, item.opcode, item.act_rd_addr, exp_rd_addr,
                  item.act_wr_addr, exp_wr_addr, item.act_wr_data, exp_wr_data,
                  item.act_comp_bytes, exp_comp, item.act_uncomp_bytes, exp_uncomp,
%000000           item.act_tr_mode, exp_tr_mode))
              end
 000978       checked_beats++;
            endfunction
          endclass : mfu_scoreboard
        
          // ---------------------------------------------------------------------------
          // 8. UVM Environment & Test: mfu_env, mfu_dma_decomp_test
          // ---------------------------------------------------------------------------
          class mfu_env extends uvm_env;
%000001     `uvm_component_utils(mfu_env)
            mfu_agent      agent;
            mfu_scoreboard scoreboard;
%000001     function new(string name = "mfu_env", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       agent      = mfu_agent::type_id::create("agent", this);
%000001       scoreboard = mfu_scoreboard::type_id::create("scoreboard", this);
            endfunction
%000001     function void connect_phase(uvm_phase phase);
%000001       super.connect_phase(phase);
%000001       agent.monitor.ap.connect(scoreboard.analysis_export);
            endfunction
          endclass : mfu_env
        
          class mfu_dma_decomp_test extends uvm_test;
%000002     `uvm_component_utils(mfu_dma_decomp_test)
            mfu_env env;
%000001     function new(string name = "mfu_dma_decomp_test", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       env = mfu_env::type_id::create("env", this);
            endfunction
%000001     task run_phase(uvm_phase phase);
%000001       mfu_sequence seq = mfu_sequence::type_id::create("seq");
%000001       phase.raise_objection(this);
%000001       seq.start(env.agent.sequencer);
%000001       phase.drop_objection(this);
            endtask
%000001     function void report_phase(uvm_phase phase);
%000001       int unsigned dpi_calls = dpi_mfu_get_calls();
%000001       real         func_cov  = env.agent.monitor.mfu_cg.get_inst_coverage();
              bit          pass_gate = (env.agent.driver.driven_cmds == 320) &&
                                       (env.scoreboard.checked_beats >= 800) &&
                                       (dpi_calls == env.scoreboard.checked_beats) &&
%000001                                (env.scoreboard.mismatches == 0) &&
                                       (func_cov == 100.0);
%000001       super.report_phase(phase);
%000001       dpi_mfu_set_status(pass_gate ? 0 : 1);
%000001       if (!pass_gate) begin
                `uvm_fatal("UVM_MFU_FAIL", $sformatf(
                  "MFU UVM failed: cmds=%0d beats=%0d mismatches=%0d cov=%0.2f%%",
                  env.agent.driver.driven_cmds, env.scoreboard.checked_beats,
%000000           env.scoreboard.mismatches, func_cov))
%000001       end else begin
                `uvm_info("UVM_MFU_PASS", $sformatf(
                  "PASS: %0d DMA commands (%0d beats) verified bit-exact via DPI-C, 0 mismatches, %0.2f%% functional coverage",
%000001           env.agent.driver.driven_cmds, env.scoreboard.checked_beats, func_cov), UVM_LOW)
              end
            endfunction
          endclass : mfu_dma_decomp_test
        
        endpackage : mlu_mfu_uvm_pkg
        
        `endif // MLU_MFU_UVM_PKG_SV
        
