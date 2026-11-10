//      // verilator_coverage annotation
        // =============================================================================
        // File: uvm_tb/uvm_bang_icu_pmu/mlu_bang_icu_pmu_uvm_pkg.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: Accellera IEEE 1800.2-2020 UVM Verification Package for Suite 2:
        //              mlu_bang_icu and mlu_pmu_clock_gate.
        // =============================================================================
        `ifndef MLU_BANG_ICU_PMU_UVM_PKG_SV
        `define MLU_BANG_ICU_PMU_UVM_PKG_SV
        
        `timescale 1ns/1ps
        `include "uvm_macros.svh"
        `include "mlu_pkg.sv"
        
        package mlu_bang_icu_pmu_uvm_pkg;
          import uvm_pkg::*;
          import mlu_pkg::*;
        
          // DPI-C C++17 Cycle-Accurate ICU + PMU Reference Model Imports
          import "DPI-C" function void         dpi_icu_set_status(int status);
          import "DPI-C" function int          dpi_icu_get_status();
          import "DPI-C" function int unsigned dpi_icu_get_calls();
          import "DPI-C" function void         dpi_icu_reset();
          import "DPI-C" function void         dpi_icu_eval_and_step(
            int unsigned     inst_valid,
            longint unsigned inst_hi,
            longint unsigned inst_lo,
            int unsigned     eng_ready,
            int unsigned     cluster_ack,
            int unsigned     done_valid,
            longint unsigned done_tags_packed
          );
          import "DPI-C" function int unsigned dpi_icu_exp_inst_ready();
          import "DPI-C" function int unsigned dpi_icu_exp_eng_cmd_valid();
          import "DPI-C" function int unsigned dpi_icu_exp_dispatch_mask();
          import "DPI-C" function int unsigned dpi_icu_exp_cluster_sync_req();
          import "DPI-C" function int unsigned dpi_icu_exp_queue_busy();
          import "DPI-C" function int unsigned dpi_icu_exp_hazard_stall();
          import "DPI-C" function int unsigned dpi_icu_exp_inst_retired_cnt();
          import "DPI-C" function int unsigned dpi_icu_exp_hazard_stall_cnt();
          import "DPI-C" function int unsigned dpi_pmu_exp_eng_clk_en();
          import "DPI-C" function int unsigned dpi_pmu_exp_sram_slp();
          import "DPI-C" function int unsigned dpi_pmu_exp_sram_dslp();
          import "DPI-C" function int unsigned dpi_pmu_exp_sram_wake_ready();
          import "DPI-C" function int unsigned dpi_pmu_exp_gated_saved_cycles();
          import "DPI-C" function int unsigned dpi_pmu_exp_sram_sleep_cycles();
        
 000533   function automatic logic [127:0] pack_bang_inst(
            input mlu_opcode_e      op,
            input mlu_engine_e      eng,
            input mlu_prec_e        prec,
            input mlu_sparse_mode_e sp_mode,
            input mlu_mem_space_e   src_sp,
            input mlu_mem_space_e   dst_sp,
            input logic [3:0]       dep,
            input logic [7:0]       tag,
            input logic [31:0]      dst_a,
            input logic [31:0]      src0_a,
            input logic [15:0]      src1_s,
            input logic [15:0]      len_d
          );
 000533     pack_bang_inst = {op, eng, prec, sp_mode, src_sp, dst_sp, dep, tag, dst_a, src0_a, src1_s, len_d};
          endfunction
        
          // ---------------------------------------------------------------------------
          // 1. UVM Sequence Item: mlu_icu_seq_item
          // ---------------------------------------------------------------------------
%000000   class mlu_icu_seq_item extends uvm_sequence_item;
~001200     `uvm_object_utils(mlu_icu_seq_item)
        
            int unsigned     cycle_id;
            logic            inst_valid;
            logic [127:0]    inst_word;
            logic [4:0]      eng_cmd_ready;
            logic            cluster_sync_ack;
            logic [4:0]      eng_done_valid;
            logic [4:0][7:0] eng_done_tag;
        
            // Observed DUT Outputs
            logic        act_inst_ready;
            logic [4:0]  act_eng_cmd_valid;
            logic [4:0]  act_icu_dispatch_mask;
            logic        act_cluster_sync_req;
            logic [4:0]  act_queue_busy;
            logic        act_hazard_stall;
            logic [31:0] act_inst_retired_cnt;
            logic [31:0] act_hazard_stall_cnt;
            logic [4:0]  act_eng_clk_en;
            logic [2:0]  act_sram_slp;
            logic [2:0]  act_sram_dslp;
            logic [2:0]  act_sram_wake_ready;
            logic [31:0] act_gated_saved_cycles;
            logic [31:0] act_sram_sleep_cycles;
        
~002400     function new(string name = "mlu_icu_seq_item");
 002400       super.new(name);
            endfunction
          endclass : mlu_icu_seq_item
          // ---------------------------------------------------------------------------
          // 2. UVM Sequencer & Sequence (1,200 Cycles Directed + Constrained-Random)
          // ---------------------------------------------------------------------------
          class mlu_icu_sequencer extends uvm_sequencer #(mlu_icu_seq_item);
%000001     `uvm_component_utils(mlu_icu_sequencer)
%000001     function new(string name = "mlu_icu_sequencer", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
          endclass : mlu_icu_sequencer
        
          class mlu_icu_sequence extends uvm_sequence #(mlu_icu_seq_item);
%000001     `uvm_object_utils(mlu_icu_sequence)
        
%000001     int unsigned num_cycles = 1200;
%000001     longint unsigned prng_state = 64'hBA66_1C00_5906_9002;
        
%000001     function new(string name = "mlu_icu_sequence");
%000001       super.new(name);
            endfunction
        
 001200     function longint unsigned next_rand64();
 001200       prng_state ^= (prng_state << 13);
 001200       prng_state ^= (prng_state >> 7);
 001200       prng_state ^= (prng_state << 17);
 001200       return prng_state;
            endfunction
        
%000001     task body();
~001200       for (int unsigned cyc = 0; cyc < num_cycles; cyc++) begin
 001200         mlu_icu_seq_item item = mlu_icu_seq_item::type_id::create("item");
 001200         longint unsigned r0 = next_rand64();
 001200         start_item(item);
        
 001200         item.cycle_id         = cyc;
 001200         item.inst_valid       = 1'b0;
 001200         item.inst_word        = 128'd0;
 001200         item.eng_cmd_ready    = 5'b11111;
 001200         item.cluster_sync_ack = 1'b0;
 001200         item.eng_done_valid   = 5'b00000;
 001200         item.eng_done_tag     = '0;
        
                // Phase 0 (0..99): OP_PWR_GATE_CFG (threshold=2), Idle Sleep/Deep-Sleep,
                // and 0-Cycle Clock Wakeup across all 5 execution engines
%000001         if (cyc == 2) begin
%000001           item.inst_valid = 1'b1;
%000001           item.inst_word  = pack_bang_inst(OP_PWR_GATE_CFG, ENG_ICU_CTRL, PREC_INT8, SPARSE_DENSE,
%000001                                            MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h01,
%000001                                            32'd0, 32'd0, 16'd0, 16'd2);
 000010         end else if (cyc >= 20 && cyc < 30) begin
 000010           int q = ((cyc - 20) / 2) % 5;
%000005           if ((cyc % 2) == 0) begin
%000005             mlu_engine_e eng_v = mlu_engine_e'(q + 1);
%000005             item.inst_valid = 1'b1;
%000005             item.inst_word  = pack_bang_inst(OP_BANG_MATMUL, eng_v, PREC_INT8, SPARSE_DENSE,
%000005                                              MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'(8'h10 + q),
%000005                                              32'((q + 1) << 12), 32'((q + 8) << 12), 16'd0, 16'd1);
%000005           end else begin
%000005             item.eng_done_valid[q] = 1'b1;
%000005             item.eng_done_tag[q]   = 8'(8'h10 + q);
                  end
                end
                // Phase 1 (100..299): Intentional RAW, WAR, WAW Memory Hazards on NRAM/WRAM/SRAM
                // and Explicit dep_mask Barriers
 000180         else if (cyc >= 100 && cyc < 280) begin
 000180           int blk = (cyc - 100) / 10;
 000180           int step = (cyc - 100) % 10;
 000180           mlu_mem_space_e sp = (blk % 3 == 0) ? MEM_SPACE_NRAM :
                                       (blk % 3 == 1) ? MEM_SPACE_WRAM : MEM_SPACE_SRAM;
 000180           logic [31:0] reg_a = 32'h0000_2000;
 000180           logic [31:0] reg_b = 32'h0000_4000;
 000018           if (step == 0) begin
                    // Producer instruction writing to reg_a, reading from reg_b on queue (blk % 5)
 000018             int q = blk % 5;
 000018             item.inst_valid = 1'b1;
 000018             item.inst_word  = pack_bang_inst(OP_BANG_VADD, mlu_engine_e'(q + 1), PREC_FP16, SPARSE_DENSE,
 000018                                              sp, sp, 4'b0000, 8'(8'h20 + blk), reg_a, reg_b, 16'h0800, 16'd1);
 000054           end else if (step >= 1 && step <= 3) begin
                    // Dependent consumer instruction held valid during hazard stall (step 1..2),
                    // producer completes at step 2 so consumer issues cleanly at step 3!
 000054             int q_prod = blk % 5;
 000054             int q_cons = (blk + 1) % 5;
 000054             item.inst_valid = 1'b1;
 000015             if ((blk % 4) == 0) begin
                      // RAW hazard: consumer reads reg_a
 000015               item.inst_word = pack_bang_inst(OP_BANG_VMUL, mlu_engine_e'(q_cons + 1), PREC_FP16, SPARSE_DENSE,
 000015                                               sp, sp, 4'b0000, 8'(8'h40 + blk), 32'h0000_6000, reg_a, 16'd0, 16'd1);
 000015             end else if ((blk % 4) == 1) begin
                      // WAW hazard: consumer writes reg_a
 000015               item.inst_word = pack_bang_inst(OP_BANG_VMUL, mlu_engine_e'(q_cons + 1), PREC_FP16, SPARSE_DENSE,
 000015                                               sp, sp, 4'b0000, 8'(8'h40 + blk), reg_a, 32'h0000_6000, 16'd0, 16'd1);
 000012             end else if ((blk % 4) == 2) begin
                      // WAR hazard: consumer writes reg_b (which producer reads)
 000012               item.inst_word = pack_bang_inst(OP_BANG_VMUL, mlu_engine_e'(q_cons + 1), PREC_FP16, SPARSE_DENSE,
 000012                                               sp, sp, 4'b0000, 8'(8'h40 + blk), reg_b, 32'h0000_6000, 16'd0, 16'd1);
 000012             end else begin
                      // Explicit dep_mask barrier
 000012               item.inst_word = pack_bang_inst(OP_BANG_VMUL, mlu_engine_e'(q_cons + 1), PREC_FP16, SPARSE_DENSE,
 000012                                               MEM_SPACE_GDRAM, MEM_SPACE_GDRAM, 4'b1111, 8'(8'h40 + blk),
 000012                                               32'h0000_8000, 32'h0000_9000, 16'd0, 16'd1);
                    end
 000036             if (step == 2) begin
 000018               item.eng_done_valid[q_prod] = 1'b1;
 000018               item.eng_done_tag[q_prod]   = 8'(8'h20 + blk);
                    end
 000090           end else if (step == 5) begin
 000018             int q_cons = (blk + 1) % 5;
 000018             item.eng_done_valid[q_cons] = 1'b1;
 000018             item.eng_done_tag[q_cons]   = 8'(8'h40 + blk);
                  end
                end
                // Phase 2 (300..449): OP_SYNC_IPU & OP_SYNC_CLUSTER Handshake Verification
 000140         else if (cyc >= 300 && cyc < 440) begin
 000140           int step = (cyc - 300) % 14;
 000010           if (step == 0) begin
                    // Issue MFU DMA instruction
 000010             item.inst_valid = 1'b1;
 000010             item.inst_word  = pack_bang_inst(OP_BANG_MEMCPY_1D, ENG_MFU_DMA, PREC_INT8, SPARSE_DENSE,
 000010                                              MEM_SPACE_GDRAM, MEM_SPACE_NRAM, 4'b0000, 8'h77,
 000010                                              32'h0001_0000, 32'h0002_0000, 16'd0, 16'd4);
 000030           end else if (step >= 1 && step <= 3) begin
                    // Issue OP_SYNC_IPU: stalls while MFU is busy (step 1..2), retires at step 3
 000030             item.inst_valid = 1'b1;
 000030             item.inst_word  = pack_bang_inst(OP_SYNC_IPU, ENG_ICU_CTRL, PREC_INT8, SPARSE_DENSE,
 000030                                              MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h78,
 000030                                              32'd0, 32'd0, 16'd0, 16'd0);
 000020             if (step == 2) begin
 000010               item.eng_done_valid[2] = 1'b1;
 000010               item.eng_done_tag[2]   = 8'h77;
                    end
 000060           end else if (step >= 5 && step <= 8) begin
                    // Issue OP_SYNC_CLUSTER: waits for cluster_sync_ack at step 8
 000040             item.inst_valid = 1'b1;
 000040             item.inst_word  = pack_bang_inst(OP_SYNC_CLUSTER, ENG_ICU_CTRL, PREC_INT8, SPARSE_DENSE,
 000040                                              MEM_SPACE_NRAM, MEM_SPACE_NRAM, 4'b0000, 8'h79,
 000040                                              32'd0, 32'd0, 16'd0, 16'd0);
 000030             if (step == 8) begin
 000010               item.cluster_sync_ack = 1'b1;
                    end
                  end
                end
                // Phase 3 (450..1199): Constrained-Random 5-Queue Instruction Stream & Completion Stress
 000750         else if (cyc >= 450) begin
 000750           int blk  = (cyc - 450) / 6;
 000750           int step = (cyc - 450) % 6;
 000750           int q    = blk % 5;
 000750           mlu_engine_e eng_v = mlu_engine_e'(q + 1);
 000750           mlu_mem_space_e s_sp = mlu_mem_space_e'(blk % 3);
 000750           mlu_mem_space_e d_sp = mlu_mem_space_e'((blk + 1) % 3);
 000750           logic [7:0] tag_v = 8'(8'h80 + (blk % 64));
 000750           logic [5:0] reg_d = 6'(blk & 6'h3F);
 000750           logic [5:0] reg_s = 6'((blk + 17) & 6'h3F);
        
 000125           if (step == 0) begin
 000125             item.inst_valid = 1'b1;
 000125             item.inst_word  = pack_bang_inst(OP_BANG_MATMUL, eng_v, mlu_prec_e'(r0[11:9]),
 000125                                              mlu_sparse_mode_e'(r0[13:12]), s_sp, d_sp,
 000125                                              4'b0000, tag_v,
 000125                                              {16'd0, reg_d, 10'd0},
 000125                                              {16'd0, reg_s, 10'd0},
 000125                                              {reg_s, 10'd0}, 16'd1);
 000125           end else if (step == 1) begin
                    // Deliberate hazard + dep_mask probe while tag_v is in-flight
 000125             item.inst_valid = 1'b1;
 000125             item.inst_word  = pack_bang_inst(OP_BANG_VADD, eng_v, PREC_FP16, SPARSE_DENSE,
 000125                                              d_sp, s_sp, 4'(1 << (q % 4)), 8'(tag_v + 8'd1),
 000125                                              {16'd0, reg_d, 10'd0},
 000125                                              {16'd0, reg_d, 10'd0},
 000125                                              16'd0, 16'd1);
 000125           end else if (step == 2) begin
                    // Retire tag_v
 000125             item.eng_done_valid[q] = 1'b1;
 000125             item.eng_done_tag[q]   = tag_v;
 000125           end else if (step == 3) begin
                    // Re-issue dependent instruction after hazard clears
 000125             item.inst_valid = 1'b1;
 000125             item.inst_word  = pack_bang_inst(OP_BANG_VADD, eng_v, PREC_FP16, SPARSE_DENSE,
 000125                                              d_sp, s_sp, 4'b0000, 8'(tag_v + 8'd1),
 000125                                              {16'd0, reg_d, 10'd0},
 000125                                              {16'd0, reg_s, 10'd0},
 000125                                              16'd0, 16'd1);
 000125           end else if (step == 4) begin
 000125             item.eng_done_valid[q] = 1'b1;
 000125             item.eng_done_tag[q]   = 8'(tag_v + 8'd1);
                  end
                end
        
 001200         finish_item(item);
              end
            endtask
          endclass : mlu_icu_sequence
          // ---------------------------------------------------------------------------
          // 3. UVM Driver: mlu_icu_driver
          // ---------------------------------------------------------------------------
          class mlu_icu_driver extends uvm_driver #(mlu_icu_seq_item);
%000001     `uvm_component_utils(mlu_icu_driver)
        
            virtual mlu_bang_icu_pmu_if vif;
%000001     int unsigned driven = 0;
        
%000001     function new(string name = "mlu_icu_driver", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       if (!uvm_config_db#(virtual mlu_bang_icu_pmu_if)::get(this, "", "vif", vif)) begin
%000000         `uvm_fatal("NO_VIF", "Virtual interface mlu_bang_icu_pmu_if missing in mlu_icu_driver")
              end
            endfunction
        
%000000     task run_phase(uvm_phase phase);
%000000       mlu_icu_seq_item item;
%000000       vif.rst_n       = 1'b0;
%000000       vif.cycle_valid = 1'b0;
%000000       dpi_icu_reset();
%000003       repeat (3) @(negedge vif.clk);
        
 001200       forever begin
 001200         seq_item_port.get_next_item(item);
 001200         vif.rst_n              = 1'b1;
 001200         vif.cycle_id           = item.cycle_id;
 001200         vif.inst_valid_i       = item.inst_valid;
 001200         vif.inst_i             = item.inst_word;
 001200         vif.eng_cmd_ready_i    = item.eng_cmd_ready;
 001200         vif.cluster_sync_ack_i = item.cluster_sync_ack;
 001200         vif.eng_done_valid_i   = item.eng_done_valid;
 001200         vif.eng_done_tag_i     = item.eng_done_tag;
        
 001200         vif.cycle_valid = 1'b1;
 001200         @(posedge vif.clk);
 001200         #1ns;
 001200         vif.cycle_valid = 1'b0;
 001200         driven++;
 001200         @(negedge vif.clk);
 001200         seq_item_port.item_done();
              end
            endtask
          endclass : mlu_icu_driver
        
          // ---------------------------------------------------------------------------
          // 4. UVM Monitor: mlu_icu_monitor (with Functional Covergroup)
          // ---------------------------------------------------------------------------
          class mlu_icu_monitor extends uvm_monitor;
%000001     `uvm_component_utils(mlu_icu_monitor)
        
            virtual mlu_bang_icu_pmu_if vif;
            uvm_analysis_port #(mlu_icu_seq_item) ap;
%000001     int unsigned seen = 0;
        
            covergroup mlu_icu_cg with function sample(
              bit [2:0] eng_id,
              bit       haz_stall,
              bit       sync_req,
              bit       clk_gated,
              bit       sram_sleep
            );
              option.per_instance = 1;
              cp_eng: coverpoint eng_id {
 000738         bins e_ctrl = {3'd0};
 000089         bins e_tfu  = {3'd1};
 000092         bins e_vfu  = {3'd2};
 000102         bins e_mfu  = {3'd3};
 000091         bins e_mpu  = {3'd4};
 000088         bins e_llm  = {3'd5};
              }
 000989       cp_haz: coverpoint haz_stall { bins b0 = {0}; bins b1 = {1}; }
 001160       cp_sync: coverpoint sync_req { bins b0 = {0}; bins b1 = {1}; }
~001196       cp_cg: coverpoint clk_gated { bins b0 = {0}; bins b1 = {1}; }
 001022       cp_slp: coverpoint sram_sleep { bins b0 = {0}; bins b1 = {1}; }
            endgroup
        
%000001     function new(string name = "mlu_icu_monitor", uvm_component parent = null);
%000001       super.new(name, parent);
%000001       ap = new("ap", this);
%000001       mlu_icu_cg = new();
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       if (!uvm_config_db#(virtual mlu_bang_icu_pmu_if)::get(this, "", "vif", vif)) begin
%000000         `uvm_fatal("NO_VIF", "Virtual interface mlu_bang_icu_pmu_if missing in mlu_icu_monitor")
              end
            endfunction
%000000     task run_phase(uvm_phase phase);
 001202       forever begin
 001202         @(negedge vif.clk);
 001202         #1ns;
~001200         if (vif.rst_n && vif.cycle_valid) begin
 001200           mlu_icu_seq_item item = mlu_icu_seq_item::type_id::create("obs_item");
 001200           item.cycle_id               = vif.cycle_id;
 001200           item.inst_valid             = vif.inst_valid_i;
 001200           item.inst_word              = vif.inst_i;
 001200           item.eng_cmd_ready          = vif.eng_cmd_ready_i;
 001200           item.cluster_sync_ack       = vif.cluster_sync_ack_i;
 001200           item.eng_done_valid         = vif.eng_done_valid_i;
 001200           item.eng_done_tag           = vif.eng_done_tag_i;
        
 001200           item.act_inst_ready         = vif.inst_ready_o;
 001200           item.act_eng_cmd_valid      = vif.eng_cmd_valid_o;
 001200           item.act_icu_dispatch_mask  = vif.icu_dispatch_mask_o;
 001200           item.act_cluster_sync_req   = vif.cluster_sync_req_o;
 001200           item.act_queue_busy         = vif.queue_busy_o;
 001200           item.act_hazard_stall       = vif.hazard_stall_o;
 001200           item.act_inst_retired_cnt   = vif.inst_retired_cnt_o;
 001200           item.act_hazard_stall_cnt   = vif.hazard_stall_cnt_o;
        
 001200           item.act_eng_clk_en         = vif.eng_clk_en_o;
 001200           item.act_sram_slp           = vif.sram_slp_o;
 001200           item.act_sram_dslp          = vif.sram_dslp_o;
 001200           item.act_sram_wake_ready    = vif.sram_wake_ready_o;
 001200           item.act_gated_saved_cycles = vif.gated_saved_cycles_o;
 001200           item.act_sram_sleep_cycles  = vif.sram_sleep_cycles_o;
        
 001200           mlu_icu_cg.sample(
 001200             vif.inst_i[121:119],
 001200             vif.hazard_stall_o,
 001200             vif.cluster_sync_req_o,
 001200             (vif.eng_clk_en_o != 5'b11111),
 001200             (|(vif.sram_slp_o | vif.sram_dslp_o))
                  );
        
 001200           seen++;
 001200           ap.write(item);
                end
              end
            endtask
          endclass : mlu_icu_monitor
        
          // ---------------------------------------------------------------------------
          // 5. UVM Agent & DPI-C Scoreboard
          // ---------------------------------------------------------------------------
          class mlu_icu_agent extends uvm_agent;
%000001     `uvm_component_utils(mlu_icu_agent)
            mlu_icu_sequencer sequencer;
            mlu_icu_driver    driver;
            mlu_icu_monitor   monitor;
%000001     function new(string name = "mlu_icu_agent", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       sequencer = mlu_icu_sequencer::type_id::create("sequencer", this);
%000001       driver    = mlu_icu_driver::type_id::create("driver", this);
%000001       monitor   = mlu_icu_monitor::type_id::create("monitor", this);
            endfunction
%000001     function void connect_phase(uvm_phase phase);
%000001       super.connect_phase(phase);
%000001       driver.seq_item_port.connect(sequencer.seq_item_export);
            endfunction
          endclass : mlu_icu_agent
        
          class mlu_icu_scoreboard extends uvm_scoreboard;
%000001     `uvm_component_utils(mlu_icu_scoreboard)
        
            uvm_analysis_imp #(mlu_icu_seq_item, mlu_icu_scoreboard) analysis_export;
        
%000001     int unsigned checked_cycles     = 0;
%000001     int unsigned mismatches         = 0;
%000001     int unsigned hazard_stalls_seen = 0;
%000001     int unsigned cluster_syncs_seen = 0;
%000001     int unsigned zero_cyc_wakeups   = 0;
        
%000001     function new(string name = "mlu_icu_scoreboard", uvm_component parent = null);
%000001       super.new(name, parent);
%000001       analysis_export = new("analysis_export", this);
            endfunction
 001200     function void write(mlu_icu_seq_item item);
 001200       longint unsigned packed_tags = {
 001200         24'd0,
 001200         item.eng_done_tag[4], item.eng_done_tag[3],
 001200         item.eng_done_tag[2], item.eng_done_tag[1], item.eng_done_tag[0]
              };
        
 001200       dpi_icu_eval_and_step(
 001200         {31'd0, item.inst_valid},
 001200         item.inst_word[127:64],
 001200         item.inst_word[63:0],
 001200         {27'd0, item.eng_cmd_ready},
 001200         {31'd0, item.cluster_sync_ack},
 001200         {27'd0, item.eng_done_valid},
 001200         packed_tags
              );
        
 001200       checked_cycles++;
 000989       if (item.act_hazard_stall) hazard_stalls_seen++;
 001190       if (item.act_cluster_sync_req && item.cluster_sync_ack) cluster_syncs_seen++;
 000738       if ((item.act_icu_dispatch_mask != 5'b00000) &&
 000462           ((item.act_eng_clk_en & item.act_icu_dispatch_mask) == item.act_icu_dispatch_mask)) begin
 000462         zero_cyc_wakeups++;
              end
        
~001200       if (item.act_inst_ready         !== dpi_icu_exp_inst_ready()[0]        ||
                  item.act_eng_cmd_valid      !== dpi_icu_exp_eng_cmd_valid()[4:0]   ||
                  item.act_icu_dispatch_mask  !== dpi_icu_exp_dispatch_mask()[4:0]   ||
                  item.act_cluster_sync_req   !== dpi_icu_exp_cluster_sync_req()[0]  ||
                  item.act_queue_busy         !== dpi_icu_exp_queue_busy()[4:0]      ||
                  item.act_hazard_stall       !== dpi_icu_exp_hazard_stall()[0]      ||
                  item.act_inst_retired_cnt   !== dpi_icu_exp_inst_retired_cnt()     ||
                  item.act_hazard_stall_cnt   !== dpi_icu_exp_hazard_stall_cnt()     ||
                  item.act_eng_clk_en         !== dpi_pmu_exp_eng_clk_en()[4:0]      ||
                  item.act_sram_slp           !== dpi_pmu_exp_sram_slp()[2:0]        ||
                  item.act_sram_dslp          !== dpi_pmu_exp_sram_dslp()[2:0]       ||
                  item.act_sram_wake_ready    !== dpi_pmu_exp_sram_wake_ready()[2:0] ||
                  item.act_gated_saved_cycles !== dpi_pmu_exp_gated_saved_cycles()   ||
%000000           item.act_sram_sleep_cycles  !== dpi_pmu_exp_sram_sleep_cycles()) begin
                `uvm_error("ICU_PMU_MISMATCH", $sformatf(
                  "Cyc %0d: rdy=%b(%b) cmd=%b(%b) busy=%b(%b) haz=%b(%b) ret=%0d(%0d) clk=%b(%b) slp=%b(%b)",
                  item.cycle_id,
                  item.act_inst_ready, dpi_icu_exp_inst_ready()[0],
                  item.act_eng_cmd_valid, dpi_icu_exp_eng_cmd_valid()[4:0],
                  item.act_queue_busy, dpi_icu_exp_queue_busy()[4:0],
                  item.act_hazard_stall, dpi_icu_exp_hazard_stall()[0],
                  item.act_inst_retired_cnt, dpi_icu_exp_inst_retired_cnt(),
                  item.act_eng_clk_en, dpi_pmu_exp_eng_clk_en()[4:0],
%000000           item.act_sram_slp, dpi_pmu_exp_sram_slp()[2:0]))
%000000         mismatches++;
              end
            endfunction
          endclass : mlu_icu_scoreboard
        
          // ---------------------------------------------------------------------------
          // 6. UVM Environment & Test
          // ---------------------------------------------------------------------------
          class mlu_icu_env extends uvm_env;
%000001     `uvm_component_utils(mlu_icu_env)
            mlu_icu_agent      agent;
            mlu_icu_scoreboard scoreboard;
%000001     function new(string name = "mlu_icu_env", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       agent      = mlu_icu_agent::type_id::create("agent", this);
%000001       scoreboard = mlu_icu_scoreboard::type_id::create("scoreboard", this);
            endfunction
%000001     function void connect_phase(uvm_phase phase);
%000001       super.connect_phase(phase);
%000001       agent.monitor.ap.connect(scoreboard.analysis_export);
            endfunction
          endclass : mlu_icu_env
        
          class mlu_bang_icu_pmu_test extends uvm_test;
%000002     `uvm_component_utils(mlu_bang_icu_pmu_test)
            mlu_icu_env env;
%000001     function new(string name = "mlu_bang_icu_pmu_test", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       env = mlu_icu_env::type_id::create("env", this);
            endfunction
%000001     task run_phase(uvm_phase phase);
%000001       mlu_icu_sequence seq = mlu_icu_sequence::type_id::create("seq");
%000001       phase.raise_objection(this);
%000001       seq.start(env.agent.sequencer);
%000001       phase.drop_objection(this);
            endtask
%000001     function void report_phase(uvm_phase phase);
%000001       real func_cov = env.agent.monitor.mlu_icu_cg.get_inst_coverage();
              bit pass_gate = (env.agent.driver.driven == 1200) &&
                              (env.scoreboard.checked_cycles == 1200) &&
                              (env.scoreboard.mismatches == 0) &&
                              (env.scoreboard.hazard_stalls_seen >= 50) &&
%000001                       (env.scoreboard.cluster_syncs_seen >= 5) &&
                              (env.scoreboard.zero_cyc_wakeups >= 100);
%000001       super.report_phase(phase);
%000001       dpi_icu_set_status(pass_gate ? 0 : 1);
%000001       if (!pass_gate) begin
                `uvm_fatal("UVM_ICU_PMU_FAIL", $sformatf(
                  "Suite 2 gate failed: mismatches=%0d haz=%0d syncs=%0d wake=%0d cov=%0.2f%% (eng=%0.1f haz=%0.1f sync=%0.1f cg=%0.1f slp=%0.1f)",
                  env.scoreboard.mismatches, env.scoreboard.hazard_stalls_seen,
                  env.scoreboard.cluster_syncs_seen, env.scoreboard.zero_cyc_wakeups, func_cov,
                  env.agent.monitor.mlu_icu_cg.cp_eng.get_inst_coverage(),
                  env.agent.monitor.mlu_icu_cg.cp_haz.get_inst_coverage(),
                  env.agent.monitor.mlu_icu_cg.cp_sync.get_inst_coverage(),
                  env.agent.monitor.mlu_icu_cg.cp_cg.get_inst_coverage(),
%000000           env.agent.monitor.mlu_icu_cg.cp_slp.get_inst_coverage()))
%000001       end else begin
                `uvm_info("UVM_ICU_PMU_PASS", $sformatf(
                  "SUITE 2 PASS: cycles=%0d dpi_calls=%0d hazard_stalls=%0d cluster_syncs=%0d wakeups=%0d retired=%0d gated_saved=%0d cov=%0.2f%%",
                  env.scoreboard.checked_cycles, dpi_icu_get_calls(),
                  env.scoreboard.hazard_stalls_seen, env.scoreboard.cluster_syncs_seen,
                  env.scoreboard.zero_cyc_wakeups, dpi_icu_exp_inst_retired_cnt(),
%000001           dpi_pmu_exp_gated_saved_cycles(), func_cov), UVM_LOW)
              end
            endfunction
          endclass : mlu_bang_icu_pmu_test
        
        endpackage : mlu_bang_icu_pmu_uvm_pkg
        
        `endif // MLU_BANG_ICU_PMU_UVM_PKG_SV
        
