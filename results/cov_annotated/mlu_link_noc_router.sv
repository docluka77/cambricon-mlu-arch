//      // verilator_coverage annotation
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
 001135   input  logic             clk,
%000001   input  logic             rst_n,
        
          // In-Router Hardware Ring/Tree AllReduce Combiner Enable
~000049   input  logic             allreduce_en_i,
        
          // 5-Port Input Links (0: Local, 1: North, 2: South, 3: East/D2D, 4: West/C2C)
~000135   input  logic [4:0]        in_valid_i,
~000174   output logic [4:0]        in_ready_o,
          input  logic [4:0][127:0] in_flit_i,
        
          // 5-Port Output Links
~000076   output logic [4:0]        out_valid_o,
~000010   input  logic [4:0]        out_ready_i,
          output logic [4:0][127:0] out_flit_o,
        
          // Performance & QoS Telemetry Counters
~000160   output logic [31:0]       routed_flit_cnt_o,
~000067   output logic [31:0]       vc1_priority_cnt_o
        );
        
          localparam int unsigned NUM_PORTS = 5;
        
          // ---------------------------------------------------------------------------
          // 1. Deterministic Deadlock-Free Dimension-Ordered Routing Function
          // ---------------------------------------------------------------------------
 000836   function automatic logic [2:0] route_lookup(input logic [3:0] dst_id);
~000165     if (dst_id == ROUTER_ID) begin
~000165       route_lookup = 3'd0; // Port 0: Local Cluster
~000173     end else if (dst_id[3:2] == 2'b11) begin
~000173       route_lookup = 3'd4; // Port 4: West / Off-Chip MLU-Link Aperture
~000170     end else if (dst_id[3:2] == 2'b10) begin
~000170       route_lookup = 3'd3; // Port 3: East / Die-to-Die C2C Aperture
~000166     end else if (dst_id[3:2] == 2'b01) begin
~000166       route_lookup = 3'd2; // Port 2: South Intra-Die Mesh
~000162     end else begin
~000162       /* verilator lint_off CMPCONST */
~000162       if (dst_id[1:0] > ROUTER_ID[1:0]) begin
%000000       /* verilator lint_on CMPCONST */
~000024         route_lookup = 3'd1; // Port 1: North Intra-Die Mesh
~000018       end else begin
~000018         route_lookup = 3'd2; // Port 2: South Intra-Die Mesh
              end
            end
          endfunction
        
          // ---------------------------------------------------------------------------
          // 2. Per-Input-Port Dual Virtual Channel Buffers (VC0: Req, VC1: Resp/AR)
          //    mlu_noc_flit_t bit layout:
          //      [127:126] flit_type, [125] vc_id, [124:121] src_id, [120:117] dst_id,
~000092   //      [116:112] pkt_seq, [111:96] crc16_or_cmd, [95:64] addr, [63:0] payload
          // ---------------------------------------------------------------------------
~000025   logic [NUM_PORTS-1:0]         vc0_valid_q, vc1_valid_q;
 000034   logic [NUM_PORTS-1:0][127:0]  vc0_flit_q;
~000051   logic [NUM_PORTS-1:0][127:0]  vc1_flit_q;
%000005   logic [NUM_PORTS-1:0][2:0]    vc0_dst_p_q;
~000106   logic [NUM_PORTS-1:0][2:0]    vc1_dst_p_q;
 000108 
~000025   logic [NUM_PORTS-1:0]         vc0_pop, vc1_pop;
~002809   logic [NUM_PORTS-1:0]         vc0_push, vc1_push;
 014045 
 007804   always_comb begin
 009295     for (int p = 0; p < NUM_PORTS; p++) begin
 009160       if (in_valid_i[p]) begin
~003600         if (in_flit_i[p][125] == 1'b1) begin
~003600           in_ready_o[p] = !vc1_valid_q[p] || vc1_pop[p];
~000199         end else begin
~006241           in_ready_o[p] = !vc0_valid_q[p] || vc0_pop[p];
 006241         end
 009160       end else begin
 014045         in_ready_o[p] = !vc0_valid_q[p] || !vc1_valid_q[p];
 014045       end
 009295       vc0_push[p] = in_valid_i[p] && (in_flit_i[p][125] == 1'b0) && in_ready_o[p];
 009295       vc1_push[p] = in_valid_i[p] && (in_flit_i[p][125] == 1'b1) && in_ready_o[p];
            end
          end
        
          // ---------------------------------------------------------------------------
%000007   // 3. Wormhole Output Port Lock & Round-Robin Priority State
%000001   // ---------------------------------------------------------------------------
%000000   logic [NUM_PORTS-1:0]                  lock_active_q;
~000048   logic [NUM_PORTS-1:0][2:0]             lock_in_p_q;
%000000   logic [NUM_PORTS-1:0]                  lock_vc_q;
~000076   logic [NUM_PORTS-1:0][2:0]             rr_ptr_q;
 000098 
~000038   logic [NUM_PORTS-1:0]                  out_grant_v;
~000016   logic [NUM_PORTS-1:0][2:0]             out_grant_in_p;
%000002   logic [NUM_PORTS-1:0]                  out_grant_vc;
%000002   logic [NUM_PORTS-1:0][NUM_PORTS-1:0]   out_ar_combine;
          logic [NUM_PORTS-1:0][127:0]           out_flit_s;
        
          // ---------------------------------------------------------------------------
 001123   // 4. Crossbar Arbitration, Wormhole Locking & AllReduce Combiner
 001123   // ---------------------------------------------------------------------------
 001139   always_comb begin
 001139     logic [2:0]  lp;
 001139     logic [2:0]  ip_idx;
 001139     logic [2:0]  gp;
 001139     logic [63:0] sum_payload;
 001123 
 001139     vc0_pop     = '0;
 001139     vc1_pop     = '0;
 001139     lp          = 3'd0;
 001139     ip_idx      = 3'd0;
 001139     gp          = 3'd0;
 005615     sum_payload = 64'd0;
 005615 
 005695     for (int op = 0; op < NUM_PORTS; op++) begin
 005695       out_grant_v[op]    = 1'b0;
 005695       out_grant_in_p[op] = 3'd0;
 005695       out_grant_vc[op]   = 1'b0;
 005695       out_ar_combine[op] = '0;
 005695       out_flit_s[op]     = '0;
        
~005695       if (lock_active_q[op]) begin
~000782         // Wormhole Lock Active: strictly service the locked (in_p, vc)
%000000         lp = lock_in_p_q[op];
%000000         if (lock_vc_q[op]) begin
%000000           if (vc1_valid_q[lp]) begin
%000000             out_grant_v[op]    = 1'b1;
%000000             out_grant_in_p[op] = lock_in_p_q[op];
%000000             out_grant_vc[op]   = 1'b1;
%000000             out_flit_s[op]     = vc1_flit_q[lp];
~000782             if (out_ready_i[op]) vc1_pop[lp] = 1'b1;
 000577           end
~000205         end else begin
~000205           if (vc0_valid_q[lp]) begin
~000205             out_grant_v[op]    = 1'b1;
~000205             out_grant_in_p[op] = lock_in_p_q[op];
~000205             out_grant_vc[op]   = 1'b0;
%000000             out_flit_s[op]     = vc0_flit_q[lp];
%000000             if (out_ready_i[op]) vc0_pop[lp] = 1'b1;
 004833           end
                end
 024165       end else begin
 024165         // Unlocked Output Port: Arbitrate VC1 first (strict priority), then VC0
 028475         for (int off = 0; off < NUM_PORTS; off++) begin
 028475           ip_idx = (({1'b0, rr_ptr_q[op]} + {1'b0, off[2:0]}) >= 4'd5) ?
 000433                    (rr_ptr_q[op] + off[2:0] - 3'd5) : (rr_ptr_q[op] + off[2:0]);
~028475           if (!out_grant_v[op] && vc1_valid_q[ip_idx] && (vc1_dst_p_q[ip_idx] == op[2:0])) begin
~000433             out_grant_v[op]    = 1'b1;
~000433             out_grant_in_p[op] = ip_idx;
~000010             out_grant_vc[op]   = 1'b1;
~000010             out_flit_s[op]     = vc1_flit_q[ip_idx];
                  end
 004400         end
 022000         // Check VC0 only if no VC1 request matched
~022000         if (!out_grant_v[op]) begin
 028475           for (int off = 0; off < NUM_PORTS; off++) begin
 028475             ip_idx = (({1'b0, rr_ptr_q[op]} + {1'b0, off[2:0]}) >= 4'd5) ?
 000356                      (rr_ptr_q[op] + off[2:0] - 3'd5) : (rr_ptr_q[op] + off[2:0]);
~028436             if (!out_grant_v[op] && vc0_valid_q[ip_idx] && (vc0_dst_p_q[ip_idx] == op[2:0])) begin
~000356               out_grant_v[op]    = 1'b1;
~000356               out_grant_in_p[op] = ip_idx;
~000052               out_grant_vc[op]   = 1'b0;
~000052               out_flit_s[op]     = vc0_flit_q[ip_idx];
                    end
                  end
                end
 004044 
 000789         // Handle Pop and Optional In-Router Hardware AllReduce Combining
~005656         if (out_grant_v[op]) begin
~000052           gp = out_grant_in_p[op];
~000010           if (out_grant_vc[op] && allreduce_en_i &&
~000010               (out_flit_s[op][127:126] == mlu_pkg::FLIT_HEAD_TAIL)) begin
~000010             sum_payload = 64'd0;
~000050             for (int ip = 0; ip < NUM_PORTS; ip++) begin
~000040               if (vc1_valid_q[ip] && (vc1_dst_p_q[ip] == op[2:0]) &&
~000010                   (vc1_flit_q[ip][127:126] == mlu_pkg::FLIT_HEAD_TAIL)) begin
~000010                 out_ar_combine[op][ip] = 1'b1;
~000010                 sum_payload = sum_payload + vc1_flit_q[ip][63:0];
~000010                 if (out_ready_i[op]) vc1_pop[ip] = 1'b1;
%000000               end
~000788             end
~000433             out_flit_s[op][63:0] = sum_payload;
~000355           end else if (out_ready_i[op]) begin
~000052             if (out_grant_vc[op]) vc1_pop[gp] = 1'b1;
~000052             else                  vc0_pop[gp] = 1'b1;
                  end
                end
 005615       end
 005615 
 005695       out_valid_o[op] = out_grant_v[op];
 005695       out_flit_o[op]  = out_flit_s[op];
            end
          end
        
          // ---------------------------------------------------------------------------
 000804   // 5. Sequential State: VC Buffers, Wormhole Locks, RR Arbiters & Telemetry
 000804   // ---------------------------------------------------------------------------
 001135   always_ff @(posedge clk or negedge rst_n) begin
~001135     logic [31:0] add_routed;
~001135     logic [31:0] add_vc1;
~001131     if (!rst_n) begin
%000004       vc0_valid_q        <= '0;
%000004       vc1_valid_q        <= '0;
%000004       lock_active_q      <= '0;
%000004       lock_vc_q          <= '0;
~000020       routed_flit_cnt_o  <= 32'd0;
~000020       vc1_priority_cnt_o <= 32'd0;
~000020       for (int p = 0; p < NUM_PORTS; p++) begin
 000020         vc0_flit_q[p]  <= '0;
 000020         vc1_flit_q[p]  <= '0;
 000020         vc0_dst_p_q[p] <= 3'd0;
 000020         vc1_dst_p_q[p] <= 3'd0;
 000020         lock_in_p_q[p] <= 3'd0;
 000800         rr_ptr_q[p]    <= 3'd0;
              end
 004000     end else begin
 000465       // Update Input VC0 & VC1 Buffers
 005655       for (int p = 0; p < NUM_PORTS; p++) begin
~000465         if (vc0_push[p]) begin
~000398           vc0_valid_q[p] <= 1'b1;
~000398           vc0_flit_q[p]  <= in_flit_i[p];
~000398           if ((in_flit_i[p][127:126] == mlu_pkg::FLIT_HEAD) ||
~000052               (in_flit_i[p][127:126] == mlu_pkg::FLIT_HEAD_TAIL)) begin
~003296             vc0_dst_p_q[p] <= route_lookup(in_flit_i[p][120:117]);
 000239           end
~005577         end else if (vc0_pop[p]) begin
~000052           vc0_valid_q[p] <= 1'b0;
 000438         end
 000438 
~000438         if (vc1_push[p]) begin
~000438           vc1_valid_q[p] <= 1'b1;
~000438           vc1_flit_q[p]  <= in_flit_i[p];
~000438           if ((in_flit_i[p][127:126] == mlu_pkg::FLIT_HEAD) ||
~000010               (in_flit_i[p][127:126] == mlu_pkg::FLIT_HEAD_TAIL)) begin
~003279             vc1_dst_p_q[p] <= route_lookup(in_flit_i[p][120:117]);
 000283           end
~005655         end else if (vc1_pop[p]) begin
%000004           vc1_valid_q[p] <= 1'b0;
                end
              end
 000800 
 000800       // Update Wormhole Output Port Locks, Round-Robin Pointers & Counters
 004000       add_routed = 32'd0;
 003102       add_vc1    = 32'd0;
 005655       for (int op = 0; op < NUM_PORTS; op++) begin
 005616         if (out_valid_o[op] && out_ready_i[op]) begin
 000433           add_routed = add_routed + 32'd1;
~000052           if (out_grant_vc[op] || (|out_ar_combine[op])) begin
~000010             add_vc1 = add_vc1 + 32'd1;
 000777           end
 000743 
~000052           if (!lock_active_q[op]) begin
~000052             if (out_flit_s[op][127:126] == mlu_pkg::FLIT_HEAD) begin
~000034               lock_active_q[op] <= 1'b1;
%000000               lock_in_p_q[op]   <= out_grant_in_p[op];
~000777               lock_vc_q[op]     <= out_grant_vc[op];
 000121             end
 000088             rr_ptr_q[op] <= (out_grant_in_p[op] == 3'd4) ? 3'd0 : (out_grant_in_p[op] + 3'd1);
~000033           end else begin
~000033             if (out_flit_s[op][127:126] == mlu_pkg::FLIT_TAIL) begin
%000000               lock_active_q[op] <= 1'b0;
%000000               rr_ptr_q[op]      <= (lock_in_p_q[op] == 3'd4) ? 3'd0 : (lock_in_p_q[op] + 3'd1);
                    end
                  end
 000800         end
 000800       end
 001131       routed_flit_cnt_o  <= routed_flit_cnt_o  + add_routed;
 001131       vc1_priority_cnt_o <= vc1_priority_cnt_o + add_vc1;
            end
          end
        
        endmodule : mlu_link_noc_router
        
