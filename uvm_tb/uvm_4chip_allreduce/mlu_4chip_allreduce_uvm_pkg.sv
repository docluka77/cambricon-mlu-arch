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

  class oam_4chip_seq_item extends uvm_sequence_item;
    `uvm_object_utils(oam_4chip_seq_item)

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

    function new(string name = "oam_4chip_seq_item");
      super.new(name);
    endfunction
  endclass : oam_4chip_seq_item
  // ---------------------------------------------------------------------------
  // 2. UVM Sequence: oam_4chip_sequence (240 Transactions: Ring, Butterfly, Unicast + Faults)
  // ---------------------------------------------------------------------------
  class oam_4chip_sequence extends uvm_sequence #(oam_4chip_seq_item);
    `uvm_object_utils(oam_4chip_sequence)

    int unsigned     num_txns   = 240;
    longint unsigned prng_state = 64'h5906_900A_4C11_2026;

    function new(string name = "oam_4chip_sequence");
      super.new(name);
    endfunction

    function longint unsigned next_rand64();
      prng_state ^= (prng_state << 13);
      prng_state ^= (prng_state >> 7);
      prng_state ^= (prng_state << 17);
      return prng_state;
    endfunction

    virtual task body();
      for (int unsigned t = 0; t < num_txns; t++) begin
        oam_4chip_seq_item req = oam_4chip_seq_item::type_id::create($sformatf("txn_%0d", t));
        longint unsigned r0 = next_rand64();
        start_item(req);
        req.txn_id = t;

        if ((t % 3) == 0) begin
          req.kind            = TXN_RING_ALLREDUCE;
          req.allreduce_mode  = 1'b0;
        end else if ((t % 3) == 1) begin
          req.kind            = TXN_BUTTERFLY_ALLREDUCE;
          req.allreduce_mode  = 1'b1;
        end else begin
          req.kind            = TXN_UNICAST_FLIT;
          req.allreduce_mode  = 1'b0;
        end

        for (int c = 0; c < 4; c++) begin
          req.grad[c] = next_rand64();
        end

        // Inject transient C2C CRC link error on every 5th transaction
        if ((t % 5) == 4) begin
          req.err_inject_mask = 4'(1 << (t & 3));
        end else begin
          req.err_inject_mask = 4'b0000;
        end

        req.src_chip     = 2'(r0[1:0]);
        req.dst_chip     = 2'((r0[1:0] + 1 + (r0[3:2] % 3)) & 3);
        req.use_diagonal = (req.dst_chip == (req.src_chip ^ 2'd2)) && r0[4];
        req.flit_payload = next_rand64();
        finish_item(req);
      end
    endtask
  endclass : oam_4chip_sequence

  // ---------------------------------------------------------------------------
  // 3. UVM Driver: oam_4chip_driver
  // ---------------------------------------------------------------------------
  class oam_4chip_driver extends uvm_driver #(oam_4chip_seq_item);
    `uvm_component_utils(oam_4chip_driver)

    virtual mlu_4chip_allreduce_if vif;
    uvm_analysis_port #(oam_4chip_seq_item) drv_ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      drv_ap = new("drv_ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(virtual mlu_4chip_allreduce_if)::get(this, "", "vif", vif)) begin
        `uvm_fatal("NOVIF", "Virtual interface mlu_4chip_allreduce_if not found")
      end
    endfunction
    virtual task run_phase(uvm_phase phase);
      vif.allreduce_start <= 1'b0;
      vif.allreduce_mode  <= 1'b0;
      vif.local_grad      <= '0;
      vif.chip_tx_valid   <= 4'b0000;
      vif.chip_tx_flit    <= '0;
      vif.chip_rx_ready   <= 4'b1111;
      vif.link_err_inject <= 4'b0000;

      @(posedge vif.rst_n);
      repeat (2) @(posedge vif.clk);

      forever begin
        oam_4chip_seq_item req;
        oam_4chip_seq_item rsp_item;
        seq_item_port.get_next_item(req);
        rsp_item = oam_4chip_seq_item::type_id::create("rsp_item");
        rsp_item.txn_id          = req.txn_id;
        rsp_item.kind            = req.kind;
        rsp_item.allreduce_mode  = req.allreduce_mode;
        rsp_item.err_inject_mask = req.err_inject_mask;
        rsp_item.src_chip        = req.src_chip;
        rsp_item.dst_chip        = req.dst_chip;
        rsp_item.use_diagonal    = req.use_diagonal;
        rsp_item.flit_payload    = req.flit_payload;
        for (int c = 0; c < 4; c++) rsp_item.grad[c] = req.grad[c];

        if (req.kind == TXN_RING_ALLREDUCE || req.kind == TXN_BUTTERFLY_ALLREDUCE) begin
          @(posedge vif.clk);
          vif.allreduce_start  <= 1'b1;
          vif.allreduce_mode   <= req.allreduce_mode;
          vif.local_grad[0]    <= req.grad[0];
          vif.local_grad[1]    <= req.grad[1];
          vif.local_grad[2]    <= req.grad[2];
          vif.local_grad[3]    <= req.grad[3];
          vif.link_err_inject  <= 4'b0000;

          @(posedge vif.clk);
          vif.allreduce_start  <= 1'b0;
          vif.link_err_inject  <= req.err_inject_mask;

          @(posedge vif.clk);
          vif.link_err_inject  <= 4'b0000;

          for (int w = 0; w < 12; w++) begin
            #1;
            if (vif.allreduce_done == 4'b1111 && !vif.allreduce_busy) break;
            @(posedge vif.clk);
          end

          for (int c = 0; c < 4; c++) rsp_item.act_sum[c] = vif.final_allreduce_sum[c];
          rsp_item.act_hops        = vif.allreduce_hops_taken;
          rsp_item.act_done        = vif.allreduce_done;
        end else begin
          logic [3:0] dst_enc;
          dst_enc = req.use_diagonal ? {2'b10, req.dst_chip} : {2'b00, req.dst_chip};
          @(posedge vif.clk);
          vif.chip_tx_valid                <= (4'b0001 << req.src_chip);
          vif.chip_tx_flit[req.src_chip]   <= {2'b00, 1'b0, {2'b00, req.src_chip}, dst_enc,
                                               5'd0, 16'h0000, 32'h1000_0000, req.flit_payload};
          vif.link_err_inject              <= 4'b0000;

          @(posedge vif.clk);
          vif.chip_tx_valid                <= 4'b0000;
          vif.link_err_inject              <= req.err_inject_mask;

          rsp_item.rx_matched = 1'b0;
          for (int w = 0; w < 16; w++) begin
            #1;
            if (w == 1) vif.link_err_inject <= 4'b0000;
            if (vif.chip_rx_valid[req.dst_chip]) begin
              rsp_item.rx_matched     = 1'b1;
              rsp_item.act_rx_payload = vif.chip_rx_flit[req.dst_chip][63:0];
              @(posedge vif.clk);
              break;
            end
            @(posedge vif.clk);
          end
          vif.link_err_inject <= 4'b0000;
        end

        rsp_item.act_crc_errs     = vif.total_crc_errs;
        rsp_item.act_retransmits  = vif.total_retransmits;
        rsp_item.act_routed_flits = vif.total_routed_flits;
        rsp_item.act_collectives  = vif.collective_completed_cnt;
        drv_ap.write(rsp_item);
        seq_item_port.item_done();
      end
    endtask
  endclass : oam_4chip_driver
  // ---------------------------------------------------------------------------
  // 4. UVM Scoreboard: oam_4chip_scoreboard
  // ---------------------------------------------------------------------------
  class oam_4chip_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(oam_4chip_scoreboard)

    uvm_analysis_imp #(oam_4chip_seq_item, oam_4chip_scoreboard) sb_export;

    int unsigned ring_ar_pass      = 0;
    int unsigned butterfly_ar_pass = 0;
    int unsigned unicast_pass      = 0;
    int unsigned total_fail        = 0;
    int unsigned last_crc_errs     = 0;
    int unsigned last_retransmits  = 0;
    int unsigned last_routed       = 0;
    int unsigned last_collectives  = 0;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      sb_export = new("sb_export", this);
    endfunction

    virtual function void write(oam_4chip_seq_item item);
      last_crc_errs    = item.act_crc_errs;
      last_retransmits = item.act_retransmits;
      last_routed      = item.act_routed_flits;
      last_collectives = item.act_collectives;

      if (item.kind == TXN_RING_ALLREDUCE || item.kind == TXN_BUTTERFLY_ALLREDUCE) begin
        longint unsigned exp_sum = dpi_4chip_calc_allreduce_sum(
          item.grad[0], item.grad[1], item.grad[2], item.grad[3], int'(item.allreduce_mode));
        int unsigned exp_hops = dpi_4chip_expected_hops(int'(item.allreduce_mode));

        if (item.act_done !== 4'b1111 || item.act_hops !== 3'(exp_hops)) begin
          `uvm_error("OAM_SB_AR_DONE", $sformatf(
            "Txn %0d: done=%b (exp 1111), hops=%0d (exp %0d)",
            item.txn_id, item.act_done, item.act_hops, exp_hops))
          total_fail++;
          dpi_4chip_set_status(1);
        end else if (item.act_sum[0] !== exp_sum || item.act_sum[1] !== exp_sum ||
                     item.act_sum[2] !== exp_sum || item.act_sum[3] !== exp_sum) begin
          `uvm_error("OAM_SB_AR_SUM", $sformatf(
            "Txn %0d: sum mismatch! exp=0x%016h act=[0x%016h, 0x%016h, 0x%016h, 0x%016h]",
            item.txn_id, exp_sum, item.act_sum[0], item.act_sum[1], item.act_sum[2], item.act_sum[3]))
          total_fail++;
          dpi_4chip_set_status(1);
        end else begin
          if (item.kind == TXN_RING_ALLREDUCE) ring_ar_pass++;
          else butterfly_ar_pass++;
        end
      end else begin
        dpi_4chip_record_unicast_check();
        if (!item.rx_matched || (item.act_rx_payload !== item.flit_payload)) begin
          `uvm_error("OAM_SB_UNICAST", $sformatf(
            "Txn %0d: src=%0d dst=%0d diag=%0b matched=%0b exp=0x%016h act=0x%016h",
            item.txn_id, item.src_chip, item.dst_chip, item.use_diagonal,
            item.rx_matched, item.flit_payload, item.act_rx_payload))
          total_fail++;
          dpi_4chip_set_status(1);
        end else begin
          unicast_pass++;
        end
      end
    endfunction

    virtual function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("OAM_4CHIP_SB_SUMMARY", $sformatf(
        "Suite 9 Summary: RingAR=%0d ButterflyAR=%0d Unicast=%0d Fail=%0d DPI_Calls=%0d Collectives=%0d RoutedFlits=%0d CRCErrs=%0d Retransmits=%0d",
        ring_ar_pass, butterfly_ar_pass, unicast_pass, total_fail, dpi_4chip_get_calls(),
        last_collectives, last_routed, last_crc_errs, last_retransmits), UVM_LOW)
      if (total_fail > 0 || ring_ar_pass == 0 || butterfly_ar_pass == 0 || unicast_pass == 0) begin
        dpi_4chip_set_status(1);
      end
    endfunction
  endclass : oam_4chip_scoreboard

  // ---------------------------------------------------------------------------
  // 5. UVM Agent, Environment & Test
  // ---------------------------------------------------------------------------
  class oam_4chip_env extends uvm_env;
    `uvm_component_utils(oam_4chip_env)

    uvm_sequencer #(oam_4chip_seq_item) sqr;
    oam_4chip_driver                    drv;
    oam_4chip_scoreboard                sb;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      sqr = uvm_sequencer #(oam_4chip_seq_item)::type_id::create("sqr", this);
      drv = oam_4chip_driver::type_id::create("drv", this);
      sb  = oam_4chip_scoreboard::type_id::create("sb", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
      drv.drv_ap.connect(sb.sb_export);
    endfunction
  endclass : oam_4chip_env

  class oam_4chip_test extends uvm_test;
    `uvm_component_utils(oam_4chip_test)

    oam_4chip_env env;

    function new(string name = "oam_4chip_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = oam_4chip_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
      oam_4chip_sequence seq = oam_4chip_sequence::type_id::create("seq");
      phase.raise_objection(this);
      seq.start(env.sqr);
      phase.drop_objection(this);
    endtask
  endclass : oam_4chip_test

endpackage : mlu_4chip_allreduce_uvm_pkg

`endif // MLU_4CHIP_ALLREDUCE_UVM_PKG_SV
