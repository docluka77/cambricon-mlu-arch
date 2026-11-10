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
  class vfu_seq_item extends uvm_sequence_item;
    `uvm_object_utils(vfu_seq_item)

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

    function new(string name = "vfu_seq_item");
      super.new(name);
    endfunction
  endclass : vfu_seq_item

  // ---------------------------------------------------------------------------
  // 2. UVM Sequence: vfu_sequence (Directed + Constrained-Random across 7 Ops)
  // ---------------------------------------------------------------------------
  class vfu_sequence extends uvm_sequence #(vfu_seq_item);
    `uvm_object_utils(vfu_sequence)

    int unsigned     num_txns   = 560;
    longint unsigned prng_state = 64'hC0DE_5906_90CA_FE11;

    function new(string name = "vfu_sequence");
      super.new(name);
    endfunction

    function longint unsigned next_rand64();
      prng_state ^= (prng_state << 13);
      prng_state ^= (prng_state >> 7);
      prng_state ^= (prng_state << 17);
      return prng_state;
    endfunction

    task body();
      mlu_opcode_e ops[7] = '{
        OP_BANG_VADD, OP_BANG_VMUL, OP_BANG_SOFTMAX,
        OP_BANG_ROPE, OP_BANG_RMSNORM, OP_BANG_SWIGLU, OP_BANG_QUANT_STAT
      };

      for (int unsigned t = 0; t < num_txns; t++) begin
        vfu_seq_item item = vfu_seq_item::type_id::create("item");
        longint unsigned r0 = next_rand64();
        longint unsigned r1 = next_rand64();
        longint unsigned r2 = next_rand64();
        longint unsigned r3 = next_rand64();

        start_item(item);
        item.txn_id    = t;
        item.opcode    = ops[t % 7];
        item.tag_id    = 8'(t & 8'hFF);
        item.prec      = ((t / 7) % 2 == 0) ? PREC_INT8 : PREC_INT4;
        item.cont_mode = (item.opcode == OP_BANG_SOFTMAX) ? bit'((t / 7) % 2) : 1'b0;

        // Directed corner cases for first 70 transactions, then constrained-random
        if (t < 14) begin
          // Saturation & boundary test vectors
          item.vec_a       = {16'h7FFF, 16'h8000, 16'h0100, 16'hFF00, 16'h0200, 16'hFE00, 16'h0000, 16'h0080};
          item.vec_b       = {16'h7FFF, 16'h8000, 16'h0100, 16'h0100, 16'h0180, 16'h0180, 16'h0000, 16'h0100};
          item.cos_sin_lut = {16'h0080, 16'h00DD, 16'h00DD, 16'h0080, 16'hFF00, 16'h0000, 16'h0000, 16'h0100};
        end else if (t < 70) begin
          // Sweep variance & PWL exp/sigmoid segments across Q8.8 scales
          int unsigned scale_sh = (t / 7) % 8;
          item.vec_a       = {(r0 << scale_sh), (r1 >> scale_sh)};
          item.vec_b       = {16'h0100, 16'h0120, 16'h00E0, 16'h0140, 16'h00C0, 16'h0100, 16'h0080, 16'h0200};
          item.cos_sin_lut = {16'h00B5, 16'h00B5, 16'h0080, 16'h00DD, 16'h00DD, 16'h0080, 16'h0100, 16'h0000};
        end else begin
          item.vec_a       = {r1, r0};
          item.vec_b       = {r3, r2};
          item.cos_sin_lut = {next_rand64(), next_rand64()};
        end
        finish_item(item);
      end
    endtask
  endclass : vfu_sequence

  // ---------------------------------------------------------------------------
  // 3. UVM Sequencer: vfu_sequencer
  // ---------------------------------------------------------------------------
  class vfu_sequencer extends uvm_sequencer #(vfu_seq_item);
    `uvm_component_utils(vfu_sequencer)
    function new(string name = "vfu_sequencer", uvm_component parent = null);
      super.new(name, parent);
    endfunction
  endclass : vfu_sequencer

  // ---------------------------------------------------------------------------
  // 4. UVM Driver: vfu_driver
  // ---------------------------------------------------------------------------
  class vfu_driver extends uvm_driver #(vfu_seq_item);
    `uvm_component_utils(vfu_driver)

    virtual mlu_vfu_if vif;
    int unsigned driven = 0;

    function new(string name = "vfu_driver", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual mlu_vfu_if)::get(this, "", "vif", vif))
        `uvm_fatal("NO_VIF", "Virtual interface mlu_vfu_if missing in vfu_driver")
    endfunction

    task run_phase(uvm_phase phase);
      vfu_seq_item item;
      mlu_inst_t   inst;

      vif.rst_ni        = 1'b0;
      vif.cmd_valid_i   = 1'b0;
      vif.cmd_inst_i    = '0;
      vif.vec_a_i       = '0;
      vif.vec_b_i       = '0;
      vif.cos_sin_lut_i = '0;
      repeat (4) @(negedge vif.clk);
      vif.rst_ni = 1'b1;
      @(negedge vif.clk);

      forever begin
        seq_item_port.get_next_item(item);
        while (!vif.cmd_ready_o) @(negedge vif.clk);

        inst              = '0;
        inst.opcode       = item.opcode;
        inst.engine       = ENG_VFU_VEC;
        inst.prec         = item.prec;
        inst.tag_id       = item.tag_id;
        inst.src1_or_strd = {15'd0, item.cont_mode};

        vif.cmd_valid_i     = 1'b1;
        vif.cmd_inst_i      = inst;
        vif.vec_a_i         = item.vec_a;
        vif.vec_b_i         = item.vec_b;
        vif.cos_sin_lut_i   = item.cos_sin_lut;
        vif.mon_cmd_inst    = inst;
        vif.mon_vec_a       = item.vec_a;
        vif.mon_vec_b       = item.vec_b;
        vif.mon_cos_sin_lut = item.cos_sin_lut;

        @(posedge vif.clk);
        @(negedge vif.clk);
        vif.cmd_valid_i = 1'b0;

        while (!vif.done_valid_o) @(negedge vif.clk);
        driven++;
        seq_item_port.item_done();
      end
    endtask
  endclass : vfu_driver

  // ---------------------------------------------------------------------------
  // 5. UVM Monitor: vfu_monitor (with Functional Covergroup)
  // ---------------------------------------------------------------------------
  class vfu_monitor extends uvm_monitor;
    `uvm_component_utils(vfu_monitor)

    virtual mlu_vfu_if vif;
    uvm_analysis_port #(vfu_seq_item) ap;
    int unsigned seen = 0;

    covergroup vfu_cg with function sample(
      bit [5:0] op,
      bit       is_int4,
      bit       cont
    );
      option.per_instance = 1;
      cp_op: coverpoint op {
        bins b_vadd       = {OP_BANG_VADD};
        bins b_vmul       = {OP_BANG_VMUL};
        bins b_softmax    = {OP_BANG_SOFTMAX};
        bins b_rope       = {OP_BANG_ROPE};
        bins b_rmsnorm    = {OP_BANG_RMSNORM};
        bins b_swiglu     = {OP_BANG_SWIGLU};
        bins b_quant_stat = {OP_BANG_QUANT_STAT};
      }
      cp_prec: coverpoint is_int4 {
        bins p_int8 = {1'b0};
        bins p_int4 = {1'b1};
      }
      cp_cont: coverpoint cont {
        bins c_single = {1'b0};
        bins c_multi  = {1'b1};
      }
    endgroup

    function new(string name = "vfu_monitor", uvm_component parent = null);
      super.new(name, parent);
      ap     = new("ap", this);
      vfu_cg = new();
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual mlu_vfu_if)::get(this, "", "vif", vif))
        `uvm_fatal("NO_VIF", "Virtual interface mlu_vfu_if missing in vfu_monitor")
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        @(negedge vif.clk);
        if (vif.rst_ni && vif.done_valid_o && vif.vec_out_valid_o) begin
          vfu_seq_item item = vfu_seq_item::type_id::create("mon_item");
          mlu_inst_t   inst = vif.mon_cmd_inst;
          item.txn_id          = seen;
          item.opcode          = inst.opcode;
          item.prec            = inst.prec;
          item.tag_id          = inst.tag_id;
          item.cont_mode       = inst.src1_or_strd[0];
          item.vec_a           = vif.mon_vec_a;
          item.vec_b           = vif.mon_vec_b;
          item.cos_sin_lut     = vif.mon_cos_sin_lut;
          item.act_vec_out     = vif.vec_out_o;
          item.act_softmax_sum = vif.softmax_sum_o;
          item.act_softmax_max = vif.softmax_max_o;
          item.act_absmax      = vif.absmax_o;
          item.act_min_val     = vif.min_val_o;
          item.act_max_val     = vif.max_val_o;
          item.act_dyn_scale   = vif.dyn_scale_o;
          item.act_done_tag    = vif.done_tag_o;

          vfu_cg.sample(inst.opcode, (inst.prec == PREC_INT4), inst.src1_or_strd[0]);
          seen++;
          ap.write(item);
        end
      end
    endtask
  endclass : vfu_monitor

  // ---------------------------------------------------------------------------
  // 6. UVM Agent: vfu_agent
  // ---------------------------------------------------------------------------
  class vfu_agent extends uvm_agent;
    `uvm_component_utils(vfu_agent)

    vfu_sequencer sequencer;
    vfu_driver    driver;
    vfu_monitor   monitor;

    function new(string name = "vfu_agent", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      sequencer = vfu_sequencer::type_id::create("sequencer", this);
      driver    = vfu_driver::type_id::create("driver", this);
      monitor   = vfu_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
  endclass : vfu_agent

  // ---------------------------------------------------------------------------
  // 7. UVM Scoreboard: vfu_scoreboard (Bit-Exact DPI-C Reference Check)
  // ---------------------------------------------------------------------------
  class vfu_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(vfu_scoreboard)

    uvm_analysis_imp #(vfu_seq_item, vfu_scoreboard) analysis_export;
    int unsigned checked_txns = 0;
    int unsigned mismatches   = 0;

    function new(string name = "vfu_scoreboard", uvm_component parent = null);
      super.new(name, parent);
      analysis_export = new("analysis_export", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      dpi_vfu_ref_reset();
    endfunction

    function void write(vfu_seq_item item);
      longint unsigned exp_lo, exp_hi;
      logic [127:0]    exp_vec;
      logic [31:0]     exp_s_sum;
      logic [15:0]     exp_s_max, exp_absmax, exp_min, exp_max, exp_scale;
      logic [7:0]      exp_tag;

      dpi_vfu_ref_exec(
        int'(item.opcode),
        int'(item.prec),
        int'(item.tag_id),
        int'(item.cont_mode),
        item.vec_a[63:0],       item.vec_a[127:64],
        item.vec_b[63:0],       item.vec_b[127:64],
        item.cos_sin_lut[63:0], item.cos_sin_lut[127:64]
      );

      exp_lo     = dpi_vfu_exp_vec_lo();
      exp_hi     = dpi_vfu_exp_vec_hi();
      exp_vec    = {exp_hi, exp_lo};
      exp_s_sum  = 32'(dpi_vfu_exp_softmax_sum());
      exp_s_max  = 16'(dpi_vfu_exp_softmax_max());
      exp_absmax = 16'(dpi_vfu_exp_absmax());
      exp_min    = 16'(dpi_vfu_exp_min_val());
      exp_max    = 16'(dpi_vfu_exp_max_val());
      exp_scale  = 16'(dpi_vfu_exp_dyn_scale());
      exp_tag    = 8'(dpi_vfu_exp_tag());

      if (item.act_vec_out     !== exp_vec    ||
          item.act_softmax_sum !== exp_s_sum  ||
          item.act_softmax_max !== exp_s_max  ||
          item.act_absmax      !== exp_absmax ||
          item.act_min_val     !== exp_min    ||
          item.act_max_val     !== exp_max    ||
          item.act_dyn_scale   !== exp_scale  ||
          item.act_done_tag    !== exp_tag) begin
        mismatches++;
        `uvm_error("VFU_MISMATCH", $sformatf(
          "txn=%0d op=%02x vec_act=%032x vec_exp=%032x smax=%04x/%04x ssum=%08x/%08x absmax=%04x/%04x scale=%04x/%04x tag=%02x/%02x",
          item.txn_id, item.opcode, item.act_vec_out, exp_vec,
          item.act_softmax_max, exp_s_max, item.act_softmax_sum, exp_s_sum,
          item.act_absmax, exp_absmax, item.act_dyn_scale, exp_scale,
          item.act_done_tag, exp_tag))
      end
      checked_txns++;
    endfunction
  endclass : vfu_scoreboard

  // ---------------------------------------------------------------------------
  // 8. UVM Environment: vfu_env
  // ---------------------------------------------------------------------------
  class vfu_env extends uvm_env;
    `uvm_component_utils(vfu_env)

    vfu_agent      agent;
    vfu_scoreboard scoreboard;

    function new(string name = "vfu_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent      = vfu_agent::type_id::create("agent", this);
      scoreboard = vfu_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent.monitor.ap.connect(scoreboard.analysis_export);
    endfunction
  endclass : vfu_env

  // ---------------------------------------------------------------------------
  // 9. UVM Test: vfu_llm_ops_test
  // ---------------------------------------------------------------------------
  class vfu_llm_ops_test extends uvm_test;
    `uvm_component_utils(vfu_llm_ops_test)

    vfu_env env;

    function new(string name = "vfu_llm_ops_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = vfu_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
      vfu_sequence seq = vfu_sequence::type_id::create("seq");
      phase.raise_objection(this);
      seq.start(env.agent.sequencer);
      phase.drop_objection(this);
    endtask

    function void report_phase(uvm_phase phase);
      int unsigned dpi_calls = dpi_vfu_get_calls();
      real         func_cov  = env.agent.monitor.vfu_cg.get_inst_coverage();
      bit          pass_gate = (env.agent.driver.driven == 560) &&
                               (env.scoreboard.checked_txns == 560) &&
                               (dpi_calls == 560) &&
                               (env.scoreboard.mismatches == 0) &&
                               (func_cov == 100.0);
      super.report_phase(phase);
      dpi_vfu_set_status(pass_gate ? 0 : 1);
      if (!pass_gate) begin
        `uvm_fatal("UVM_VFU_FAIL", $sformatf(
          "VFU UVM failed: driven=%0d checked=%0d mismatches=%0d cov=%0.2f%%",
          env.agent.driver.driven, env.scoreboard.checked_txns,
          env.scoreboard.mismatches, func_cov))
      end else begin
        `uvm_info("UVM_VFU_PASS", $sformatf(
          "PASS: %0d VFU/LLM transactions verified bit-exact via DPI-C, 0 mismatches, %0.2f%% functional coverage",
          env.scoreboard.checked_txns, func_cov), UVM_LOW)
      end
    endfunction
  endclass : vfu_llm_ops_test

endpackage : mlu_vfu_uvm_pkg

`endif // MLU_VFU_UVM_PKG_SV
