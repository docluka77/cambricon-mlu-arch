// =============================================================================
// File: uvm_tb/uvm_mlu_link_noc/mlu_link_noc_uvm_pkg.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Accellera IEEE 1800.2-2020 UVM Verification Package for Suite 6:
//              mlu_link_noc_router + mlu_c2c_serdes_pcs.
// =============================================================================
`ifndef MLU_LINK_NOC_UVM_PKG_SV
`define MLU_LINK_NOC_UVM_PKG_SV

`timescale 1ns/1ps
`include "uvm_macros.svh"
`include "mlu_pkg.sv"

package mlu_link_noc_uvm_pkg;
  import uvm_pkg::*;
  import mlu_pkg::*;

  // ---------------------------------------------------------------------------
  // DPI-C Cycle-Accurate Reference Model Imports
  // ---------------------------------------------------------------------------
  import "DPI-C" function void             dpi_noc_set_status(int status);
  import "DPI-C" function int              dpi_noc_get_status();
  import "DPI-C" function int unsigned     dpi_noc_get_calls();
  import "DPI-C" function void             dpi_noc_ref_reset();
  import "DPI-C" function void             dpi_noc_ref_set_router_port(
    int              p,
    int unsigned     in_valid,
    longint unsigned flit_lo,
    longint unsigned flit_hi,
    int unsigned     out_ready
  );
  import "DPI-C" function void             dpi_noc_ref_set_global_and_serdes(
    int unsigned     allreduce_en,
    int unsigned     tx_valid,
    longint unsigned tx_flit_lo,
    longint unsigned tx_flit_hi,
    int unsigned     err_inject_crc,
    int unsigned     replay_trigger,
    int unsigned     replay_seq
  );
  import "DPI-C" function void             dpi_noc_ref_eval_comb();
  import "DPI-C" function void             dpi_noc_ref_step_seq();
  import "DPI-C" function int unsigned     dpi_noc_exp_out_valid_mask();
  import "DPI-C" function int unsigned     dpi_noc_exp_in_ready_mask();
  import "DPI-C" function longint unsigned dpi_noc_exp_out_flit_lo(int p);
  import "DPI-C" function longint unsigned dpi_noc_exp_out_flit_hi(int p);
  import "DPI-C" function int unsigned     dpi_noc_exp_routed_cnt();
  import "DPI-C" function int unsigned     dpi_noc_exp_vc1_cnt();
  import "DPI-C" function int unsigned     dpi_noc_exp_rx_valid();
  import "DPI-C" function longint unsigned dpi_noc_exp_rx_flit_lo();
  import "DPI-C" function longint unsigned dpi_noc_exp_rx_flit_hi();
  import "DPI-C" function int unsigned     dpi_noc_exp_ack_valid();
  import "DPI-C" function int unsigned     dpi_noc_exp_ack_seq();
  import "DPI-C" function int unsigned     dpi_noc_exp_nack_valid();
  import "DPI-C" function int unsigned     dpi_noc_exp_nack_seq();
  import "DPI-C" function int unsigned     dpi_noc_exp_crc_err_cnt();
  import "DPI-C" function int unsigned     dpi_noc_exp_retransmit_cnt();

  // ---------------------------------------------------------------------------
  // 1. UVM Sequence Item: link_noc_seq_item
  // ---------------------------------------------------------------------------
  class link_noc_seq_item extends uvm_sequence_item;
    `uvm_object_utils(link_noc_seq_item)

    int unsigned       cycle_id;
    bit                allreduce_en;
    bit [4:0]          in_valid;
    logic [127:0]      in_flit [5];
    bit [4:0]          out_ready;

    bit                tx_valid;
    logic [127:0]      tx_flit;
    bit                err_inject_crc;
    bit                replay_trigger;
    bit [4:0]          replay_seq;

    // Sampled DUT Outputs
    logic [4:0]        act_in_ready;
    logic [4:0]        act_out_valid;
    logic [127:0]      act_out_flit [5];
    logic [31:0]       act_routed_cnt;
    logic [31:0]       act_vc1_cnt;

    logic              act_rx_valid;
    logic [127:0]      act_rx_flit;
    logic              act_ack_valid;
    logic [4:0]        act_ack_seq;
    logic              act_nack_valid;
    logic [4:0]        act_nack_seq;
    logic [31:0]       act_crc_err_cnt;
    logic [31:0]       act_retransmit_cnt;

    function new(string name = "link_noc_seq_item");
      super.new(name);
    endfunction
  endclass : link_noc_seq_item

  // ---------------------------------------------------------------------------
  // 2. UVM Sequence: link_noc_sequence (5-Port Routing, Wormhole, VC1, AllReduce, SerDes Replay)
  // ---------------------------------------------------------------------------
  class link_noc_sequence extends uvm_sequence #(link_noc_seq_item);
    `uvm_object_utils(link_noc_sequence)

    int unsigned     num_cycles = 800;
    longint unsigned prng_state = 64'h5906_90C2_C123_8899;

    function new(string name = "link_noc_sequence");
      super.new(name);
    endfunction

    function longint unsigned next_rand64();
      prng_state ^= (prng_state << 13);
      prng_state ^= (prng_state >> 7);
      prng_state ^= (prng_state << 17);
      return prng_state;
    endfunction

    function logic [127:0] make_flit(
      mlu_flit_type_e ftype,
      bit             vc,
      bit [3:0]       src,
      bit [3:0]       dst,
      bit [31:0]      addr,
      bit [63:0]      payload
    );
      mlu_noc_flit_t f;
      f              = '0;
      f.flit_type    = ftype;
      f.vc_id        = vc;
      f.src_id       = src;
      f.dst_id       = dst;
      f.pkt_seq      = 5'd0;
      f.crc16_or_cmd = 16'hA55A;
      f.addr         = addr;
      f.payload      = payload;
      return f;
    endfunction

    task body();
      bit [3:0] dst_lut[5] = '{4'd1, 4'd2, 4'd4, 4'd8, 4'd12}; // Local, N, S, E/D2D, W/C2C
      bit [4:0] serdes_seq = 5'd0;
      bit [4:0] saved_nack = 5'd0;

      for (int unsigned cyc = 0; cyc < num_cycles; cyc++) begin
        link_noc_seq_item item = link_noc_seq_item::type_id::create("item");
        longint unsigned  r0   = next_rand64();
        int unsigned      smod = cyc % 20;

        start_item(item);
        item.cycle_id     = cyc;
        item.allreduce_en = 1'b0;
        item.in_valid     = 5'b00000;
        item.out_ready    = 5'b11111;
        for (int p = 0; p < 5; p++) item.in_flit[p] = '0;

        // Phase 1 (0..199): 5-Port Concurrent Routing + VC1 Priority Preemption over VC0
        if (cyc < 200) begin
          item.in_valid = 5'b11111;
          for (int p = 0; p < 5; p++) begin
            bit       vc  = (cyc % 4 == 1) ? bit'(p[0]) : bit'((cyc + p) & 1);
            bit [3:0] dst = (cyc % 4 == 1) ? dst_lut[cyc % 5] : dst_lut[(p + cyc) % 5];
            item.in_flit[p] = make_flit(FLIT_HEAD_TAIL, vc, 4'(p), dst, 32'h1000_0000 + 32'(cyc*8), r0 + 64'(p));
          end
        end
        // Phase 2 (200..399): Multi-Flit Wormhole Locking (FLIT_HEAD -> FLIT_BODY -> FLIT_TAIL)
        else if (cyc < 400) begin
          int unsigned wstep = (cyc - 200) % 6;
          int unsigned wp    = ((cyc - 200) / 6) % 5;
          bit [3:0]    wdst  = dst_lut[(wp + 1) % 5];
          if (wstep == 0) begin
            item.in_valid[wp] = 1'b1;
            item.in_flit[wp]  = make_flit(FLIT_HEAD, 1'b0, 4'(wp), wdst, 32'h2000_0000, r0);
          end else if (wstep == 1) begin
            item.in_valid[wp] = 1'b1;
            item.in_flit[wp]  = make_flit(FLIT_BODY, 1'b0, 4'(wp), wdst, 32'h2000_0008, r0 ^ 64'h5555);
            // Competing port attempts to break lock on same output port
            item.in_valid[(wp + 2) % 5] = 1'b1;
            item.in_flit[(wp + 2) % 5]  = make_flit(FLIT_HEAD_TAIL, 1'b1, 4'((wp+2)%5), wdst, 32'h2000_0010, r0);
          end else if (wstep == 2) begin
            item.in_valid[wp] = 1'b1;
            item.in_flit[wp]  = make_flit(FLIT_TAIL, 1'b0, 4'(wp), wdst, 32'h2000_0018, r0 ^ 64'hAAAA);
          end
        end
        // Phase 3 (400..599): In-Router Hardware Ring/Tree AllReduce Combining (allreduce_en=1)
        else if (cyc < 600) begin
          item.allreduce_en = 1'b1;
          if ((cyc % 3) == 0) begin
            bit [3:0] ar_dst = dst_lut[(cyc / 3) % 5];
            item.in_valid    = 5'b11111;
            for (int p = 0; p < 5; p++) begin
              item.in_flit[p] = make_flit(FLIT_HEAD_TAIL, 1'b1, 4'(p), ar_dst, 32'h3000_0000, 64'd100 + 64'(p * 10 + (cyc & 7)));
            end
          end
        end
        // Phase 4 (600..799): Constrained-Random Mixed Traffic + Backpressure
        else begin
          item.allreduce_en = bit'(r0[0]);
          item.in_valid     = r0[5:1];
          item.out_ready    = (r0[9:6] == 4'h0) ? 5'b10101 : 5'b11111;
          for (int p = 0; p < 5; p++) begin
            item.in_flit[p] = make_flit(FLIT_HEAD_TAIL, bit'(r0[10+p]), 4'(p), dst_lut[(r0[18:15] + p) % 5], 32'(r0[47:16]), next_rand64());
          end
        end

        // Continuous C2C SerDes PCS Framing, Fault Injection & Go-Back-N Replay Recovery
        item.tx_flit = make_flit(FLIT_HEAD_TAIL, bit'(cyc[0]), 4'd1, 4'd12, 32'h4000_0000 + 32'(cyc*8), r0);
        if (smod == 10) begin
          item.tx_valid       = 1'b1;
          item.err_inject_crc = 1'b1;
          item.replay_trigger = 1'b0;
          item.replay_seq     = 5'd0;
          saved_nack          = serdes_seq;
          serdes_seq          = serdes_seq + 5'd1;
        end else if (smod == 11) begin
          item.tx_valid       = 1'b0;
          item.err_inject_crc = 1'b0;
          item.replay_trigger = 1'b1;
          item.replay_seq     = saved_nack;
        end else if (smod == 12) begin
          item.tx_valid       = 1'b0;
          item.err_inject_crc = 1'b0;
          item.replay_trigger = 1'b0;
          item.replay_seq     = 5'd0;
        end else begin
          item.tx_valid       = 1'b1;
          item.err_inject_crc = 1'b0;
          item.replay_trigger = 1'b0;
          item.replay_seq     = 5'd0;
          serdes_seq          = serdes_seq + 5'd1;
        end

        finish_item(item);
      end
    endtask
  endclass : link_noc_sequence

  // ---------------------------------------------------------------------------
  // 3. UVM Sequencer: link_noc_sequencer
  // ---------------------------------------------------------------------------
  class link_noc_sequencer extends uvm_sequencer #(link_noc_seq_item);
    `uvm_component_utils(link_noc_sequencer)
    function new(string name = "link_noc_sequencer", uvm_component parent = null);
      super.new(name, parent);
    endfunction
  endclass : link_noc_sequencer

  // ---------------------------------------------------------------------------
  // 4. UVM Driver: link_noc_driver
  // ---------------------------------------------------------------------------
  class link_noc_driver extends uvm_driver #(link_noc_seq_item);
    `uvm_component_utils(link_noc_driver)

    virtual mlu_link_noc_if vif;
    int unsigned driven_cycles = 0;

    function new(string name = "link_noc_driver", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual mlu_link_noc_if)::get(this, "", "vif", vif))
        `uvm_fatal("NO_VIF", "Virtual interface mlu_link_noc_if missing in link_noc_driver")
    endfunction

    task run_phase(uvm_phase phase);
      link_noc_seq_item item;

      vif.rst_n            = 1'b0;
      vif.cycle_id         = 0;
      vif.allreduce_en_i   = 1'b0;
      vif.in_valid_i       = '0;
      vif.in_flit_i        = '0;
      vif.out_ready_i      = 5'b11111;
      vif.tx_valid_i       = 1'b0;
      vif.tx_flit_i        = '0;
      vif.err_inject_crc_i = 1'b0;
      vif.replay_trigger_i = 1'b0;
      vif.replay_seq_i     = 5'd0;

      repeat (4) @(posedge vif.clk);
      #1ns;

      forever begin
        seq_item_port.get_next_item(item);
        vif.rst_n            = 1'b1;
        vif.cycle_id         = item.cycle_id;
        vif.allreduce_en_i   = item.allreduce_en;
        vif.in_valid_i       = item.in_valid;
        vif.out_ready_i      = item.out_ready;
        for (int p = 0; p < 5; p++) begin
          vif.in_flit_i[p] = item.in_flit[p];
        end
        vif.tx_valid_i       = item.tx_valid;
        vif.tx_flit_i        = item.tx_flit;
        vif.err_inject_crc_i = item.err_inject_crc;
        vif.replay_trigger_i = item.replay_trigger;
        vif.replay_seq_i     = item.replay_seq;

        @(posedge vif.clk);
        #1ns;
        driven_cycles++;
        seq_item_port.item_done();
      end
    endtask
  endclass : link_noc_driver

  // ---------------------------------------------------------------------------
  // 5. UVM Monitor: link_noc_monitor (with Functional Covergroup)
  // ---------------------------------------------------------------------------
  class link_noc_monitor extends uvm_monitor;
    `uvm_component_utils(link_noc_monitor)

    virtual mlu_link_noc_if vif;
    uvm_analysis_port #(link_noc_seq_item) ap;
    int unsigned seen_cycles = 0;

    covergroup link_noc_cg with function sample(
      int       out_port,
      bit [1:0] ftype,
      bit       vc,
      bit       ar_en,
      bit       nack_v,
      bit       replay_trig
    );
      option.per_instance = 1;
      cp_out_port: coverpoint out_port {
        bins p_local = {0};
        bins p_north = {1};
        bins p_south = {2};
        bins p_east  = {3};
        bins p_west  = {4};
      }
      cp_ftype: coverpoint ftype {
        bins ft_single = {FLIT_HEAD_TAIL};
        bins ft_head   = {FLIT_HEAD};
        bins ft_body   = {FLIT_BODY};
        bins ft_tail   = {FLIT_TAIL};
      }
      cp_vc: coverpoint vc {
        bins vc0 = {1'b0};
        bins vc1 = {1'b1};
      }
      cp_ar: coverpoint ar_en {
        bins ar_off = {1'b0};
        bins ar_on  = {1'b1};
      }
      cp_nack: coverpoint nack_v {
        bins nack_0 = {1'b0};
        bins nack_1 = {1'b1};
      }
      cp_replay: coverpoint replay_trig {
        bins rep_0 = {1'b0};
        bins rep_1 = {1'b1};
      }
    endgroup

    function new(string name = "link_noc_monitor", uvm_component parent = null);
      super.new(name, parent);
      ap          = new("ap", this);
      link_noc_cg = new();
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual mlu_link_noc_if)::get(this, "", "vif", vif))
        `uvm_fatal("NO_VIF", "Virtual interface mlu_link_noc_if missing in link_noc_monitor")
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        @(negedge vif.clk);
        if (vif.rst_n) begin
          link_noc_seq_item item = link_noc_seq_item::type_id::create("mon_item");
          item.cycle_id         = vif.cycle_id;
          item.allreduce_en     = vif.allreduce_en_i;
          item.in_valid         = vif.in_valid_i;
          item.out_ready        = vif.out_ready_i;
          item.tx_valid         = vif.tx_valid_i;
          item.tx_flit          = vif.tx_flit_i;
          item.err_inject_crc   = vif.err_inject_crc_i;
          item.replay_trigger   = vif.replay_trigger_i;
          item.replay_seq       = vif.replay_seq_i;

          item.act_in_ready     = vif.in_ready_o;
          item.act_out_valid    = vif.out_valid_o;
          for (int p = 0; p < 5; p++) begin
            item.in_flit[p]      = vif.in_flit_i[p];
            item.act_out_flit[p] = vif.out_flit_o[p];
            if (vif.out_valid_o[p]) begin
              link_noc_cg.sample(p, vif.out_flit_o[p][127:126], vif.out_flit_o[p][125],
                                 vif.allreduce_en_i, vif.nack_valid_o, vif.replay_trigger_i);
            end
          end
          if (vif.out_valid_o == 5'b00000) begin
            link_noc_cg.sample(0, FLIT_HEAD_TAIL, 1'b0, vif.allreduce_en_i,
                               vif.nack_valid_o, vif.replay_trigger_i);
          end

          item.act_routed_cnt     = vif.routed_flit_cnt_o;
          item.act_vc1_cnt        = vif.vc1_priority_cnt_o;
          item.act_rx_valid       = vif.rx_valid_o;
          item.act_rx_flit        = vif.rx_flit_o;
          item.act_ack_valid      = vif.ack_valid_o;
          item.act_ack_seq        = vif.ack_seq_o;
          item.act_nack_valid     = vif.nack_valid_o;
          item.act_nack_seq       = vif.nack_seq_o;
          item.act_crc_err_cnt    = vif.crc_err_cnt_o;
          item.act_retransmit_cnt = vif.retransmit_cnt_o;

          seen_cycles++;
          ap.write(item);
        end
      end
    endtask
  endclass : link_noc_monitor

  // ---------------------------------------------------------------------------
  // 6. UVM Agent: link_noc_agent
  // ---------------------------------------------------------------------------
  class link_noc_agent extends uvm_agent;
    `uvm_component_utils(link_noc_agent)
    link_noc_sequencer sequencer;
    link_noc_driver    driver;
    link_noc_monitor   monitor;
    function new(string name = "link_noc_agent", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      sequencer = link_noc_sequencer::type_id::create("sequencer", this);
      driver    = link_noc_driver::type_id::create("driver", this);
      monitor   = link_noc_monitor::type_id::create("monitor", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
  endclass : link_noc_agent

  // ---------------------------------------------------------------------------
  // 7. UVM Scoreboard: link_noc_scoreboard (Cycle-Accurate DPI-C Check)
  // ---------------------------------------------------------------------------
  class link_noc_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(link_noc_scoreboard)
    uvm_analysis_imp #(link_noc_seq_item, link_noc_scoreboard) analysis_export;
    int unsigned checked_cycles = 0;
    int unsigned mismatches     = 0;

    function new(string name = "link_noc_scoreboard", uvm_component parent = null);
      super.new(name, parent);
      analysis_export = new("analysis_export", this);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      dpi_noc_ref_reset();
    endfunction
    function void write(link_noc_seq_item item);
      logic [4:0]   exp_in_rdy, exp_out_val;
      logic [127:0] exp_rx_flit;
      bit           cyc_err = 1'b0;

      for (int p = 0; p < 5; p++) begin
        dpi_noc_ref_set_router_port(p, int'(item.in_valid[p]),
          item.in_flit[p][63:0], item.in_flit[p][127:64], int'(item.out_ready[p]));
      end
      dpi_noc_ref_set_global_and_serdes(
        int'(item.allreduce_en), int'(item.tx_valid),
        item.tx_flit[63:0], item.tx_flit[127:64],
        int'(item.err_inject_crc), int'(item.replay_trigger), int'(item.replay_seq)
      );
      dpi_noc_ref_eval_comb();

      exp_in_rdy  = 5'(dpi_noc_exp_in_ready_mask());
      exp_out_val = 5'(dpi_noc_exp_out_valid_mask());
      exp_rx_flit = {dpi_noc_exp_rx_flit_hi(), dpi_noc_exp_rx_flit_lo()};

      if (item.act_in_ready       !== exp_in_rdy ||
          item.act_out_valid      !== exp_out_val ||
          item.act_routed_cnt     !== dpi_noc_exp_routed_cnt() ||
          item.act_vc1_cnt        !== dpi_noc_exp_vc1_cnt() ||
          item.act_rx_valid       !== 1'(dpi_noc_exp_rx_valid()) ||
          item.act_rx_flit        !== exp_rx_flit ||
          item.act_ack_valid      !== 1'(dpi_noc_exp_ack_valid()) ||
          item.act_ack_seq        !== 5'(dpi_noc_exp_ack_seq()) ||
          item.act_nack_valid     !== 1'(dpi_noc_exp_nack_valid()) ||
          item.act_nack_seq       !== 5'(dpi_noc_exp_nack_seq()) ||
          item.act_crc_err_cnt    !== dpi_noc_exp_crc_err_cnt() ||
          item.act_retransmit_cnt !== dpi_noc_exp_retransmit_cnt()) begin
        cyc_err = 1'b1;
      end
      for (int p = 0; p < 5; p++) begin
        logic [127:0] exp_of = {dpi_noc_exp_out_flit_hi(p), dpi_noc_exp_out_flit_lo(p)};
        if (item.act_out_flit[p] !== exp_of) cyc_err = 1'b1;
      end
      if (cyc_err) begin
        mismatches++;
        `uvm_error("NOC_SERDES_MISMATCH", $sformatf(
          "cyc=%0d out_v=%05b/%05b in_r=%05b/%05b routed=%0d/%0d rx_v=%0b/%0b nack=%0b/%0b crc_err=%0d/%0d retx=%0d/%0d",
          item.cycle_id, item.act_out_valid, exp_out_val, item.act_in_ready, exp_in_rdy,
          item.act_routed_cnt, dpi_noc_exp_routed_cnt(),
          item.act_rx_valid, dpi_noc_exp_rx_valid(),
          item.act_nack_valid, dpi_noc_exp_nack_valid(),
          item.act_crc_err_cnt, dpi_noc_exp_crc_err_cnt(),
          item.act_retransmit_cnt, dpi_noc_exp_retransmit_cnt()))
      end
      checked_cycles++;
      dpi_noc_ref_step_seq();
    endfunction
  endclass : link_noc_scoreboard

  // ---------------------------------------------------------------------------
  // 8. UVM Environment & Test: link_noc_env, mlu_link_noc_test
  // ---------------------------------------------------------------------------
  class link_noc_env extends uvm_env;
    `uvm_component_utils(link_noc_env)
    link_noc_agent      agent;
    link_noc_scoreboard scoreboard;
    function new(string name = "link_noc_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent      = link_noc_agent::type_id::create("agent", this);
      scoreboard = link_noc_scoreboard::type_id::create("scoreboard", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent.monitor.ap.connect(scoreboard.analysis_export);
    endfunction
  endclass : link_noc_env

  class mlu_link_noc_test extends uvm_test;
    `uvm_component_utils(mlu_link_noc_test)
    link_noc_env env;
    function new(string name = "mlu_link_noc_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = link_noc_env::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
      link_noc_sequence seq = link_noc_sequence::type_id::create("seq");
      phase.raise_objection(this);
      seq.start(env.agent.sequencer);
      phase.drop_objection(this);
    endtask
    function void report_phase(uvm_phase phase);
      int unsigned dpi_calls = dpi_noc_get_calls();
      real         func_cov  = env.agent.monitor.link_noc_cg.get_inst_coverage();
      bit          pass_gate = (env.agent.driver.driven_cycles == 800) &&
                               (env.scoreboard.checked_cycles == 800) &&
                               (dpi_calls == 800) &&
                               (env.scoreboard.mismatches == 0) &&
                               (dpi_noc_exp_routed_cnt() > 800) &&
                               (dpi_noc_exp_vc1_cnt() > 400) &&
                               (dpi_noc_exp_crc_err_cnt() == 40) &&
                               (dpi_noc_exp_retransmit_cnt() == 40) &&
                               (func_cov == 100.0);
      super.report_phase(phase);
      dpi_noc_set_status(pass_gate ? 0 : 1);
      if (!pass_gate) begin
        `uvm_fatal("UVM_LINK_NOC_FAIL", $sformatf(
          "MLU-Link NoC UVM failed: cyc=%0d mismatches=%0d routed=%0d vc1=%0d crc_err=%0d retx=%0d cov=%0.2f%%",
          env.scoreboard.checked_cycles, env.scoreboard.mismatches,
          dpi_noc_exp_routed_cnt(), dpi_noc_exp_vc1_cnt(),
          dpi_noc_exp_crc_err_cnt(), dpi_noc_exp_retransmit_cnt(), func_cov))
      end else begin
        `uvm_info("UVM_LINK_NOC_PASS", $sformatf(
          "PASS: %0d cycles (%0d routed flits, %0d VC1 priority grants, %0d CRC faults & %0d Go-Back-N replays) verified bit-exact via DPI-C, 0 mismatches, %0.2f%% functional coverage",
          env.scoreboard.checked_cycles, dpi_noc_exp_routed_cnt(), dpi_noc_exp_vc1_cnt(),
          dpi_noc_exp_crc_err_cnt(), dpi_noc_exp_retransmit_cnt(), func_cov), UVM_LOW)
      end
    endfunction
  endclass : mlu_link_noc_test

endpackage : mlu_link_noc_uvm_pkg

`endif // MLU_LINK_NOC_UVM_PKG_SV
