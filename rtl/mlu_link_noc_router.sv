// =============================================================================
// File: rtl/mlu_link_noc_router.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Cambricon MLU-Link 5-Port (Local, N, S, E/D2D, W/MLU-Link)
//              128-bit Coherent Packetized NoC Router with Dual Virtual Channels
//              (VC0 Req/DMA, VC1 Resp/AllReduce), Wormhole Packet Lock, Credit
//              Flow Control, and In-Router Hardware AllReduce Combiner.
// =============================================================================
`include "mlu_pkg.sv"

module mlu_link_noc_router #(
  parameter logic [3:0] ROUTER_ID = 4'd0
) (
  input  logic             clk,
  input  logic             rst_n,

  // In-Router Hardware Ring/Tree AllReduce Combiner Enable
  input  logic             allreduce_en_i,

  // 5-Port Input Links (0: Local, 1: North, 2: South, 3: East/D2D, 4: West/C2C)
  input  logic [4:0]        in_valid_i,
  output logic [4:0]        in_ready_o,
  input  logic [4:0][127:0] in_flit_i,

  // 5-Port Output Links
  output logic [4:0]        out_valid_o,
  input  logic [4:0]        out_ready_i,
  output logic [4:0][127:0] out_flit_o,

  // Performance & QoS Telemetry Counters
  output logic [31:0]       routed_flit_cnt_o,
  output logic [31:0]       vc1_priority_cnt_o
);

  localparam int unsigned NUM_PORTS = 5;

  // ---------------------------------------------------------------------------
  // 1. Deterministic Deadlock-Free Dimension-Ordered Routing Function
  // ---------------------------------------------------------------------------
  function automatic logic [2:0] route_lookup(input logic [3:0] dst_id);
    if (dst_id == ROUTER_ID) begin
      route_lookup = 3'd0; // Port 0: Local Cluster
    end else if (dst_id[3:2] == 2'b11) begin
      route_lookup = 3'd4; // Port 4: West / Off-Chip MLU-Link Aperture
    end else if (dst_id[3:2] == 2'b10) begin
      route_lookup = 3'd3; // Port 3: East / Die-to-Die C2C Aperture
    end else if (dst_id[3:2] == 2'b01) begin
      route_lookup = 3'd2; // Port 2: South Intra-Die Mesh
    end else begin
      /* verilator lint_off CMPCONST */
      if (dst_id[1:0] > ROUTER_ID[1:0]) begin
      /* verilator lint_on CMPCONST */
        route_lookup = 3'd1; // Port 1: North Intra-Die Mesh
      end else begin
        route_lookup = 3'd2; // Port 2: South Intra-Die Mesh
      end
    end
  endfunction

  // ---------------------------------------------------------------------------
  // 2. Per-Input-Port Dual Virtual Channel Buffers (VC0: Req, VC1: Resp/AR)
  //    mlu_noc_flit_t bit layout:
  //      [127:126] flit_type, [125] vc_id, [124:121] src_id, [120:117] dst_id,
  //      [116:112] pkt_seq, [111:96] crc16_or_cmd, [95:64] addr, [63:0] payload
  // ---------------------------------------------------------------------------
  logic [NUM_PORTS-1:0]         vc0_valid_q, vc1_valid_q;
  logic [NUM_PORTS-1:0][127:0]  vc0_flit_q;
  logic [NUM_PORTS-1:0][127:0]  vc1_flit_q;
  logic [NUM_PORTS-1:0][2:0]    vc0_dst_p_q;
  logic [NUM_PORTS-1:0][2:0]    vc1_dst_p_q;

  logic [NUM_PORTS-1:0]         vc0_pop, vc1_pop;
  logic [NUM_PORTS-1:0]         vc0_push, vc1_push;

  always_comb begin
    for (int p = 0; p < NUM_PORTS; p++) begin
      if (in_valid_i[p]) begin
        if (in_flit_i[p][125] == 1'b1) begin
          in_ready_o[p] = !vc1_valid_q[p] || vc1_pop[p];
        end else begin
          in_ready_o[p] = !vc0_valid_q[p] || vc0_pop[p];
        end
      end else begin
        in_ready_o[p] = !vc0_valid_q[p] || !vc1_valid_q[p];
      end
      vc0_push[p] = in_valid_i[p] && (in_flit_i[p][125] == 1'b0) && in_ready_o[p];
      vc1_push[p] = in_valid_i[p] && (in_flit_i[p][125] == 1'b1) && in_ready_o[p];
    end
  end

  // ---------------------------------------------------------------------------
  // 3. Wormhole Output Port Lock & Round-Robin Priority State
  // ---------------------------------------------------------------------------
  logic [NUM_PORTS-1:0]                  lock_active_q;
  logic [NUM_PORTS-1:0][2:0]             lock_in_p_q;
  logic [NUM_PORTS-1:0]                  lock_vc_q;
  logic [NUM_PORTS-1:0][2:0]             rr_ptr_q;

  logic [NUM_PORTS-1:0]                  out_grant_v;
  logic [NUM_PORTS-1:0][2:0]             out_grant_in_p;
  logic [NUM_PORTS-1:0]                  out_grant_vc;
  logic [NUM_PORTS-1:0][NUM_PORTS-1:0]   out_ar_combine;
  logic [NUM_PORTS-1:0][127:0]           out_flit_s;

  // ---------------------------------------------------------------------------
  // 4. Crossbar Arbitration, Wormhole Locking & AllReduce Combiner
  // ---------------------------------------------------------------------------
  always_comb begin
    logic [2:0]  lp;
    logic [2:0]  ip_idx;
    logic [2:0]  gp;
    logic [63:0] sum_payload;

    vc0_pop     = '0;
    vc1_pop     = '0;
    lp          = 3'd0;
    ip_idx      = 3'd0;
    gp          = 3'd0;
    sum_payload = 64'd0;

    for (int op = 0; op < NUM_PORTS; op++) begin
      out_grant_v[op]    = 1'b0;
      out_grant_in_p[op] = 3'd0;
      out_grant_vc[op]   = 1'b0;
      out_ar_combine[op] = '0;
      out_flit_s[op]     = '0;

      if (lock_active_q[op]) begin
        // Wormhole Lock Active: strictly service the locked (in_p, vc)
        lp = lock_in_p_q[op];
        if (lock_vc_q[op]) begin
          if (vc1_valid_q[lp]) begin
            out_grant_v[op]    = 1'b1;
            out_grant_in_p[op] = lock_in_p_q[op];
            out_grant_vc[op]   = 1'b1;
            out_flit_s[op]     = vc1_flit_q[lp];
            if (out_ready_i[op]) vc1_pop[lp] = 1'b1;
          end
        end else begin
          if (vc0_valid_q[lp]) begin
            out_grant_v[op]    = 1'b1;
            out_grant_in_p[op] = lock_in_p_q[op];
            out_grant_vc[op]   = 1'b0;
            out_flit_s[op]     = vc0_flit_q[lp];
            if (out_ready_i[op]) vc0_pop[lp] = 1'b1;
          end
        end
      end else begin
        // Unlocked Output Port: Arbitrate VC1 first (strict priority), then VC0
        for (int off = 0; off < NUM_PORTS; off++) begin
          ip_idx = (({1'b0, rr_ptr_q[op]} + {1'b0, off[2:0]}) >= 4'd5) ?
                   (rr_ptr_q[op] + off[2:0] - 3'd5) : (rr_ptr_q[op] + off[2:0]);
          if (!out_grant_v[op] && vc1_valid_q[ip_idx] && (vc1_dst_p_q[ip_idx] == op[2:0])) begin
            out_grant_v[op]    = 1'b1;
            out_grant_in_p[op] = ip_idx;
            out_grant_vc[op]   = 1'b1;
            out_flit_s[op]     = vc1_flit_q[ip_idx];
          end
        end
        // Check VC0 only if no VC1 request matched
        if (!out_grant_v[op]) begin
          for (int off = 0; off < NUM_PORTS; off++) begin
            ip_idx = (({1'b0, rr_ptr_q[op]} + {1'b0, off[2:0]}) >= 4'd5) ?
                     (rr_ptr_q[op] + off[2:0] - 3'd5) : (rr_ptr_q[op] + off[2:0]);
            if (!out_grant_v[op] && vc0_valid_q[ip_idx] && (vc0_dst_p_q[ip_idx] == op[2:0])) begin
              out_grant_v[op]    = 1'b1;
              out_grant_in_p[op] = ip_idx;
              out_grant_vc[op]   = 1'b0;
              out_flit_s[op]     = vc0_flit_q[ip_idx];
            end
          end
        end

        // Handle Pop and Optional In-Router Hardware AllReduce Combining
        if (out_grant_v[op]) begin
          gp = out_grant_in_p[op];
          if (out_grant_vc[op] && allreduce_en_i &&
              (out_flit_s[op][127:126] == mlu_pkg::FLIT_HEAD_TAIL)) begin
            sum_payload = 64'd0;
            for (int ip = 0; ip < NUM_PORTS; ip++) begin
              if (vc1_valid_q[ip] && (vc1_dst_p_q[ip] == op[2:0]) &&
                  (vc1_flit_q[ip][127:126] == mlu_pkg::FLIT_HEAD_TAIL)) begin
                out_ar_combine[op][ip] = 1'b1;
                sum_payload = sum_payload + vc1_flit_q[ip][63:0];
                if (out_ready_i[op]) vc1_pop[ip] = 1'b1;
              end
            end
            out_flit_s[op][63:0] = sum_payload;
          end else if (out_ready_i[op]) begin
            if (out_grant_vc[op]) vc1_pop[gp] = 1'b1;
            else                  vc0_pop[gp] = 1'b1;
          end
        end
      end

      out_valid_o[op] = out_grant_v[op];
      out_flit_o[op]  = out_flit_s[op];
    end
  end

  // ---------------------------------------------------------------------------
  // 5. Sequential State: VC Buffers, Wormhole Locks, RR Arbiters & Telemetry
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    logic [31:0] add_routed;
    logic [31:0] add_vc1;
    if (!rst_n) begin
      vc0_valid_q        <= '0;
      vc1_valid_q        <= '0;
      lock_active_q      <= '0;
      lock_vc_q          <= '0;
      routed_flit_cnt_o  <= 32'd0;
      vc1_priority_cnt_o <= 32'd0;
      for (int p = 0; p < NUM_PORTS; p++) begin
        vc0_flit_q[p]  <= '0;
        vc1_flit_q[p]  <= '0;
        vc0_dst_p_q[p] <= 3'd0;
        vc1_dst_p_q[p] <= 3'd0;
        lock_in_p_q[p] <= 3'd0;
        rr_ptr_q[p]    <= 3'd0;
      end
    end else begin
      // Update Input VC0 & VC1 Buffers
      for (int p = 0; p < NUM_PORTS; p++) begin
        if (vc0_push[p]) begin
          vc0_valid_q[p] <= 1'b1;
          vc0_flit_q[p]  <= in_flit_i[p];
          if ((in_flit_i[p][127:126] == mlu_pkg::FLIT_HEAD) ||
              (in_flit_i[p][127:126] == mlu_pkg::FLIT_HEAD_TAIL)) begin
            vc0_dst_p_q[p] <= route_lookup(in_flit_i[p][120:117]);
          end
        end else if (vc0_pop[p]) begin
          vc0_valid_q[p] <= 1'b0;
        end

        if (vc1_push[p]) begin
          vc1_valid_q[p] <= 1'b1;
          vc1_flit_q[p]  <= in_flit_i[p];
          if ((in_flit_i[p][127:126] == mlu_pkg::FLIT_HEAD) ||
              (in_flit_i[p][127:126] == mlu_pkg::FLIT_HEAD_TAIL)) begin
            vc1_dst_p_q[p] <= route_lookup(in_flit_i[p][120:117]);
          end
        end else if (vc1_pop[p]) begin
          vc1_valid_q[p] <= 1'b0;
        end
      end

      // Update Wormhole Output Port Locks, Round-Robin Pointers & Counters
      add_routed = 32'd0;
      add_vc1    = 32'd0;
      for (int op = 0; op < NUM_PORTS; op++) begin
        if (out_valid_o[op] && out_ready_i[op]) begin
          add_routed = add_routed + 32'd1;
          if (out_grant_vc[op] || (|out_ar_combine[op])) begin
            add_vc1 = add_vc1 + 32'd1;
          end

          if (!lock_active_q[op]) begin
            if (out_flit_s[op][127:126] == mlu_pkg::FLIT_HEAD) begin
              lock_active_q[op] <= 1'b1;
              lock_in_p_q[op]   <= out_grant_in_p[op];
              lock_vc_q[op]     <= out_grant_vc[op];
            end
            rr_ptr_q[op] <= (out_grant_in_p[op] == 3'd4) ? 3'd0 : (out_grant_in_p[op] + 3'd1);
          end else begin
            if (out_flit_s[op][127:126] == mlu_pkg::FLIT_TAIL) begin
              lock_active_q[op] <= 1'b0;
              rr_ptr_q[op]      <= (lock_in_p_q[op] == 3'd4) ? 3'd0 : (lock_in_p_q[op] + 3'd1);
            end
          end
        end
      end
      routed_flit_cnt_o  <= routed_flit_cnt_o  + add_routed;
      vc1_priority_cnt_o <= vc1_priority_cnt_o + add_vc1;
    end
  end

endmodule : mlu_link_noc_router
