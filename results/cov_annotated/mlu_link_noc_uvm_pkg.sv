//      // verilator_coverage annotation
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
%000000   class link_noc_seq_item extends uvm_sequence_item;
~000800     `uvm_object_utils(link_noc_seq_item)
        
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
        
~001600     function new(string name = "link_noc_seq_item");
 001600       super.new(name);
            endfunction
          endclass : link_noc_seq_item
        
          // ---------------------------------------------------------------------------
          // 2. UVM Sequence: link_noc_sequence (5-Port Routing, Wormhole, VC1, AllReduce, SerDes Replay)
          // ---------------------------------------------------------------------------
          class link_noc_sequence extends uvm_sequence #(link_noc_seq_item);
%000001     `uvm_object_utils(link_noc_sequence)
        
%000001     int unsigned     num_cycles = 800;
%000001     longint unsigned prng_state = 64'h5906_90C2_C123_8899;
        
%000001     function new(string name = "link_noc_sequence");
%000001       super.new(name);
            endfunction
        
 001800     function longint unsigned next_rand64();
 001800       prng_state ^= (prng_state << 13);
 001800       prng_state ^= (prng_state >> 7);
 001800       prng_state ^= (prng_state << 17);
 001800       return prng_state;
            endfunction
        
 003265     function logic [127:0] make_flit(
              mlu_flit_type_e ftype,
              bit             vc,
              bit [3:0]       src,
              bit [3:0]       dst,
              bit [31:0]      addr,
              bit [63:0]      payload
            );
 003265       mlu_noc_flit_t f;
 003265       f              = '0;
 003265       f.flit_type    = ftype;
 003265       f.vc_id        = vc;
 003265       f.src_id       = src;
 003265       f.dst_id       = dst;
 003265       f.pkt_seq      = 5'd0;
 003265       f.crc16_or_cmd = 16'hA55A;
 003265       f.addr         = addr;
 003265       f.payload      = payload;
 003265       return f;
            endfunction
        
%000001     task body();
%000001       bit [3:0] dst_lut[5] = '{4'd1, 4'd2, 4'd4, 4'd8, 4'd12}; // Local, N, S, E/D2D, W/C2C
%000001       bit [4:0] serdes_seq = 5'd0;
%000001       bit [4:0] saved_nack = 5'd0;
        
~000800       for (int unsigned cyc = 0; cyc < num_cycles; cyc++) begin
 000800         link_noc_seq_item item = link_noc_seq_item::type_id::create("item");
 000800         longint unsigned  r0   = next_rand64();
 000800         int unsigned      smod = cyc % 20;
        
 000800         start_item(item);
 000800         item.cycle_id     = cyc;
 000800         item.allreduce_en = 1'b0;
 000800         item.in_valid     = 5'b00000;
 000800         item.out_ready    = 5'b11111;
 004000         for (int p = 0; p < 5; p++) item.in_flit[p] = '0;
        
                // Phase 1 (0..199): 5-Port Concurrent Routing + VC1 Priority Preemption over VC0
 000200         if (cyc < 200) begin
 000200           item.in_valid = 5'b11111;
 001000           for (int p = 0; p < 5; p++) begin
 001000             bit       vc  = (cyc % 4 == 1) ? bit'(p[0]) : bit'((cyc + p) & 1);
 001000             bit [3:0] dst = (cyc % 4 == 1) ? dst_lut[cyc % 5] : dst_lut[(p + cyc) % 5];
 001000             item.in_flit[p] = make_flit(FLIT_HEAD_TAIL, vc, 4'(p), dst, 32'h1000_0000 + 32'(cyc*8), r0 + 64'(p));
                  end
                end
                // Phase 2 (200..399): Multi-Flit Wormhole Locking (FLIT_HEAD -> FLIT_BODY -> FLIT_TAIL)
 000200         else if (cyc < 400) begin
 000200           int unsigned wstep = (cyc - 200) % 6;
 000200           int unsigned wp    = ((cyc - 200) / 6) % 5;
 000200           bit [3:0]    wdst  = dst_lut[(wp + 1) % 5];
 000034           if (wstep == 0) begin
 000034             item.in_valid[wp] = 1'b1;
 000034             item.in_flit[wp]  = make_flit(FLIT_HEAD, 1'b0, 4'(wp), wdst, 32'h2000_0000, r0);
 000034           end else if (wstep == 1) begin
 000034             item.in_valid[wp] = 1'b1;
 000034             item.in_flit[wp]  = make_flit(FLIT_BODY, 1'b0, 4'(wp), wdst, 32'h2000_0008, r0 ^ 64'h5555);
                    // Competing port attempts to break lock on same output port
 000034             item.in_valid[(wp + 2) % 5] = 1'b1;
 000034             item.in_flit[(wp + 2) % 5]  = make_flit(FLIT_HEAD_TAIL, 1'b1, 4'((wp+2)%5), wdst, 32'h2000_0010, r0);
 000099           end else if (wstep == 2) begin
 000033             item.in_valid[wp] = 1'b1;
 000033             item.in_flit[wp]  = make_flit(FLIT_TAIL, 1'b0, 4'(wp), wdst, 32'h2000_0018, r0 ^ 64'hAAAA);
                  end
                end
                // Phase 3 (400..599): In-Router Hardware Ring/Tree AllReduce Combining (allreduce_en=1)
 000200         else if (cyc < 600) begin
 000200           item.allreduce_en = 1'b1;
 000134           if ((cyc % 3) == 0) begin
 000066             bit [3:0] ar_dst = dst_lut[(cyc / 3) % 5];
 000066             item.in_valid    = 5'b11111;
 000330             for (int p = 0; p < 5; p++) begin
 000330               item.in_flit[p] = make_flit(FLIT_HEAD_TAIL, 1'b1, 4'(p), ar_dst, 32'h3000_0000, 64'd100 + 64'(p * 10 + (cyc & 7)));
                    end
                  end
                end
                // Phase 4 (600..799): Constrained-Random Mixed Traffic + Backpressure
 000200         else begin
 000200           item.allreduce_en = bit'(r0[0]);
 000200           item.in_valid     = r0[5:1];
 000200           item.out_ready    = (r0[9:6] == 4'h0) ? 5'b10101 : 5'b11111;
 001000           for (int p = 0; p < 5; p++) begin
 001000             item.in_flit[p] = make_flit(FLIT_HEAD_TAIL, bit'(r0[10+p]), 4'(p), dst_lut[(r0[18:15] + p) % 5], 32'(r0[47:16]), next_rand64());
                  end
                end
        
                // Continuous C2C SerDes PCS Framing, Fault Injection & Go-Back-N Replay Recovery
 000800         item.tx_flit = make_flit(FLIT_HEAD_TAIL, bit'(cyc[0]), 4'd1, 4'd12, 32'h4000_0000 + 32'(cyc*8), r0);
 000040         if (smod == 10) begin
 000040           item.tx_valid       = 1'b1;
 000040           item.err_inject_crc = 1'b1;
 000040           item.replay_trigger = 1'b0;
 000040           item.replay_seq     = 5'd0;
 000040           saved_nack          = serdes_seq;
 000040           serdes_seq          = serdes_seq + 5'd1;
 000040         end else if (smod == 11) begin
 000040           item.tx_valid       = 1'b0;
 000040           item.err_inject_crc = 1'b0;
 000040           item.replay_trigger = 1'b1;
 000040           item.replay_seq     = saved_nack;
 000680         end else if (smod == 12) begin
 000040           item.tx_valid       = 1'b0;
 000040           item.err_inject_crc = 1'b0;
 000040           item.replay_trigger = 1'b0;
 000040           item.replay_seq     = 5'd0;
 000680         end else begin
 000680           item.tx_valid       = 1'b1;
 000680           item.err_inject_crc = 1'b0;
 000680           item.replay_trigger = 1'b0;
 000680           item.replay_seq     = 5'd0;
 000680           serdes_seq          = serdes_seq + 5'd1;
                end
        
 000800         finish_item(item);
              end
            endtask
          endclass : link_noc_sequence
        
          // ---------------------------------------------------------------------------
          // 3. UVM Sequencer: link_noc_sequencer
          // ---------------------------------------------------------------------------
          class link_noc_sequencer extends uvm_sequencer #(link_noc_seq_item);
%000001     `uvm_component_utils(link_noc_sequencer)
%000001     function new(string name = "link_noc_sequencer", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
          endclass : link_noc_sequencer
        
          // ---------------------------------------------------------------------------
          // 4. UVM Driver: link_noc_driver
          // ---------------------------------------------------------------------------
          class link_noc_driver extends uvm_driver #(link_noc_seq_item);
%000001     `uvm_component_utils(link_noc_driver)
        
            virtual mlu_link_noc_if vif;
%000001     int unsigned driven_cycles = 0;
        
%000001     function new(string name = "link_noc_driver", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       if (!uvm_config_db#(virtual mlu_link_noc_if)::get(this, "", "vif", vif))
%000000         `uvm_fatal("NO_VIF", "Virtual interface mlu_link_noc_if missing in link_noc_driver")
            endfunction
        
%000000     task run_phase(uvm_phase phase);
%000000       link_noc_seq_item item;
        
%000000       vif.rst_n            = 1'b0;
%000000       vif.cycle_id         = 0;
%000000       vif.allreduce_en_i   = 1'b0;
%000000       vif.in_valid_i       = '0;
%000000       vif.in_flit_i        = '0;
%000000       vif.out_ready_i      = 5'b11111;
%000000       vif.tx_valid_i       = 1'b0;
%000000       vif.tx_flit_i        = '0;
%000000       vif.err_inject_crc_i = 1'b0;
%000000       vif.replay_trigger_i = 1'b0;
%000000       vif.replay_seq_i     = 5'd0;
        
%000004       repeat (4) @(posedge vif.clk);
%000000       #1ns;
        
 000800       forever begin
 000800         seq_item_port.get_next_item(item);
 000800         vif.rst_n            = 1'b1;
 000800         vif.cycle_id         = item.cycle_id;
 000800         vif.allreduce_en_i   = item.allreduce_en;
 000800         vif.in_valid_i       = item.in_valid;
 000800         vif.out_ready_i      = item.out_ready;
 004000         for (int p = 0; p < 5; p++) begin
 004000           vif.in_flit_i[p] = item.in_flit[p];
                end
 000800         vif.tx_valid_i       = item.tx_valid;
 000800         vif.tx_flit_i        = item.tx_flit;
 000800         vif.err_inject_crc_i = item.err_inject_crc;
 000800         vif.replay_trigger_i = item.replay_trigger;
 000800         vif.replay_seq_i     = item.replay_seq;
        
 000800         @(posedge vif.clk);
 000800         #1ns;
 000800         driven_cycles++;
 000800         seq_item_port.item_done();
              end
            endtask
          endclass : link_noc_driver
        
          // ---------------------------------------------------------------------------
          // 5. UVM Monitor: link_noc_monitor (with Functional Covergroup)
          // ---------------------------------------------------------------------------
          class link_noc_monitor extends uvm_monitor;
%000001     `uvm_component_utils(link_noc_monitor)
        
            virtual mlu_link_noc_if vif;
            uvm_analysis_port #(link_noc_seq_item) ap;
%000001     int unsigned seen_cycles = 0;
        
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
 000573         bins p_local = {0};
 000170         bins p_north = {1};
 000172         bins p_south = {2};
 000170         bins p_east  = {3};
 000221         bins p_west  = {4};
              }
              cp_ftype: coverpoint ftype {
 001205         bins ft_single = {FLIT_HEAD_TAIL};
 000034         bins ft_head   = {FLIT_HEAD};
 000034         bins ft_body   = {FLIT_BODY};
 000033         bins ft_tail   = {FLIT_TAIL};
              }
              cp_vc: coverpoint vc {
 000873         bins vc0 = {1'b0};
 000433         bins vc1 = {1'b1};
              }
              cp_ar: coverpoint ar_en {
 001009         bins ar_off = {1'b0};
 000297         bins ar_on  = {1'b1};
              }
              cp_nack: coverpoint nack_v {
 001251         bins nack_0 = {1'b0};
 000055         bins nack_1 = {1'b1};
              }
              cp_replay: coverpoint replay_trig {
 001243         bins rep_0 = {1'b0};
 000063         bins rep_1 = {1'b1};
              }
            endgroup
        
%000001     function new(string name = "link_noc_monitor", uvm_component parent = null);
%000001       super.new(name, parent);
%000001       ap          = new("ap", this);
%000001       link_noc_cg = new();
            endfunction
        
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       if (!uvm_config_db#(virtual mlu_link_noc_if)::get(this, "", "vif", vif))
%000000         `uvm_fatal("NO_VIF", "Virtual interface mlu_link_noc_if missing in link_noc_monitor")
            endfunction
        
%000000     task run_phase(uvm_phase phase);
 000803       forever begin
 000803         @(negedge vif.clk);
~000800         if (vif.rst_n) begin
 000800           link_noc_seq_item item = link_noc_seq_item::type_id::create("mon_item");
 000800           item.cycle_id         = vif.cycle_id;
 000800           item.allreduce_en     = vif.allreduce_en_i;
 000800           item.in_valid         = vif.in_valid_i;
 000800           item.out_ready        = vif.out_ready_i;
 000800           item.tx_valid         = vif.tx_valid_i;
 000800           item.tx_flit          = vif.tx_flit_i;
 000800           item.err_inject_crc   = vif.err_inject_crc_i;
 000800           item.replay_trigger   = vif.replay_trigger_i;
 000800           item.replay_seq       = vif.replay_seq_i;
        
 000800           item.act_in_ready     = vif.in_ready_o;
 000800           item.act_out_valid    = vif.out_valid_o;
 004000           for (int p = 0; p < 5; p++) begin
 004000             item.in_flit[p]      = vif.in_flit_i[p];
 004000             item.act_out_flit[p] = vif.out_flit_o[p];
 003102             if (vif.out_valid_o[p]) begin
 000898               link_noc_cg.sample(p, vif.out_flit_o[p][127:126], vif.out_flit_o[p][125],
 000898                                  vif.allreduce_en_i, vif.nack_valid_o, vif.replay_trigger_i);
                    end
                  end
 000408           if (vif.out_valid_o == 5'b00000) begin
 000408             link_noc_cg.sample(0, FLIT_HEAD_TAIL, 1'b0, vif.allreduce_en_i,
 000408                                vif.nack_valid_o, vif.replay_trigger_i);
                  end
        
 000800           item.act_routed_cnt     = vif.routed_flit_cnt_o;
 000800           item.act_vc1_cnt        = vif.vc1_priority_cnt_o;
 000800           item.act_rx_valid       = vif.rx_valid_o;
 000800           item.act_rx_flit        = vif.rx_flit_o;
 000800           item.act_ack_valid      = vif.ack_valid_o;
 000800           item.act_ack_seq        = vif.ack_seq_o;
 000800           item.act_nack_valid     = vif.nack_valid_o;
 000800           item.act_nack_seq       = vif.nack_seq_o;
 000800           item.act_crc_err_cnt    = vif.crc_err_cnt_o;
 000800           item.act_retransmit_cnt = vif.retransmit_cnt_o;
        
 000800           seen_cycles++;
 000800           ap.write(item);
                end
              end
            endtask
          endclass : link_noc_monitor
        
          // ---------------------------------------------------------------------------
          // 6. UVM Agent: link_noc_agent
          // ---------------------------------------------------------------------------
          class link_noc_agent extends uvm_agent;
%000001     `uvm_component_utils(link_noc_agent)
            link_noc_sequencer sequencer;
            link_noc_driver    driver;
            link_noc_monitor   monitor;
%000001     function new(string name = "link_noc_agent", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       sequencer = link_noc_sequencer::type_id::create("sequencer", this);
%000001       driver    = link_noc_driver::type_id::create("driver", this);
%000001       monitor   = link_noc_monitor::type_id::create("monitor", this);
            endfunction
%000001     function void connect_phase(uvm_phase phase);
%000001       super.connect_phase(phase);
%000001       driver.seq_item_port.connect(sequencer.seq_item_export);
            endfunction
          endclass : link_noc_agent
        
          // ---------------------------------------------------------------------------
          // 7. UVM Scoreboard: link_noc_scoreboard (Cycle-Accurate DPI-C Check)
          // ---------------------------------------------------------------------------
          class link_noc_scoreboard extends uvm_scoreboard;
%000001     `uvm_component_utils(link_noc_scoreboard)
            uvm_analysis_imp #(link_noc_seq_item, link_noc_scoreboard) analysis_export;
%000001     int unsigned checked_cycles = 0;
%000001     int unsigned mismatches     = 0;
        
%000001     function new(string name = "link_noc_scoreboard", uvm_component parent = null);
%000001       super.new(name, parent);
%000001       analysis_export = new("analysis_export", this);
            endfunction
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       dpi_noc_ref_reset();
            endfunction
 000800     function void write(link_noc_seq_item item);
 000800       logic [4:0]   exp_in_rdy, exp_out_val;
 000800       logic [127:0] exp_rx_flit;
 000800       bit           cyc_err = 1'b0;
        
 004000       for (int p = 0; p < 5; p++) begin
 004000         dpi_noc_ref_set_router_port(p, int'(item.in_valid[p]),
 004000           item.in_flit[p][63:0], item.in_flit[p][127:64], int'(item.out_ready[p]));
              end
 000800       dpi_noc_ref_set_global_and_serdes(
 000800         int'(item.allreduce_en), int'(item.tx_valid),
 000800         item.tx_flit[63:0], item.tx_flit[127:64],
 000800         int'(item.err_inject_crc), int'(item.replay_trigger), int'(item.replay_seq)
              );
 000800       dpi_noc_ref_eval_comb();
        
 000800       exp_in_rdy  = 5'(dpi_noc_exp_in_ready_mask());
 000800       exp_out_val = 5'(dpi_noc_exp_out_valid_mask());
 000800       exp_rx_flit = {dpi_noc_exp_rx_flit_hi(), dpi_noc_exp_rx_flit_lo()};
        
~000800       if (item.act_in_ready       !== exp_in_rdy ||
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
%000000           item.act_retransmit_cnt !== dpi_noc_exp_retransmit_cnt()) begin
%000000         cyc_err = 1'b1;
              end
 004000       for (int p = 0; p < 5; p++) begin
 004000         logic [127:0] exp_of = {dpi_noc_exp_out_flit_hi(p), dpi_noc_exp_out_flit_lo(p)};
~004000         if (item.act_out_flit[p] !== exp_of) cyc_err = 1'b1;
              end
~000800       if (cyc_err) begin
%000000         mismatches++;
                `uvm_error("NOC_SERDES_MISMATCH", $sformatf(
                  "cyc=%0d out_v=%05b/%05b in_r=%05b/%05b routed=%0d/%0d rx_v=%0b/%0b nack=%0b/%0b crc_err=%0d/%0d retx=%0d/%0d",
                  item.cycle_id, item.act_out_valid, exp_out_val, item.act_in_ready, exp_in_rdy,
                  item.act_routed_cnt, dpi_noc_exp_routed_cnt(),
                  item.act_rx_valid, dpi_noc_exp_rx_valid(),
                  item.act_nack_valid, dpi_noc_exp_nack_valid(),
                  item.act_crc_err_cnt, dpi_noc_exp_crc_err_cnt(),
%000000           item.act_retransmit_cnt, dpi_noc_exp_retransmit_cnt()))
              end
 000800       checked_cycles++;
 000800       dpi_noc_ref_step_seq();
            endfunction
          endclass : link_noc_scoreboard
        
          // ---------------------------------------------------------------------------
          // 8. UVM Environment & Test: link_noc_env, mlu_link_noc_test
          // ---------------------------------------------------------------------------
          class link_noc_env extends uvm_env;
%000001     `uvm_component_utils(link_noc_env)
            link_noc_agent      agent;
            link_noc_scoreboard scoreboard;
%000001     function new(string name = "link_noc_env", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       agent      = link_noc_agent::type_id::create("agent", this);
%000001       scoreboard = link_noc_scoreboard::type_id::create("scoreboard", this);
            endfunction
%000001     function void connect_phase(uvm_phase phase);
%000001       super.connect_phase(phase);
%000001       agent.monitor.ap.connect(scoreboard.analysis_export);
            endfunction
          endclass : link_noc_env
        
          class mlu_link_noc_test extends uvm_test;
%000002     `uvm_component_utils(mlu_link_noc_test)
            link_noc_env env;
%000001     function new(string name = "mlu_link_noc_test", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
%000001     function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       env = link_noc_env::type_id::create("env", this);
            endfunction
%000001     task run_phase(uvm_phase phase);
%000001       link_noc_sequence seq = link_noc_sequence::type_id::create("seq");
%000001       phase.raise_objection(this);
%000001       seq.start(env.agent.sequencer);
%000001       phase.drop_objection(this);
            endtask
%000001     function void report_phase(uvm_phase phase);
%000001       int unsigned dpi_calls = dpi_noc_get_calls();
%000001       real         func_cov  = env.agent.monitor.link_noc_cg.get_inst_coverage();
              bit          pass_gate = (env.agent.driver.driven_cycles == 800) &&
                                       (env.scoreboard.checked_cycles == 800) &&
                                       (dpi_calls == 800) &&
                                       (env.scoreboard.mismatches == 0) &&
                                       (dpi_noc_exp_routed_cnt() > 800) &&
                                       (dpi_noc_exp_vc1_cnt() > 400) &&
                                       (dpi_noc_exp_crc_err_cnt() == 40) &&
%000001                                (dpi_noc_exp_retransmit_cnt() == 40) &&
                                       (func_cov == 100.0);
%000001       super.report_phase(phase);
%000001       dpi_noc_set_status(pass_gate ? 0 : 1);
%000001       if (!pass_gate) begin
                `uvm_fatal("UVM_LINK_NOC_FAIL", $sformatf(
                  "MLU-Link NoC UVM failed: cyc=%0d mismatches=%0d routed=%0d vc1=%0d crc_err=%0d retx=%0d cov=%0.2f%%",
                  env.scoreboard.checked_cycles, env.scoreboard.mismatches,
                  dpi_noc_exp_routed_cnt(), dpi_noc_exp_vc1_cnt(),
%000000           dpi_noc_exp_crc_err_cnt(), dpi_noc_exp_retransmit_cnt(), func_cov))
%000001       end else begin
                `uvm_info("UVM_LINK_NOC_PASS", $sformatf(
                  "PASS: %0d cycles (%0d routed flits, %0d VC1 priority grants, %0d CRC faults & %0d Go-Back-N replays) verified bit-exact via DPI-C, 0 mismatches, %0.2f%% functional coverage",
                  env.scoreboard.checked_cycles, dpi_noc_exp_routed_cnt(), dpi_noc_exp_vc1_cnt(),
%000001           dpi_noc_exp_crc_err_cnt(), dpi_noc_exp_retransmit_cnt(), func_cov), UVM_LOW)
              end
            endfunction
          endclass : mlu_link_noc_test
        
        endpackage : mlu_link_noc_uvm_pkg
        
        `endif // MLU_LINK_NOC_UVM_PKG_SV
        
