# Stage 17 Adversarial Mutation Testing Report (M01–M20)

- **Target Architecture**: Cambricon Siyuan 590 / 690 (`MLUarch05` / `MLUarch06` & `Cambricon-LLM/Q/S`)
- **Verification Engine**: Yosys 0.60 Formal SAT / Bounded Model Checking (`sat -verify -prove-asserts`)
- **Total Synthetic RTL Bugs Injected**: **20**
- **Mutants Killed (Counterexample Found)**: **20 / 20 (100.0%)**
- **Golden RTL Integrity**: `rtl/` and `sram_ip/` 100% Untouched (Isolated Sandbox Execution)
- **Total Campaign Wall-Clock Time**: 43.03 s

## Mutant-by-Mutant Kill Matrix

| ID | Target RTL Module | Synthetic Bug Injected | Formal Property Violated | SAT Clauses | Time (s) | Result |
|:--:|:------------------|:-----------------------|:-------------------------|------------:|---------:|:------:|
| `M01` | `mlu_sram_secded_ecc` | Flip bit 0 of H_ROW0 parity mask (8'h07 -> 8'h06) breaking Hsiao odd-weight column invariant | SECDED Property 2/3: 100% Single-Bit Correction & Double-Bit Detection | 21,158 | 0.25 | **KILLED (`FAIL` CEX)** |
| `M02` | `mlu_sram_secded_ecc` | Swap sec_err_o and ded_err_o parity classification condition | SECDED Property 2/3: SEC vs DED Syndrome Parity Classification | 21,006 | 0.25 | **KILLED (`FAIL` CEX)** |
| `M03` | `mlu_sram_sp_macro` | Disable spare-row repair address match (hit_spare_row = 1'b0) | SRAM Macro Property 1: Spare-Row Repair Remapping Invariance & Isolation | 485,740 | 1.10 | **KILLED (`FAIL` CEX)** |
| `M04` | `mlu_sram_sp_macro` | Invert pwr_ready_o during light-sleep mode (slp_i) | SRAM Macro Property 2: Low-Power Gating Safety (!pwr_ready_o on slp_i) | 512,310 | 1.22 | **KILLED (`FAIL` CEX)** |
| `M05` | `mlu_nram_banked_scratchpad` | Break XOR bank-swizzling (bank_idx = lane_idx ignoring row_addr[2:0]) | NRAM Property 1: XOR Bank-Swizzle Conflict-Free Column/Row Bijection | 5,171,136 | 20.10 | **KILLED (`FAIL` CEX)** |
| `M06` | `mlu_nram_banked_scratchpad` | Corrupt 2D matrix transpose indexing (out[r][c] = in[r][c] instead of in[c][r]) | NRAM Property 2: 8x8 Byte Matrix Transpose End-to-End Exactness | 5,138,912 | 22.35 | **KILLED (`FAIL` CEX)** |
| `M07` | `mlu_wram_weight_buffer` | Allow shadow DMA write into active ping_pong_sel_i bank | WRAM Property 3: Ping-Pong Shadow DMA Write / Active Read Isolation | 5,172,908 | 21.35 | **KILLED (`FAIL` CEX)** |
| `M08` | `mlu_mpu_shared_sram` | Mask bit 3 of bcast_valid_o (4'b0111 instead of 4'b1111) during OP_MPU_BCAST_SRAM | MPU SRAM Property 4: Multi-Cast Broadcast Consistency (4'b1111) | 5,172,896 | 18.84 | **KILLED (`FAIL` CEX)** |
| `M09` | `mlu_bang_icu` | Disable RAW hazard check on MEM_SPACE_NRAM in scoreboard | BANG ICU Property 1: Scoreboard RAW Hazard Stall on MEM_SPACE_NRAM | 386,293 | 0.90 | **KILLED (`FAIL` CEX)** |
| `M10` | `mlu_bang_icu` | Allow instruction retirement/dispatch while OP_SYNC_CLUSTER barrier is active | BANG ICU Property 2: OP_SYNC_CLUSTER Barrier Queue-Idle Interlock | 385,873 | 0.95 | **KILLED (`FAIL` CEX)** |
| `M11` | `mlu_pmu_clock_gate` | Suppress 0-cycle wakeup on icu_dispatch_mask_i | PMU Property 3: 0-Cycle Combinational Clock-Gate Wakeup on Dispatch | 386,063 | 0.95 | **KILLED (`FAIL` CEX)** |
| `M12` | `mlu_tfu_fractal_mac` | Disable zero_skip_cnt_o increment in SPARSE_BLOCK_4X4 zero-block skip | TFU Property 1: Cambricon-S SPARSE_BLOCK_4X4 Zero-Skip Telemetry Exactness | 3,624,008 | 21.09 | **KILLED (`FAIL` CEX)** |
| `M13` | `mlu_tfu_fractal_mac` | Add +1 bias bug to PREC_INT8 dot product accumulation | TFU Property 2: Multi-Precision Zero-Operand Annihilation (PREC_INT8) | 2,634,869 | 25.31 | **KILLED (`FAIL` CEX)** |
| `M14` | `mlu_tfu_fractal_mac` | Corrupt done_tag_o (tag_q ^ 8'h01) | TFU Property 3: Completion Tag Preservation (done_tag_o == expected_tag_q) | 3,653,584 | 22.16 | **KILLED (`FAIL` CEX)** |
| `M15` | `mlu_vfu_sfu_pipe` | Replace saturating OP_BANG_VADD with wrapping 16-bit addition | VFU Property 2: Saturating VADD Signed Overflow/Underflow Clamping | 340,504 | 3.30 | **KILLED (`FAIL` CEX)** |
| `M16` | `mlu_vfu_sfu_pipe` | Force softmax_sum_o to 0 on OP_BANG_SOFTMAX | VFU Property 3: Online Safe Softmax Strictly Positive Denominator (softmax_sum_o > 0) | 4,652,578 | 13.47 | **KILLED (`FAIL` CEX)** |
| `M17` | `mlu_vfu_sfu_pipe` | Swap min_val_o and max_val_o in OP_BANG_QUANT_STAT | VFU Property 4: Cambricon-Q QuantStat Ordering Invariant (min_val_o <= max_val_o) | 3,543,982 | 24.07 | **KILLED (`FAIL` CEX)** |
| `M18` | `mlu_mfu_dma_engine` | Write 8'hFF instead of 8'h00 for zero-masked bytes in OP_BANG_DECOMP_DMA | MFU DMA Property 1: Zero-Bitmap Hardware Decompression Zero-Byte Exactness | 766,757 | 1.47 | **KILLED (`FAIL` CEX)** |
| `M19` | `mlu_link_noc_router` | Invert VC priority (grant VC0 over VC1 under contention) | MLU-Link NoC Property 1: Strict VC1 Priority over VC0 under Contention | 4,998,057 | 10.17 | **KILLED (`FAIL` CEX)** |
| `M20` | `mlu_c2c_serdes_pcs` | Suppress nack_valid_o when CRC-16 check fails | MLU-Link C2C PCS Property 2: Immediate NACK Assertion on CRC-16 Fault | 6,786,105 | 12.94 | **KILLED (`FAIL` CEX)** |
