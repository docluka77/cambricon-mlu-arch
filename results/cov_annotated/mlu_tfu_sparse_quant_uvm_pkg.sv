//      // verilator_coverage annotation
        // =============================================================================
        // File: uvm_tb/uvm_tfu_sparse_quant/mlu_tfu_sparse_quant_uvm_pkg.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: Accellera IEEE 1800.2-2020 UVM Verification Package for Suite 3:
        //              mlu_tfu_fractal_mac across all 8 precisions, Cambricon-S 2:4 &
        //              4x4 Block Sparsity, and Cambricon-Q Statistical Quantization.
        // =============================================================================
        `ifndef MLU_TFU_SPARSE_QUANT_UVM_PKG_SV
        `define MLU_TFU_SPARSE_QUANT_UVM_PKG_SV
        
        `timescale 1ns/1ps
        `include "uvm_macros.svh"
        `include "mlu_pkg.sv"
        
        package mlu_tfu_sparse_quant_uvm_pkg;
          import uvm_pkg::*;
          import mlu_pkg::*;
        
          // DPI-C C++17 Bit-Exact TFU Reference Model Imports
          import "DPI-C" function void             dpi_tfu_set_status(int status);
          import "DPI-C" function int              dpi_tfu_get_status();
          import "DPI-C" function int unsigned     dpi_tfu_get_calls();
          import "DPI-C" function void             dpi_tfu_reset();
          import "DPI-C" function void             dpi_tfu_eval_and_step(
            int unsigned     cmd_valid,
            longint unsigned cmd_inst_hi,
            longint unsigned cmd_inst_lo,
            int unsigned     stream_valid,
            longint unsigned act_w0, longint unsigned act_w1, longint unsigned act_w2, longint unsigned act_w3,
            longint unsigned wt_w0,  longint unsigned wt_w1,  longint unsigned wt_w2,  longint unsigned wt_w3,
            int unsigned     sparse_meta,
            int unsigned     quant_scale,
            int unsigned     quant_zp
          );
          import "DPI-C" function int unsigned     dpi_tfu_exp_cmd_ready();
          import "DPI-C" function int unsigned     dpi_tfu_exp_stream_ready();
          import "DPI-C" function int unsigned     dpi_tfu_exp_tfu_busy();
          import "DPI-C" function int unsigned     dpi_tfu_exp_result_valid();
          import "DPI-C" function int unsigned     dpi_tfu_exp_done_valid();
          import "DPI-C" function int unsigned     dpi_tfu_exp_done_tag();
          import "DPI-C" function longint unsigned dpi_tfu_exp_res_word(int w);
          import "DPI-C" function int unsigned     dpi_tfu_exp_zero_skip_cnt();
          import "DPI-C" function int unsigned     dpi_tfu_exp_total_mac_ops();
        
 001200   function automatic logic [127:0] pack_tfu_inst(
            input mlu_opcode_e      op,
            input mlu_prec_e        prec,
            input mlu_sparse_mode_e sp_mode,
            input logic [7:0]       tag,
            input logic [15:0]      beats
          );
 001200     pack_tfu_inst = {op, ENG_TFU_MAT, prec, sp_mode, MEM_SPACE_NRAM, MEM_SPACE_NRAM,
 001200                      4'b0000, tag, 32'h0000_1000, 32'h0000_0000, 16'd0, beats};
          endfunction
        
          // ---------------------------------------------------------------------------
          // 1. UVM Sequence Item: mlu_tfu_seq_item
          // ---------------------------------------------------------------------------
%000000   class mlu_tfu_seq_item extends uvm_sequence_item;
~001200     `uvm_object_utils(mlu_tfu_seq_item)
        
            int unsigned  cycle_id;
            logic         cmd_valid;
            logic [127:0] cmd_inst;
            logic         stream_valid;
            logic [255:0] nram_act;
            logic [255:0] wram_wt;
            logic [31:0]  wram_sparse_meta;
            logic [15:0]  quant_scale;
            logic [7:0]   quant_zp;
        
            // Observed DUT Outputs
            logic         act_cmd_ready;
            logic         act_stream_ready;
            logic         act_tfu_busy;
            logic [255:0] act_result_data;
            logic         act_result_valid;
            logic         act_done_valid;
            logic [7:0]   act_done_tag;
            logic [31:0]  act_zero_skip_cnt;
            logic [31:0]  act_total_mac_ops;
        
~002400     function new(string name = "mlu_tfu_seq_item");
 002400       super.new(name);
            endfunction
          endclass : mlu_tfu_seq_item
          // ---------------------------------------------------------------------------
          // 2. UVM Sequencer & Sequence (1,200 Cycles Across All 8 Precisions,
          //    Cambricon-S 2:4 & 4x4 Sparsity, and Cambricon-Q Statistical Quantization)
          // ---------------------------------------------------------------------------
          class mlu_tfu_sequencer extends uvm_sequencer #(mlu_tfu_seq_item);
%000001     `uvm_component_utils(mlu_tfu_sequencer)
%000001     function new(string name = "mlu_tfu_sequencer", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
          endclass : mlu_tfu_sequencer
        
          class mlu_tfu_sequence extends uvm_sequence #(mlu_tfu_seq_item);
%000001     `uvm_object_utils(mlu_tfu_sequence)
        
%000001     int unsigned num_cycles = 1200;
%000001     longint unsigned prng_state = 64'h7F05_9069_0BEE_FCAFE;
        
%000001     function new(string name = "mlu_tfu_sequence");
%000001       super.new(name);
            endfunction
        
 004800     function longint unsigned next_rand64();
 004800       prng_state ^= (prng_state << 13);
 004800       prng_state ^= (prng_state >> 7);
 004800       prng_state ^= (prng_state << 17);
 004800       return prng_state;
            endfunction
        
%000001     task body();
~001200       for (int unsigned cyc = 0; cyc < num_cycles; cyc++) begin
 001200         mlu_tfu_seq_item item = mlu_tfu_seq_item::type_id::create("item");
 001200         longint unsigned r0 = next_rand64();
 001200         longint unsigned r1 = next_rand64();
 001200         longint unsigned r2 = next_rand64();
 001200         longint unsigned r3 = next_rand64();
 001200         int unsigned txn_id = cyc / 6;
 001200         int unsigned step   = cyc % 6;
 001200         mlu_prec_e        prec_v;
 001200         mlu_sparse_mode_e sp_v;
 001200         mlu_opcode_e      op_v;
 001200         start_item(item);
        
                // Sweep all 8 precisions, all 4 sparsity modes, and OP_BANG_MATMUL / SPARSE_MM / QUANT_MM
 001200         prec_v = mlu_prec_e'(txn_id % 8);
 000816         if (txn_id < 64) begin
 000384           sp_v = mlu_sparse_mode_e'((txn_id / 8) % 4);
 000816         end else begin
 000816           sp_v = mlu_sparse_mode_e'(txn_id % 4);
                end
 000396         if ((txn_id % 3) == 2) begin
 000396           op_v = OP_BANG_QUANT_MM;
 000600         end else if (sp_v != SPARSE_DENSE) begin
 000600           op_v = OP_BANG_SPARSE_MM;
 000204         end else begin
 000204           op_v = OP_BANG_MATMUL;
                end
        
 001200         item.cycle_id         = cyc;
 001200         item.cmd_valid        = (step == 0);
 001200         item.cmd_inst         = pack_tfu_inst(op_v, prec_v, sp_v, 8'(txn_id & 8'hFF), 16'd4);
 001200         item.stream_valid     = (step >= 1 && step <= 4);
 001200         item.nram_act         = {r3, r2, r1, r0};
 001200         item.wram_wt          = {r0 ^ r2, r1 ^ r3, r2 + r0, r3 + r1};
                // In SPARSE_BLOCK_4X4 mode, force alternating zero/non-zero bitmap bits (0xA = 4'b1010)
 000900         if (sp_v == SPARSE_BLOCK_4X4) begin
 000300           item.wram_sparse_meta = 32'h0000_000A;
 000900         end else begin
 000900           item.wram_sparse_meta = r0[31:0];
                end
 001200         item.quant_scale      = 16'h0040 + 16'((txn_id * 13) & 16'h01FF);
 001200         item.quant_zp         = 8'((txn_id * 7) - 32);
        
 001200         finish_item(item);
              end
            endtask
          endclass : mlu_tfu_sequence
          // ---------------------------------------------------------------------------
          // 3. UVM Driver: mlu_tfu_driver
          // ---------------------------------------------------------------------------
          class mlu_tfu_driver extends uvm_driver #(mlu_tfu_seq_item);
%000001     `uvm_component_utils(mlu_tfu_driver)
        
            virtual mlu_tfu_sparse_quant_if vif;
%000001     int unsigned driven = 0;
        
%000001     function new(string name = "mlu_tfu_driver", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       if (!uvm_config_db#(virtual mlu_tfu_sparse_quant_if)::get(this, "", "vif", vif)) begin
%000000         `uvm_fatal("NO_VIF", "Virtual interface mlu_tfu_sparse_quant_if missing in mlu_tfu_driver")
              end
            endfunction
        
%000000     task run_phase(uvm_phase phase);
%000000       mlu_tfu_seq_item item;
%000000       vif.rst_n       = 1'b0;
%000000       vif.cycle_valid = 1'b0;
%000000       dpi_tfu_reset();
%000003       repeat (3) @(negedge vif.clk);
        
 001200       forever begin
 001200         seq_item_port.get_next_item(item);
 001200         vif.rst_n              = 1'b1;
 001200         vif.cycle_id           = item.cycle_id;
 001200         vif.cmd_valid_i        = item.cmd_valid;
 001200         vif.cmd_inst_i         = item.cmd_inst;
 001200         vif.stream_valid_i     = item.stream_valid;
 001200         vif.nram_act_i         = item.nram_act;
 001200         vif.wram_wt_i          = item.wram_wt;
 001200         vif.wram_sparse_meta_i = item.wram_sparse_meta;
 001200         vif.quant_scale_i      = item.quant_scale;
 001200         vif.quant_zp_i         = item.quant_zp;
        
 001200         vif.cycle_valid = 1'b1;
 001200         @(posedge vif.clk);
 001200         #1ns;
 001200         vif.cycle_valid = 1'b0;
 001200         driven++;
 001200         @(negedge vif.clk);
 001200         seq_item_port.item_done();
              end
            endtask
          endclass : mlu_tfu_driver
        
          // ---------------------------------------------------------------------------
          // 4. UVM Monitor: mlu_tfu_monitor (with Functional Covergroup)
          // ---------------------------------------------------------------------------
          class mlu_tfu_monitor extends uvm_monitor;
%000001     `uvm_component_utils(mlu_tfu_monitor)
        
            virtual mlu_tfu_sparse_quant_if vif;
            uvm_analysis_port #(mlu_tfu_seq_item) ap;
%000001     int unsigned seen = 0;
        
            covergroup mlu_tfu_cg with function sample(
              bit [2:0] prec_mode,
              bit [1:0] sp_mode,
              bit       is_quant_op,
              bit       res_valid
            );
              option.per_instance = 1;
              cp_prec: coverpoint prec_mode {
 000150         bins p_int4     = {3'd0};
 000150         bins p_int8     = {3'd1};
 000150         bins p_fp8_e4m3 = {3'd2};
 000150         bins p_fp8_e5m2 = {3'd3};
 000150         bins p_fp16     = {3'd4};
 000150         bins p_bf16     = {3'd5};
 000150         bins p_tf32     = {3'd6};
 000150         bins p_fp32     = {3'd7};
              }
              cp_sparse: coverpoint sp_mode {
 000300         bins s_dense    = {2'd0};
 000300         bins s_2_of_4   = {2'd1};
 000300         bins s_blk_4x4  = {2'd2};
 000300         bins s_indexed  = {2'd3};
              }
 000804       cp_quant: coverpoint is_quant_op { bins b0 = {0}; bins b1 = {1}; }
 001000       cp_valid: coverpoint res_valid   { bins b0 = {0}; bins b1 = {1}; }
            endgroup
        
%000001     function new(string name = "mlu_tfu_monitor", uvm_component parent = null);
%000001       super.new(name, parent);
%000001       ap = new("ap", this);
%000001       mlu_tfu_cg = new();
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       if (!uvm_config_db#(virtual mlu_tfu_sparse_quant_if)::get(this, "", "vif", vif)) begin
%000000         `uvm_fatal("NO_VIF", "Virtual interface mlu_tfu_sparse_quant_if missing in mlu_tfu_monitor")
              end
            endfunction
%000000     task run_phase(uvm_phase phase);
 001202       forever begin
 001202         @(negedge vif.clk);
 001202         #1ns;
~001200         if (vif.rst_n && vif.cycle_valid) begin
 001200           mlu_tfu_seq_item item = mlu_tfu_seq_item::type_id::create("obs_item");
 001200           item.cycle_id          = vif.cycle_id;
 001200           item.cmd_valid         = vif.cmd_valid_i;
 001200           item.cmd_inst          = vif.cmd_inst_i;
 001200           item.stream_valid      = vif.stream_valid_i;
 001200           item.nram_act          = vif.nram_act_i;
 001200           item.wram_wt           = vif.wram_wt_i;
 001200           item.wram_sparse_meta  = vif.wram_sparse_meta_i;
 001200           item.quant_scale       = vif.quant_scale_i;
 001200           item.quant_zp          = vif.quant_zp_i;
        
 001200           item.act_cmd_ready     = vif.cmd_ready_o;
 001200           item.act_stream_ready  = vif.stream_ready_o;
 001200           item.act_tfu_busy      = vif.tfu_busy_o;
 001200           item.act_result_data   = vif.result_data_o;
 001200           item.act_result_valid  = vif.result_valid_o;
 001200           item.act_done_valid    = vif.done_valid_o;
 001200           item.act_done_tag      = vif.done_tag_o;
 001200           item.act_zero_skip_cnt = vif.zero_skip_cnt_o;
 001200           item.act_total_mac_ops = vif.total_mac_ops_o;
        
 001200           mlu_tfu_cg.sample(
 001200             vif.cmd_inst_i[118:116],
 001200             vif.cmd_inst_i[115:114],
 001200             (vif.cmd_inst_i[127:122] == OP_BANG_QUANT_MM),
 001200             vif.result_valid_o
                  );
        
 001200           seen++;
 001200           ap.write(item);
                end
              end
            endtask
          endclass : mlu_tfu_monitor
        
          // ---------------------------------------------------------------------------
          // 5. UVM Agent, DPI-C Scoreboard, Environment, and Test
          // ---------------------------------------------------------------------------
          class mlu_tfu_agent extends uvm_agent;
%000001     `uvm_component_utils(mlu_tfu_agent)
            mlu_tfu_sequencer sequencer;
            mlu_tfu_driver    driver;
            mlu_tfu_monitor   monitor;
%000001     function new(string name = "mlu_tfu_agent", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       sequencer = mlu_tfu_sequencer::type_id::create("sequencer", this);
%000001       driver    = mlu_tfu_driver::type_id::create("driver", this);
%000001       monitor   = mlu_tfu_monitor::type_id::create("monitor", this);
            endfunction
%000001     function void connect_phase(uvm_phase phase);
%000001       super.connect_phase(phase);
%000001       driver.seq_item_port.connect(sequencer.seq_item_export);
            endfunction
          endclass : mlu_tfu_agent
        
          class mlu_tfu_scoreboard extends uvm_scoreboard;
%000001     `uvm_component_utils(mlu_tfu_scoreboard)
        
            uvm_analysis_imp #(mlu_tfu_seq_item, mlu_tfu_scoreboard) analysis_export;
        
%000001     int unsigned checked_cycles = 0;
%000001     int unsigned mismatches     = 0;
%000001     int unsigned tiles_retired  = 0;
        
%000001     function new(string name = "mlu_tfu_scoreboard", uvm_component parent = null);
%000001       super.new(name, parent);
%000001       analysis_export = new("analysis_export", this);
            endfunction
        
 001200     function void write(mlu_tfu_seq_item item);
 001200       logic [255:0] exp_res_vec;
        
 001200       dpi_tfu_eval_and_step(
 001200         {31'd0, item.cmd_valid},
 001200         item.cmd_inst[127:64],
 001200         item.cmd_inst[63:0],
 001200         {31'd0, item.stream_valid},
 001200         item.nram_act[63:0],  item.nram_act[127:64], item.nram_act[191:128], item.nram_act[255:192],
 001200         item.wram_wt[63:0],   item.wram_wt[127:64],  item.wram_wt[191:128],  item.wram_wt[255:192],
 001200         item.wram_sparse_meta,
 001200         {16'd0, item.quant_scale},
 001200         {24'd0, item.quant_zp}
              );
        
 001200       exp_res_vec = {
 001200         dpi_tfu_exp_res_word(3),
 001200         dpi_tfu_exp_res_word(2),
 001200         dpi_tfu_exp_res_word(1),
 001200         dpi_tfu_exp_res_word(0)
              };
        
 001200       checked_cycles++;
 001000       if (item.act_result_valid) tiles_retired++;
        
~001200       if (item.act_cmd_ready     !== dpi_tfu_exp_cmd_ready()[0]    ||
                  item.act_stream_ready  !== dpi_tfu_exp_stream_ready()[0] ||
                  item.act_tfu_busy      !== dpi_tfu_exp_tfu_busy()[0]     ||
                  item.act_result_valid  !== dpi_tfu_exp_result_valid()[0] ||
                  item.act_done_valid    !== dpi_tfu_exp_done_valid()[0]   ||
                  item.act_done_tag      !== dpi_tfu_exp_done_tag()[7:0]   ||
                  item.act_zero_skip_cnt !== dpi_tfu_exp_zero_skip_cnt()   ||
                  item.act_total_mac_ops !== dpi_tfu_exp_total_mac_ops()   ||
%000000           (item.act_result_valid && (item.act_result_data !== exp_res_vec))) begin
                `uvm_error("TFU_MISMATCH", $sformatf(
                  "Cyc %0d: rval=%b(%b) skip=%0d(%0d) ops=%0d(%0d) res=%h(exp %h)",
                  item.cycle_id,
                  item.act_result_valid, dpi_tfu_exp_result_valid()[0],
                  item.act_zero_skip_cnt, dpi_tfu_exp_zero_skip_cnt(),
                  item.act_total_mac_ops, dpi_tfu_exp_total_mac_ops(),
%000000           item.act_result_data, exp_res_vec))
%000000         mismatches++;
              end
            endfunction
          endclass : mlu_tfu_scoreboard
          class mlu_tfu_env extends uvm_env;
%000001     `uvm_component_utils(mlu_tfu_env)
            mlu_tfu_agent      agent;
            mlu_tfu_scoreboard scoreboard;
%000001     function new(string name = "mlu_tfu_env", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       agent      = mlu_tfu_agent::type_id::create("agent", this);
%000001       scoreboard = mlu_tfu_scoreboard::type_id::create("scoreboard", this);
            endfunction
%000001     function void connect_phase(uvm_phase phase);
%000001       super.connect_phase(phase);
%000001       agent.monitor.ap.connect(scoreboard.analysis_export);
            endfunction
          endclass : mlu_tfu_env
        
          class mlu_tfu_sparse_quant_test extends uvm_test;
%000002     `uvm_component_utils(mlu_tfu_sparse_quant_test)
            mlu_tfu_env env;
%000001     function new(string name = "mlu_tfu_sparse_quant_test", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       env = mlu_tfu_env::type_id::create("env", this);
            endfunction
%000001     task run_phase(uvm_phase phase);
%000001       mlu_tfu_sequence seq = mlu_tfu_sequence::type_id::create("seq");
%000001       phase.raise_objection(this);
%000001       seq.start(env.agent.sequencer);
%000001       phase.drop_objection(this);
            endtask
%000001     function void report_phase(uvm_phase phase);
%000001       real func_cov = env.agent.monitor.mlu_tfu_cg.get_inst_coverage();
              bit pass_gate = (env.agent.driver.driven == 1200) &&
                              (env.scoreboard.checked_cycles == 1200) &&
                              (env.scoreboard.mismatches == 0) &&
                              (env.scoreboard.tiles_retired == 200) &&
%000001                       (dpi_tfu_exp_zero_skip_cnt() >= 80) &&
                              (dpi_tfu_exp_total_mac_ops() >= 10000);
%000001       super.report_phase(phase);
%000001       dpi_tfu_set_status(pass_gate ? 0 : 1);
%000001       if (!pass_gate) begin
                `uvm_fatal("UVM_TFU_FAIL", $sformatf("Suite 3 gate failed: mismatches=%0d tiles=%0d cov=%0.2f%%",
%000000           env.scoreboard.mismatches, env.scoreboard.tiles_retired, func_cov))
%000001       end else begin
                `uvm_info("UVM_TFU_PASS", $sformatf(
                  "SUITE 3 PASS: cycles=%0d dpi_calls=%0d tiles=%0d zero_skips=%0d total_mac_ops=%0d cov=%0.2f%%",
                  env.scoreboard.checked_cycles, dpi_tfu_get_calls(),
                  env.scoreboard.tiles_retired, dpi_tfu_exp_zero_skip_cnt(),
%000001           dpi_tfu_exp_total_mac_ops(), func_cov), UVM_LOW)
              end
            endfunction
          endclass : mlu_tfu_sparse_quant_test
        
        endpackage : mlu_tfu_sparse_quant_uvm_pkg
        
        `endif // MLU_TFU_SPARSE_QUANT_UVM_PKG_SV
        
