//      // verilator_coverage annotation
        // =============================================================================
        // File: uvm_tb/uvm_vfu_llm_ops/mlu_vfu_uvm_pkg.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: Accellera IEEE 1800.2-2020 UVM Verification Package for Suite 4:
        //              mlu_vfu_sfu_pipe (uvm_sequence_item, uvm_sequence, uvm_sequencer,
        //              uvm_driver, uvm_monitor, uvm_agent, uvm_scoreboard, uvm_env, uvm_test).
        // =============================================================================
        `ifndef MLU_VFU_UVM_PKG_SV
        `define MLU_VFU_UVM_PKG_SV
        
        `timescale 1ns/1ps
        `include "uvm_macros.svh"
        `include "mlu_pkg.sv"
        
        package mlu_vfu_uvm_pkg;
          import uvm_pkg::*;
          import mlu_pkg::*;
        
          // ---------------------------------------------------------------------------
          // DPI-C Bit-Exact Reference Model Imports
          // ---------------------------------------------------------------------------
          import "DPI-C" function void         dpi_vfu_set_status(int status);
          import "DPI-C" function int          dpi_vfu_get_status();
          import "DPI-C" function int unsigned dpi_vfu_get_calls();
          import "DPI-C" function void         dpi_vfu_ref_reset();
          import "DPI-C" function void         dpi_vfu_ref_exec(
            int unsigned opcode,
            int unsigned prec,
            int unsigned tag_id,
            int unsigned cont_mode,
            longint unsigned va_lo,  longint unsigned va_hi,
            longint unsigned vb_lo,  longint unsigned vb_hi,
            longint unsigned lut_lo, longint unsigned lut_hi
          );
          import "DPI-C" function longint unsigned dpi_vfu_exp_vec_lo();
          import "DPI-C" function longint unsigned dpi_vfu_exp_vec_hi();
          import "DPI-C" function int unsigned     dpi_vfu_exp_softmax_sum();
          import "DPI-C" function int unsigned     dpi_vfu_exp_softmax_max();
          import "DPI-C" function int unsigned     dpi_vfu_exp_absmax();
          import "DPI-C" function int unsigned     dpi_vfu_exp_min_val();
          import "DPI-C" function int unsigned     dpi_vfu_exp_max_val();
          import "DPI-C" function int unsigned     dpi_vfu_exp_dyn_scale();
          import "DPI-C" function int unsigned     dpi_vfu_exp_tag();
        
          // ---------------------------------------------------------------------------
          // 1. UVM Sequence Item: vfu_seq_item
          // ---------------------------------------------------------------------------
%000000   class vfu_seq_item extends uvm_sequence_item;
~000560     `uvm_object_utils(vfu_seq_item)
        
            int unsigned   txn_id;
            mlu_opcode_e   opcode;
            mlu_prec_e     prec;
            bit [7:0]      tag_id;
            bit            cont_mode;
            logic [127:0]  vec_a;
            logic [127:0]  vec_b;
            logic [127:0]  cos_sin_lut;
        
            // Sampled DUT Outputs
            logic [127:0]  act_vec_out;
            logic [31:0]   act_softmax_sum;
            logic [15:0]   act_softmax_max;
            logic [15:0]   act_absmax;
            logic [15:0]   act_min_val;
            logic [15:0]   act_max_val;
            logic [15:0]   act_dyn_scale;
            logic [7:0]    act_done_tag;
        
~001120     function new(string name = "vfu_seq_item");
 001120       super.new(name);
            endfunction
          endclass : vfu_seq_item
        
          // ---------------------------------------------------------------------------
          // 2. UVM Sequence: vfu_sequence (Directed + Constrained-Random across 7 Ops)
          // ---------------------------------------------------------------------------
          class vfu_sequence extends uvm_sequence #(vfu_seq_item);
%000001     `uvm_object_utils(vfu_sequence)
        
%000001     int unsigned     num_txns   = 560;
%000001     longint unsigned prng_state = 64'hC0DE_5906_90CA_FE11;
        
%000001     function new(string name = "vfu_sequence");
%000001       super.new(name);
            endfunction
        
 003052     function longint unsigned next_rand64();
 003052       prng_state ^= (prng_state << 13);
 003052       prng_state ^= (prng_state >> 7);
 003052       prng_state ^= (prng_state << 17);
 003052       return prng_state;
            endfunction
        
%000001     task body();
%000001       mlu_opcode_e ops[7] = '{
%000001         OP_BANG_VADD, OP_BANG_VMUL, OP_BANG_SOFTMAX,
%000001         OP_BANG_ROPE, OP_BANG_RMSNORM, OP_BANG_SWIGLU, OP_BANG_QUANT_STAT
              };
        
~000560       for (int unsigned t = 0; t < num_txns; t++) begin
 000560         vfu_seq_item item = vfu_seq_item::type_id::create("item");
 000560         longint unsigned r0 = next_rand64();
 000560         longint unsigned r1 = next_rand64();
 000560         longint unsigned r2 = next_rand64();
 000560         longint unsigned r3 = next_rand64();
        
 000560         start_item(item);
 000560         item.txn_id    = t;
 000560         item.opcode    = ops[t % 7];
 000560         item.tag_id    = 8'(t & 8'hFF);
 000560         item.prec      = ((t / 7) % 2 == 0) ? PREC_INT8 : PREC_INT4;
 000560         item.cont_mode = (item.opcode == OP_BANG_SOFTMAX) ? bit'((t / 7) % 2) : 1'b0;
        
                // Directed corner cases for first 126 transactions, then constrained-random
 000014         if (t < 14) begin
                  // Saturation & boundary test vectors
 000014           item.vec_a       = {16'h7FFF, 16'h8000, 16'h0100, 16'hFF00, 16'h0200, 16'hFE00, 16'h0000, 16'h0080};
 000014           item.vec_b       = {16'h7FFF, 16'h8000, 16'h0100, 16'h0100, 16'h0180, 16'h0180, 16'h0000, 16'h0100};
 000014           item.cos_sin_lut = {16'h0080, 16'h00DD, 16'h00DD, 16'h0080, 16'hFF00, 16'h0000, 16'h0000, 16'h0100};
 000084         end else if (t < 98) begin
                  // Sweep all 12 Q8.8 variance buckets of rsqrt_lut_nr_q88:
                  // v_safe = ((x*x) >> 8) + 1 across [<16, <64, <128, <192, <320, <512, <768, <1280, <2560, <5120, <10240, >=10240]
 000084           logic [15:0] rms_lut_x[12] = '{
 000084             16'd16,  16'd96,  16'd160, 16'd200, 16'd256,  16'd320,
 000084             16'd400, 16'd512, 16'd700, 16'd1024, 16'd1400, 16'd2048
                  };
 000084           logic [15:0] vx = rms_lut_x[(t - 14) / 7];
 000084           logic [15:0] nx = ~vx + 16'd1;
 000084           item.vec_a       = {vx, nx, vx, nx, vx, nx, vx, nx};
 000084           item.vec_b       = {16'h0100, 16'h0120, 16'h00E0, 16'h0140, 16'h00C0, 16'h0100, 16'h0080, 16'h0200};
 000084           item.cos_sin_lut = {16'h00B5, 16'h00B5, 16'h0080, 16'h00DD, 16'h00DD, 16'h0080, 16'h0100, 16'h0000};
 000406         end else if (t < 154) begin
                  // Sweep variance & PWL exp/sigmoid segments across Q8.8 scales
 000056           int unsigned scale_sh = (t / 7) % 8;
 000056           item.vec_a       = {(r0 << scale_sh), (r1 >> scale_sh)};
 000056           item.vec_b       = {16'h0100, 16'h0120, 16'h00E0, 16'h0140, 16'h00C0, 16'h0100, 16'h0080, 16'h0200};
 000056           item.cos_sin_lut = {16'h00B5, 16'h00B5, 16'h0080, 16'h00DD, 16'h00DD, 16'h0080, 16'h0100, 16'h0000};
 000406         end else begin
 000406           item.vec_a       = {r1, r0};
 000406           item.vec_b       = {r3, r2};
 000406           item.cos_sin_lut = {next_rand64(), next_rand64()};
                end
 000560         finish_item(item);
              end
            endtask
          endclass : vfu_sequence
        
          // ---------------------------------------------------------------------------
          // 3. UVM Sequencer: vfu_sequencer
          // ---------------------------------------------------------------------------
          class vfu_sequencer extends uvm_sequencer #(vfu_seq_item);
%000001     `uvm_component_utils(vfu_sequencer)
%000001     function new(string name = "vfu_sequencer", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
          endclass : vfu_sequencer
        
          // ---------------------------------------------------------------------------
          // 4. UVM Driver: vfu_driver
          // ---------------------------------------------------------------------------
          class vfu_driver extends uvm_driver #(vfu_seq_item);
%000001     `uvm_component_utils(vfu_driver)
        
            virtual mlu_vfu_if vif;
%000001     int unsigned driven = 0;
        
%000001     function new(string name = "vfu_driver", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       if (!uvm_config_db#(virtual mlu_vfu_if)::get(this, "", "vif", vif))
%000000         `uvm_fatal("NO_VIF", "Virtual interface mlu_vfu_if missing in vfu_driver")
            endfunction
        
%000000     task run_phase(uvm_phase phase);
%000000       vfu_seq_item item;
%000000       mlu_inst_t   inst;
        
%000000       vif.rst_ni        = 1'b0;
%000000       vif.cmd_valid_i   = 1'b0;
%000000       vif.cmd_inst_i    = '0;
%000000       vif.vec_a_i       = '0;
%000000       vif.vec_b_i       = '0;
%000000       vif.cos_sin_lut_i = '0;
%000004       repeat (4) @(negedge vif.clk);
%000000       vif.rst_ni = 1'b1;
%000000       @(negedge vif.clk);
        
 000560       forever begin
 000560         seq_item_port.get_next_item(item);
%000000         while (!vif.cmd_ready_o) @(negedge vif.clk);
        
 000560         inst              = '0;
 000560         inst.opcode       = item.opcode;
 000560         inst.engine       = ENG_VFU_VEC;
 000560         inst.prec         = item.prec;
 000560         inst.tag_id       = item.tag_id;
 000560         inst.src1_or_strd = {15'd0, item.cont_mode};
        
 000560         vif.cmd_valid_i     = 1'b1;
 000560         vif.cmd_inst_i      = inst;
 000560         vif.vec_a_i         = item.vec_a;
 000560         vif.vec_b_i         = item.vec_b;
 000560         vif.cos_sin_lut_i   = item.cos_sin_lut;
 000560         vif.mon_cmd_inst    = inst;
 000560         vif.mon_vec_a       = item.vec_a;
 000560         vif.mon_vec_b       = item.vec_b;
 000560         vif.mon_cos_sin_lut = item.cos_sin_lut;
        
 000560         @(posedge vif.clk);
 000560         @(negedge vif.clk);
 000560         vif.cmd_valid_i = 1'b0;
        
 001120         while (!vif.done_valid_o) @(negedge vif.clk);
 000560         driven++;
 000560         seq_item_port.item_done();
              end
            endtask
          endclass : vfu_driver
        
          // ---------------------------------------------------------------------------
          // 5. UVM Monitor: vfu_monitor (with Functional Covergroup)
          // ---------------------------------------------------------------------------
          class vfu_monitor extends uvm_monitor;
%000001     `uvm_component_utils(vfu_monitor)
        
            virtual mlu_vfu_if vif;
            uvm_analysis_port #(vfu_seq_item) ap;
%000001     int unsigned seen = 0;
        
            covergroup vfu_cg with function sample(
              bit [5:0] op,
              bit       is_int4,
              bit       cont
            );
              option.per_instance = 1;
              cp_op: coverpoint op {
 000080         bins b_vadd       = {OP_BANG_VADD};
 000080         bins b_vmul       = {OP_BANG_VMUL};
 000080         bins b_softmax    = {OP_BANG_SOFTMAX};
 000080         bins b_rope       = {OP_BANG_ROPE};
 000080         bins b_rmsnorm    = {OP_BANG_RMSNORM};
 000080         bins b_swiglu     = {OP_BANG_SWIGLU};
 000080         bins b_quant_stat = {OP_BANG_QUANT_STAT};
              }
              cp_prec: coverpoint is_int4 {
 000280         bins p_int8 = {1'b0};
 000280         bins p_int4 = {1'b1};
              }
              cp_cont: coverpoint cont {
 000520         bins c_single = {1'b0};
 000040         bins c_multi  = {1'b1};
              }
            endgroup
        
%000001     function new(string name = "vfu_monitor", uvm_component parent = null);
%000001       super.new(name, parent);
%000001       ap     = new("ap", this);
%000001       vfu_cg = new();
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       if (!uvm_config_db#(virtual mlu_vfu_if)::get(this, "", "vif", vif))
%000000         `uvm_fatal("NO_VIF", "Virtual interface mlu_vfu_if missing in vfu_monitor")
            endfunction
        
%000000     task run_phase(uvm_phase phase);
 001685       forever begin
 001685         @(negedge vif.clk);
 001125         if (vif.rst_ni && vif.done_valid_o && vif.vec_out_valid_o) begin
 000560           vfu_seq_item item = vfu_seq_item::type_id::create("mon_item");
 000560           mlu_inst_t   inst = vif.mon_cmd_inst;
 000560           item.txn_id          = seen;
 000560           item.opcode          = inst.opcode;
 000560           item.prec            = inst.prec;
 000560           item.tag_id          = inst.tag_id;
 000560           item.cont_mode       = inst.src1_or_strd[0];
 000560           item.vec_a           = vif.mon_vec_a;
 000560           item.vec_b           = vif.mon_vec_b;
 000560           item.cos_sin_lut     = vif.mon_cos_sin_lut;
 000560           item.act_vec_out     = vif.vec_out_o;
 000560           item.act_softmax_sum = vif.softmax_sum_o;
 000560           item.act_softmax_max = vif.softmax_max_o;
 000560           item.act_absmax      = vif.absmax_o;
 000560           item.act_min_val     = vif.min_val_o;
 000560           item.act_max_val     = vif.max_val_o;
 000560           item.act_dyn_scale   = vif.dyn_scale_o;
 000560           item.act_done_tag    = vif.done_tag_o;
        
 000560           vfu_cg.sample(inst.opcode, (inst.prec == PREC_INT4), inst.src1_or_strd[0]);
 000560           seen++;
 000560           ap.write(item);
                end
              end
            endtask
          endclass : vfu_monitor
        
          // ---------------------------------------------------------------------------
          // 6. UVM Agent: vfu_agent
          // ---------------------------------------------------------------------------
          class vfu_agent extends uvm_agent;
%000001     `uvm_component_utils(vfu_agent)
        
            vfu_sequencer sequencer;
            vfu_driver    driver;
            vfu_monitor   monitor;
        
%000001     function new(string name = "vfu_agent", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       sequencer = vfu_sequencer::type_id::create("sequencer", this);
%000001       driver    = vfu_driver::type_id::create("driver", this);
%000001       monitor   = vfu_monitor::type_id::create("monitor", this);
            endfunction
        
%000001     function void connect_phase(uvm_phase phase);
%000001       super.connect_phase(phase);
%000001       driver.seq_item_port.connect(sequencer.seq_item_export);
            endfunction
          endclass : vfu_agent
        
          // ---------------------------------------------------------------------------
          // 7. UVM Scoreboard: vfu_scoreboard (Bit-Exact DPI-C Reference Check)
          // ---------------------------------------------------------------------------
          class vfu_scoreboard extends uvm_scoreboard;
%000001     `uvm_component_utils(vfu_scoreboard)
        
            uvm_analysis_imp #(vfu_seq_item, vfu_scoreboard) analysis_export;
%000001     int unsigned checked_txns = 0;
%000001     int unsigned mismatches   = 0;
        
%000001     function new(string name = "vfu_scoreboard", uvm_component parent = null);
%000001       super.new(name, parent);
%000001       analysis_export = new("analysis_export", this);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       dpi_vfu_ref_reset();
            endfunction
        
 000560     function void write(vfu_seq_item item);
 000560       longint unsigned exp_lo, exp_hi;
 000560       logic [127:0]    exp_vec;
 000560       logic [31:0]     exp_s_sum;
 000560       logic [15:0]     exp_s_max, exp_absmax, exp_min, exp_max, exp_scale;
 000560       logic [7:0]      exp_tag;
        
 000560       dpi_vfu_ref_exec(
 000560         int'(item.opcode),
 000560         int'(item.prec),
 000560         int'(item.tag_id),
 000560         int'(item.cont_mode),
 000560         item.vec_a[63:0],       item.vec_a[127:64],
 000560         item.vec_b[63:0],       item.vec_b[127:64],
 000560         item.cos_sin_lut[63:0], item.cos_sin_lut[127:64]
              );
        
 000560       exp_lo     = dpi_vfu_exp_vec_lo();
 000560       exp_hi     = dpi_vfu_exp_vec_hi();
 000560       exp_vec    = {exp_hi, exp_lo};
 000560       exp_s_sum  = 32'(dpi_vfu_exp_softmax_sum());
 000560       exp_s_max  = 16'(dpi_vfu_exp_softmax_max());
 000560       exp_absmax = 16'(dpi_vfu_exp_absmax());
 000560       exp_min    = 16'(dpi_vfu_exp_min_val());
 000560       exp_max    = 16'(dpi_vfu_exp_max_val());
 000560       exp_scale  = 16'(dpi_vfu_exp_dyn_scale());
 000560       exp_tag    = 8'(dpi_vfu_exp_tag());
        
~000560       if (item.act_vec_out     !== exp_vec    ||
                  item.act_softmax_sum !== exp_s_sum  ||
                  item.act_softmax_max !== exp_s_max  ||
                  item.act_absmax      !== exp_absmax ||
                  item.act_min_val     !== exp_min    ||
                  item.act_max_val     !== exp_max    ||
                  item.act_dyn_scale   !== exp_scale  ||
%000000           item.act_done_tag    !== exp_tag) begin
%000000         mismatches++;
                `uvm_error("VFU_MISMATCH", $sformatf(
                  "txn=%0d op=%02x vec_act=%032x vec_exp=%032x smax=%04x/%04x ssum=%08x/%08x absmax=%04x/%04x scale=%04x/%04x tag=%02x/%02x",
                  item.txn_id, item.opcode, item.act_vec_out, exp_vec,
                  item.act_softmax_max, exp_s_max, item.act_softmax_sum, exp_s_sum,
                  item.act_absmax, exp_absmax, item.act_dyn_scale, exp_scale,
%000000           item.act_done_tag, exp_tag))
              end
 000560       checked_txns++;
            endfunction
          endclass : vfu_scoreboard
        
          // ---------------------------------------------------------------------------
          // 8. UVM Environment: vfu_env
          // ---------------------------------------------------------------------------
          class vfu_env extends uvm_env;
%000001     `uvm_component_utils(vfu_env)
        
            vfu_agent      agent;
            vfu_scoreboard scoreboard;
        
%000001     function new(string name = "vfu_env", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       agent      = vfu_agent::type_id::create("agent", this);
%000001       scoreboard = vfu_scoreboard::type_id::create("scoreboard", this);
            endfunction
        
%000001     function void connect_phase(uvm_phase phase);
%000001       super.connect_phase(phase);
%000001       agent.monitor.ap.connect(scoreboard.analysis_export);
            endfunction
          endclass : vfu_env
        
          // ---------------------------------------------------------------------------
          // 9. UVM Test: vfu_llm_ops_test
          // ---------------------------------------------------------------------------
          class vfu_llm_ops_test extends uvm_test;
%000002     `uvm_component_utils(vfu_llm_ops_test)
        
            vfu_env env;
        
%000001     function new(string name = "vfu_llm_ops_test", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       env = vfu_env::type_id::create("env", this);
            endfunction
        
%000001     task run_phase(uvm_phase phase);
%000001       vfu_sequence seq = vfu_sequence::type_id::create("seq");
%000001       phase.raise_objection(this);
%000001       seq.start(env.agent.sequencer);
%000001       phase.drop_objection(this);
            endtask
        
%000001     function void report_phase(uvm_phase phase);
%000001       int unsigned dpi_calls = dpi_vfu_get_calls();
%000001       real         func_cov  = env.agent.monitor.vfu_cg.get_inst_coverage();
              bit          pass_gate = (env.agent.driver.driven == 560) &&
                                       (env.scoreboard.checked_txns == 560) &&
                                       (dpi_calls == 560) &&
%000001                                (env.scoreboard.mismatches == 0) &&
                                       (func_cov == 100.0);
%000001       super.report_phase(phase);
%000001       dpi_vfu_set_status(pass_gate ? 0 : 1);
%000001       if (!pass_gate) begin
                `uvm_fatal("UVM_VFU_FAIL", $sformatf(
                  "VFU UVM failed: driven=%0d checked=%0d mismatches=%0d cov=%0.2f%%",
                  env.agent.driver.driven, env.scoreboard.checked_txns,
%000000           env.scoreboard.mismatches, func_cov))
%000001       end else begin
                `uvm_info("UVM_VFU_PASS", $sformatf(
                  "PASS: %0d VFU/LLM transactions verified bit-exact via DPI-C, 0 mismatches, %0.2f%% functional coverage",
%000001           env.scoreboard.checked_txns, func_cov), UVM_LOW)
              end
            endfunction
          endclass : vfu_llm_ops_test
        
        endpackage : mlu_vfu_uvm_pkg
        
        `endif // MLU_VFU_UVM_PKG_SV
        
