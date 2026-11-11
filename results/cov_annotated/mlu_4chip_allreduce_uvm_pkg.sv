//      // verilator_coverage annotation
        // =============================================================================
        // File: uvm_tb/uvm_4chip_allreduce/mlu_4chip_allreduce_uvm_pkg.sv
        // Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
        // Description: Accellera IEEE 1800.2-2020 UVM Verification Package for Suite 9:
        //              mlu_4chip_oam_node (4-Chip OAM Ring/Butterfly AllReduce & Routing).
        // =============================================================================
        `ifndef MLU_4CHIP_ALLREDUCE_UVM_PKG_SV
        `define MLU_4CHIP_ALLREDUCE_UVM_PKG_SV
        
        `timescale 1ns/1ps
        `include "uvm_macros.svh"
        `include "mlu_pkg.sv"
        
        package mlu_4chip_allreduce_uvm_pkg;
          import uvm_pkg::*;
          import mlu_pkg::*;
        
          // ---------------------------------------------------------------------------
          // DPI-C Golden Reference Model Imports
          // ---------------------------------------------------------------------------
          import "DPI-C" function void             dpi_4chip_set_status(int status);
          import "DPI-C" function int              dpi_4chip_get_status();
          import "DPI-C" function int unsigned     dpi_4chip_get_calls();
          import "DPI-C" function longint unsigned dpi_4chip_calc_allreduce_sum(
            longint unsigned g0,
            longint unsigned g1,
            longint unsigned g2,
            longint unsigned g3,
            int unsigned     mode
          );
          import "DPI-C" function int unsigned     dpi_4chip_expected_hops(int unsigned mode);
          import "DPI-C" function void             dpi_4chip_record_unicast_check();
        
          // ---------------------------------------------------------------------------
          // 1. UVM Sequence Item: oam_4chip_seq_item
          // ---------------------------------------------------------------------------
          typedef enum int {
            TXN_RING_ALLREDUCE      = 0,
            TXN_BUTTERFLY_ALLREDUCE = 1,
            TXN_UNICAST_FLIT        = 2
          } oam_txn_kind_e;
        
%000000   class oam_4chip_seq_item extends uvm_sequence_item;
~000240     `uvm_object_utils(oam_4chip_seq_item)
        
            int unsigned       txn_id;
            oam_txn_kind_e     kind;
            bit                allreduce_mode;
            logic [63:0]       grad [4];
            bit [3:0]          err_inject_mask;
        
            bit [1:0]          src_chip;
            bit [1:0]          dst_chip;
            bit                use_diagonal;
            logic [63:0]       flit_payload;
        
            // Sampled DUT Responses
            logic [63:0]       act_sum [4];
            logic [2:0]        act_hops;
            logic [3:0]        act_done;
            bit                rx_matched;
            logic [63:0]       act_rx_payload;
            logic [31:0]       act_crc_errs;
            logic [31:0]       act_retransmits;
            logic [31:0]       act_routed_flits;
            logic [31:0]       act_collectives;
        
~000480     function new(string name = "oam_4chip_seq_item");
 000480       super.new(name);
            endfunction
          endclass : oam_4chip_seq_item
          // ---------------------------------------------------------------------------
          // 2. UVM Sequence: oam_4chip_sequence (240 Transactions: Ring, Butterfly, Unicast + Faults)
          // ---------------------------------------------------------------------------
          class oam_4chip_sequence extends uvm_sequence #(oam_4chip_seq_item);
%000001     `uvm_object_utils(oam_4chip_sequence)
        
%000001     int unsigned     num_txns   = 240;
%000001     longint unsigned prng_state = 64'h5906_900A_4C11_2026;
        
%000001     function new(string name = "oam_4chip_sequence");
%000001       super.new(name);
            endfunction
        
 001440     function longint unsigned next_rand64();
 001440       prng_state ^= (prng_state << 13);
 001440       prng_state ^= (prng_state >> 7);
 001440       prng_state ^= (prng_state << 17);
 001440       return prng_state;
            endfunction
        
%000001     virtual task body();
~000240       for (int unsigned t = 0; t < num_txns; t++) begin
 000240         oam_4chip_seq_item req = oam_4chip_seq_item::type_id::create($sformatf("txn_%0d", t));
 000240         longint unsigned r0 = next_rand64();
 000240         start_item(req);
 000240         req.txn_id = t;
        
 000080         if ((t % 3) == 0) begin
 000080           req.kind            = TXN_RING_ALLREDUCE;
 000080           req.allreduce_mode  = 1'b0;
 000080         end else if ((t % 3) == 1) begin
 000080           req.kind            = TXN_BUTTERFLY_ALLREDUCE;
 000080           req.allreduce_mode  = 1'b1;
 000080         end else begin
 000080           req.kind            = TXN_UNICAST_FLIT;
 000080           req.allreduce_mode  = 1'b0;
                end
        
 000960         for (int c = 0; c < 4; c++) begin
 000960           req.grad[c] = next_rand64();
                end
        
                // Inject transient C2C CRC link error on every 5th transaction
 000192         if ((t % 5) == 4) begin
 000048           req.err_inject_mask = 4'(1 << (t & 3));
 000192         end else begin
 000192           req.err_inject_mask = 4'b0000;
                end
        
 000240         req.src_chip     = 2'(r0[1:0]);
 000240         req.dst_chip     = 2'((r0[1:0] + 1 + (r0[3:2] % 3)) & 3);
 000240         req.use_diagonal = (req.dst_chip == (req.src_chip ^ 2'd2)) && r0[4];
 000240         req.flit_payload = next_rand64();
 000240         finish_item(req);
              end
            endtask
          endclass : oam_4chip_sequence
        
          // ---------------------------------------------------------------------------
          // 3. UVM Driver: oam_4chip_driver
          // ---------------------------------------------------------------------------
          class oam_4chip_driver extends uvm_driver #(oam_4chip_seq_item);
%000001     `uvm_component_utils(oam_4chip_driver)
        
            virtual mlu_4chip_allreduce_if vif;
            uvm_analysis_port #(oam_4chip_seq_item) drv_ap;
        
%000001     function new(string name, uvm_component parent);
%000001       super.new(name, parent);
%000001       drv_ap = new("drv_ap", this);
            endfunction
        
%000001     virtual function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       if (!uvm_config_db #(virtual mlu_4chip_allreduce_if)::get(this, "", "vif", vif)) begin
%000000         `uvm_fatal("NOVIF", "Virtual interface mlu_4chip_allreduce_if not found")
              end
            endfunction
%000000     virtual task run_phase(uvm_phase phase);
%000000       vif.allreduce_start <= 1'b0;
%000000       vif.allreduce_mode  <= 1'b0;
%000000       vif.local_grad      <= '0;
%000000       vif.chip_tx_valid   <= 4'b0000;
%000000       vif.chip_tx_flit    <= '0;
%000000       vif.chip_rx_ready   <= 4'b1111;
%000000       vif.link_err_inject <= 4'b0000;
        
%000000       @(posedge vif.rst_n);
%000002       repeat (2) @(posedge vif.clk);
        
 000240       forever begin
 000240         oam_4chip_seq_item req;
 000240         oam_4chip_seq_item rsp_item;
 000240         seq_item_port.get_next_item(req);
 000240         rsp_item = oam_4chip_seq_item::type_id::create("rsp_item");
 000240         rsp_item.txn_id          = req.txn_id;
 000240         rsp_item.kind            = req.kind;
 000240         rsp_item.allreduce_mode  = req.allreduce_mode;
 000240         rsp_item.err_inject_mask = req.err_inject_mask;
 000240         rsp_item.src_chip        = req.src_chip;
 000240         rsp_item.dst_chip        = req.dst_chip;
 000240         rsp_item.use_diagonal    = req.use_diagonal;
 000240         rsp_item.flit_payload    = req.flit_payload;
 000960         for (int c = 0; c < 4; c++) rsp_item.grad[c] = req.grad[c];
        
 000160         if (req.kind == TXN_RING_ALLREDUCE || req.kind == TXN_BUTTERFLY_ALLREDUCE) begin
 000160           @(posedge vif.clk);
 000160           vif.allreduce_start  <= 1'b1;
 000160           vif.allreduce_mode   <= req.allreduce_mode;
 000160           vif.local_grad[0]    <= req.grad[0];
 000160           vif.local_grad[1]    <= req.grad[1];
 000160           vif.local_grad[2]    <= req.grad[2];
 000160           vif.local_grad[3]    <= req.grad[3];
 000160           vif.link_err_inject  <= 4'b0000;
        
 000160           @(posedge vif.clk);
 000160           vif.allreduce_start  <= 1'b0;
 000160           vif.link_err_inject  <= req.err_inject_mask;
        
 000160           @(posedge vif.clk);
 000160           vif.link_err_inject  <= 4'b0000;
        
 000304           for (int w = 0; w < 12; w++) begin
 000304             #1;
~000304             if (vif.allreduce_done == 4'b1111 && !vif.allreduce_busy) break;
 000304             @(posedge vif.clk);
                  end
        
 000640           for (int c = 0; c < 4; c++) rsp_item.act_sum[c] = vif.final_allreduce_sum[c];
 000160           rsp_item.act_hops        = vif.allreduce_hops_taken;
 000160           rsp_item.act_done        = vif.allreduce_done;
 000080         end else begin
 000080           logic [3:0] dst_enc;
 000080           bit         use_c2c_west;
 000080           use_c2c_west = (req.dst_chip == 2'((req.src_chip + 2'd1) & 2'd3)) && req.txn_id[1];
 000080           dst_enc = req.use_diagonal ? {2'b10, req.dst_chip} :
                            (use_c2c_west    ? {2'b11, req.dst_chip} : {2'b00, req.dst_chip});
 000080           @(posedge vif.clk);
 000080           vif.chip_tx_valid                <= (4'b0001 << req.src_chip);
 000080           vif.chip_tx_flit[req.src_chip]   <= {2'b00, req.txn_id[0], {2'b00, req.src_chip}, dst_enc,
 000080                                                5'd0, 16'h0000, 32'h1000_0000, req.flit_payload};
 000080           vif.link_err_inject              <= 4'b0000;
        
 000080           @(posedge vif.clk);
 000080           vif.chip_tx_valid                <= 4'b0000;
 000080           vif.link_err_inject              <= req.err_inject_mask;
        
 000080           rsp_item.rx_matched = 1'b0;
 000105           for (int w = 0; w < 16; w++) begin
 000105             #1;
 000105             if (w == 1) vif.link_err_inject <= 4'b0000;
~000105             if (vif.chip_rx_valid[req.dst_chip]) begin
%000000               rsp_item.rx_matched     = 1'b1;
%000000               rsp_item.act_rx_payload = vif.chip_rx_flit[req.dst_chip][63:0];
%000000               @(posedge vif.clk);
%000000               break;
                    end
 000105             @(posedge vif.clk);
                  end
 000080           vif.link_err_inject <= 4'b0000;
                end
        
 000240         rsp_item.act_crc_errs     = vif.total_crc_errs;
 000240         rsp_item.act_retransmits  = vif.total_retransmits;
 000240         rsp_item.act_routed_flits = vif.total_routed_flits;
 000240         rsp_item.act_collectives  = vif.collective_completed_cnt;
 000240         drv_ap.write(rsp_item);
 000240         seq_item_port.item_done();
              end
            endtask
          endclass : oam_4chip_driver
          // ---------------------------------------------------------------------------
          // 4. UVM Scoreboard: oam_4chip_scoreboard
          // ---------------------------------------------------------------------------
          class oam_4chip_scoreboard extends uvm_scoreboard;
%000001     `uvm_component_utils(oam_4chip_scoreboard)
        
            uvm_analysis_imp #(oam_4chip_seq_item, oam_4chip_scoreboard) sb_export;
        
%000001     int unsigned ring_ar_pass      = 0;
%000001     int unsigned butterfly_ar_pass = 0;
%000001     int unsigned unicast_pass      = 0;
%000001     int unsigned total_fail        = 0;
%000001     int unsigned last_crc_errs     = 0;
%000001     int unsigned last_retransmits  = 0;
%000001     int unsigned last_routed       = 0;
%000001     int unsigned last_collectives  = 0;
        
%000001     function new(string name, uvm_component parent);
%000001       super.new(name, parent);
%000001       sb_export = new("sb_export", this);
            endfunction
        
 000240     virtual function void write(oam_4chip_seq_item item);
 000240       last_crc_errs    = item.act_crc_errs;
 000240       last_retransmits = item.act_retransmits;
 000240       last_routed      = item.act_routed_flits;
 000240       last_collectives = item.act_collectives;
        
 000160       if (item.kind == TXN_RING_ALLREDUCE || item.kind == TXN_BUTTERFLY_ALLREDUCE) begin
 000160         longint unsigned exp_sum = dpi_4chip_calc_allreduce_sum(
 000160           item.grad[0], item.grad[1], item.grad[2], item.grad[3], int'(item.allreduce_mode));
 000160         int unsigned exp_hops = dpi_4chip_expected_hops(int'(item.allreduce_mode));
        
%000000         if (item.act_done !== 4'b1111 || item.act_hops !== 3'(exp_hops)) begin
                  `uvm_error("OAM_SB_AR_DONE", $sformatf(
                    "Txn %0d: done=%b (exp 1111), hops=%0d (exp %0d)",
%000000             item.txn_id, item.act_done, item.act_hops, exp_hops))
%000000           total_fail++;
%000000           dpi_4chip_set_status(1);
~000160         end else if (item.act_sum[0] !== exp_sum || item.act_sum[1] !== exp_sum ||
%000000                      item.act_sum[2] !== exp_sum || item.act_sum[3] !== exp_sum) begin
                  `uvm_error("OAM_SB_AR_SUM", $sformatf(
                    "Txn %0d: sum mismatch! exp=0x%016h act=[0x%016h, 0x%016h, 0x%016h, 0x%016h]",
%000000             item.txn_id, exp_sum, item.act_sum[0], item.act_sum[1], item.act_sum[2], item.act_sum[3]))
%000000           total_fail++;
%000000           dpi_4chip_set_status(1);
 000160         end else begin
 000080           if (item.kind == TXN_RING_ALLREDUCE) ring_ar_pass++;
 000080           else butterfly_ar_pass++;
                end
 000080       end else begin
 000080         dpi_4chip_record_unicast_check();
~000080         if (!item.rx_matched || (item.act_rx_payload !== item.flit_payload)) begin
                  `uvm_error("OAM_SB_UNICAST", $sformatf(
                    "Txn %0d: src=%0d dst=%0d diag=%0b matched=%0b exp=0x%016h act=0x%016h",
                    item.txn_id, item.src_chip, item.dst_chip, item.use_diagonal,
%000000             item.rx_matched, item.flit_payload, item.act_rx_payload))
%000000           total_fail++;
%000000           dpi_4chip_set_status(1);
 000080         end else begin
 000080           unicast_pass++;
                end
              end
            endfunction
        
%000001     virtual function void report_phase(uvm_phase phase);
%000001       super.report_phase(phase);
              `uvm_info("OAM_4CHIP_SB_SUMMARY", $sformatf(
                "Suite 9 Summary: RingAR=%0d ButterflyAR=%0d Unicast=%0d Fail=%0d DPI_Calls=%0d Collectives=%0d RoutedFlits=%0d CRCErrs=%0d Retransmits=%0d",
                ring_ar_pass, butterfly_ar_pass, unicast_pass, total_fail, dpi_4chip_get_calls(),
%000001         last_collectives, last_routed, last_crc_errs, last_retransmits), UVM_LOW)
%000001       if (total_fail > 0 || ring_ar_pass == 0 || butterfly_ar_pass == 0 || unicast_pass == 0) begin
%000000         dpi_4chip_set_status(1);
              end
            endfunction
          endclass : oam_4chip_scoreboard
        
          // ---------------------------------------------------------------------------
          // 5. UVM Agent, Environment & Test
          // ---------------------------------------------------------------------------
          class oam_4chip_env extends uvm_env;
%000001     `uvm_component_utils(oam_4chip_env)
        
            uvm_sequencer #(oam_4chip_seq_item) sqr;
            oam_4chip_driver                    drv;
            oam_4chip_scoreboard                sb;
        
%000001     function new(string name, uvm_component parent);
%000001       super.new(name, parent);
            endfunction
        
%000001     virtual function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       sqr = uvm_sequencer #(oam_4chip_seq_item)::type_id::create("sqr", this);
%000001       drv = oam_4chip_driver::type_id::create("drv", this);
%000001       sb  = oam_4chip_scoreboard::type_id::create("sb", this);
            endfunction
        
%000001     virtual function void connect_phase(uvm_phase phase);
%000001       super.connect_phase(phase);
%000001       drv.seq_item_port.connect(sqr.seq_item_export);
%000001       drv.drv_ap.connect(sb.sb_export);
            endfunction
          endclass : oam_4chip_env
        
          class oam_4chip_test extends uvm_test;
%000002     `uvm_component_utils(oam_4chip_test)
        
            oam_4chip_env env;
        
%000001     function new(string name = "oam_4chip_test", uvm_component parent = null);
%000001       super.new(name, parent);
            endfunction
        
%000001     virtual function void build_phase(uvm_phase phase);
%000001       super.build_phase(phase);
%000001       env = oam_4chip_env::type_id::create("env", this);
            endfunction
        
%000001     virtual task run_phase(uvm_phase phase);
%000001       oam_4chip_sequence seq = oam_4chip_sequence::type_id::create("seq");
%000001       phase.raise_objection(this);
%000001       seq.start(env.sqr);
%000001       phase.drop_objection(this);
            endtask
          endclass : oam_4chip_test
        
        endpackage : mlu_4chip_allreduce_uvm_pkg
        
        `endif // MLU_4CHIP_ALLREDUCE_UVM_PKG_SV
        
