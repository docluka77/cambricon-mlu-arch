# Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06) — Comprehensive UVM & Soak Coverage Closure Report

## 1. Executive Summary & Verification Methodology

This report documents the end-to-end functional, code (line), and signal toggle coverage closure across all **16 synthesizable SystemVerilog RTL modules** (`rtl/*.sv`, `sram_ip/*.sv`) and **10 Accellera UVM-2020.3.1 + DPI-C Golden Co-Simulation Verification Suites** (`uvm_tb/uvm_*`), complemented by the **500,000-cycle full-chip randomized soak stress test** (`uvm_tb/uvm_soak_500k`).

All 10 per-suite Verilator 5.054 coverage databases (`uvm_tb/uvm_*/coverage.dat`) were merged and annotated using:
```bash
verilator_coverage --write results/merged_uvm_coverage.dat \
                   --write-info results/merged_uvm_coverage.info \
                   uvm_tb/uvm_*/coverage.dat
verilator_coverage --annotate results/cov_annotated results/merged_uvm_coverage.dat
```

### Headline Coverage Closure Metrics
| Coverage Metric Category | Covered / Total | Closure Rate | Verification Scope & Notes |
|---|---:|---:|---|
| **UVM Functional Covergroup Bins** | **`150 / 150`** | **`100.00%`** | 100% cross/bin closure across all UVM suites (`covergroup`) |
| **Unique RTL Source Line Coverage (16 Modules)** | **`469 / 507`** | **`92.50%`** | Deduplicated executable SV statements across all 16 RTL modules |
| **UVM Testbench Top & Interface Line Coverage** | **`202 / 202`** | **`100.00%`** | 100% across all 10 `tb_*_top.sv` and `mlu_*_if.sv` files |
| **UVM Package Sequence/Scoreboard Unique Lines** | **`732 / 812`** | **`90.15%`** | Active UVM sequences, drivers, monitors, and DPI-C scoreboards |
| **Instance-Weighted RTL Line Points** | **`1,741 / 2,358`** | **`73.83%`** | Includes all parameterized SRAM/IPU sub-instances inside Cluster/Chip |
| **Global Merged Line Pts (incl. UVM-2020.3.1 Base Lib)** | **`12,656 / 45,646`** | **`27.73%`** | Denominator includes ~33,000 lines of unused Accellera UVM base library (`uvm_reg_*`, etc.) |
| **Global Merged Signal Toggle Coverage** | **`73,674 / 199,218`** | **`36.98%`** | Leaf/compute/link IPs reach **64.0%–86.8%** toggle closure |
| **DPI-C Bit-Exact Co-Simulation Mismatches** | **`0`** | **`100% PASS`** | Zero mismatches across 5,500+ UVM transactions & 500,000 soak cycles |

---

## 2. Per-Suite UVM Verification & Coverage Summary (10 UVM Suites + 500K Soak)

| Suite # | UVM Suite Directory | Target DUT / Subsystem | Sim Cycles / Txns | Raw `coverage.dat` Line Pts | Raw `coverage.dat` Toggle Pts | Covergroup Bins | Key Verified Architectural Transactions & Telemetry | Status |
|:-:|---|---|---|---:|---:|---:|---|:---:|
| 1 | `uvm_sram_nram_wram` | `mlu_sram_sp_macro`, `mlu_nram_banked_scratchpad`, `mlu_wram_weight_buffer`, `mlu_mpu_shared_sram` | 1,200 cyc / 1,200 DPI calls | 5,220 / 27,592 (18.9%) | 6,624 / 18,354 (36.1%) | **20 / 20 (100.0%)** | `sec=467`, `ded=466`, `bist=1`, `repair=1`, `swiz=50`, `xpose=1`, `wram=67`, `bcast=19`, `atomic=1` | **`PASS`** |
| 2 | `uvm_bang_icu_pmu` | `mlu_bang_icu`, `mlu_pmu_clock_gate` | 1,200 cyc / 1,200 DPI calls | 5,049 / 27,341 (18.5%) | 1,580 / 3,990 (39.6%) | **14 / 14 (100.0%)** | `hazard_stalls=211`, `cluster_syncs=10`, `wakeups=462`, `retired=322`, `gated_saved=4,816` | **`PASS`** |
| 3 | `uvm_tfu_sparse_quant` | `mlu_tfu_fractal_mac` (INT4/INT8/FP8/BF16/FP16 + 2:4 Sparse) | 1,200 cyc / 200 tiles | 4,999 / 27,289 (18.3%) | 4,405 / 5,628 (78.3%) | **16 / 16 (100.0%)** | `tiles=200`, `zero_skips=100`, `total_mac_ops=18,608`, 100% bit-exact vs. C++17 golden | **`PASS`** |
| 4 | `uvm_vfu_llm_ops` | `mlu_vfu_sfu_pipe` (LayerNorm/RMSNorm/RoPE/Softmax/GELU) | 1,685 cyc / 560 txns | 4,992 / 27,294 (18.3%) | 5,169 / 6,662 (77.6%) | **11 / 11 (100.0%)** | `560` VFU/LLM nonlinear vector transactions verified bit-exact via DPI-C | **`PASS`** |
| 5 | `uvm_mfu_dma_decomp` | `mlu_mfu_dma_engine` (3D Strided DMA +LZ4/Zstd RLE Decomp) | 1,100 cyc / 320 cmds | 4,964 / 27,256 (18.2%) | 2,355 / 3,460 (68.1%) | **9 / 9 (100.0%)** | `320` DMA commands (`978` beats), 2:4 zero-page skip & RLE expansion verified | **`PASS`** |
| 6 | `uvm_mlu_link_noc` | `mlu_link_noc_router`, `mlu_c2c_serdes_pcs` | 800 cyc / 898 flits | 5,032 / 27,336 (18.4%) | 3,061 / 3,676 (83.3%) | **17 / 17 (100.0%)** | `898` routed flits, `433` VC1 priority grants, `40` CRC-16 faults & `40` Go-Back-N replays | **`PASS`** |
| 7 | `uvm_mtp_cluster` | `mlu_mtp_cluster` (4x `mlu_ipu_core` + `mlu_mpu_core`) | 600 cyc / 4-IPU cluster | 5,466 / 27,888 (19.6%) | 19,345 / 68,126 (28.4%) | **18 / 18 (100.0%)** | `bcast=2`, `allred_flits=4`, `gdram_reqs=12`, `barriers=2`, `retired=25`, `mac_ops=1,216`, `gated_cycs=11,438` | **`PASS`** |
| 8 | `uvm_mlu_chip_top` | `mlu_chip_top` (MTP Cluster + NoC Router + C2C SerDes PCS) | 600 cyc / Full-Chip | 5,549 / 28,014 (19.8%) | 20,645 / 74,592 (27.7%) | **22 / 22 (100.0%)** | `bcast=2`, `allred=2`, `routed=10`, `crc_err=1`, `retx=1`, `barriers=1`, `retired=25`, `mac_ops=1,168` | **`PASS`** |
| 9 | `uvm_4chip_allreduce` | `mlu_4chip_oam_node` (4-Chip MLU-Link Ring/Butterfly Mesh) | 567 cyc / 400 DPI calls | 5,075 / 27,430 (18.5%) | 5,894 / 9,038 (65.2%) | All 3 Topologies | `RingAR=80`, `ButterflyAR=80`, `Unicast=80`, `Collectives=160`, `RoutedFlits=182`, `CRCErrs=34`, `Retx=34` | **`PASS`** |
| 10 | `uvm_cambricon_llm_kv` | `mlu_cambricon_llm_flash_kv` (INT4/FP8 KV Pack + Spec-Tree) | 620 cyc / 300 txns | 4,957 / 27,265 (18.2%) | 4,596 / 5,692 (80.7%) | **23 / 23 (100.0%)** | `checked_txns=300` (`kv_pack=150`, `spec_verify=150`), `mismatches=0`, `func_cov=100.00%` | **`PASS`** |
| 11 | `uvm_soak_500k` | `mlu_chip_top` (Stage 17 Long-Horizon Full-Chip Soak Stress) | **500,000 cycles** (99.96 kHz) | Covered via Suite 8 Top | Covered via Suite 8 Top | **4,998 Random Epochs** | `99,960` retired insts, `559,280` MACs, `4,998` barriers, `479,887` flits, `16,025` replays, `2,499` ECC | **`PASS`** |

---

## 3. Per-Module RTL Line & Signal Toggle Coverage Breakdown (`results/merged_uvm_coverage.dat`)

The table below separates our **16 synthesizable SystemVerilog RTL modules** (`rtl/*.sv`, `sram_ip/*.sv`) from the UVM-2020.3.1 base library (`uvm-core-2020.3.1/src/**/*.svh`, which accounts for ~33,000 unexercised base framework lines in the global LCOV file). For parameterized modules instantiated multiple times across `mlu_ipu_core`, `mlu_mtp_cluster`, and `mlu_chip_top`, both **Unique Source Line Coverage** (deduplicated by source file line number in `results/merged_uvm_coverage.info`) and **Instance-Weighted Line Points** are reported.

| # | RTL Module File | Subsystem | Unique Source Lines Covered | Instance-Weighted Line Pts | Signal Toggle Points Covered | Primary Exercising UVM Suite(s) |
|:-:|---|---|---:|---:|---:|---|
| 1 | `mlu_sram_secded_ecc.sv` | SRAM IP | **`6 / 6 (100.0%)`** | `24 / 24 (100.0%)` | **`2,772 / 3,192 (86.8%)`** | `uvm_sram_nram_wram`, `uvm_mtp_cluster`, `uvm_mlu_chip_top` |
| 2 | `mlu_sram_sp_macro.sv` | SRAM IP | **`50 / 53 (94.3%)`** | `225 / 450 (50.0%)` | **`4,908 / 9,450 (51.9%)`** | `uvm_sram_nram_wram` (BIST, Repair, Scrub, Sleep) |
| 3 | `mlu_nram_banked_scratchpad.sv` | Memory Subsys | **`21 / 21 (100.0%)`** | `77 / 81 (95.1%)` | `1,818 / 7,560 (24.0%)` | `uvm_sram_nram_wram` (XOR Swizzle, 8x8 Transpose, Conflict) |
| 4 | `mlu_wram_weight_buffer.sv` | Memory Subsys | **`8 / 8 (100.0%)`** | `33 / 36 (91.7%)` | `1,743 / 8,646 (20.2%)` | `uvm_sram_nram_wram`, `uvm_mtp_cluster` (Ping-Pong Stream) |
| 5 | `mlu_mpu_shared_sram.sv` | Memory Subsys | **`15 / 15 (100.0%)`** | `56 / 63 (88.9%)` | `1,350 / 11,970 (11.3%)` | `uvm_sram_nram_wram`, `uvm_mtp_cluster` (1-to-4 Bcast, Atomic) |
| 6 | `mlu_bang_icu.sv` | Control / ISA | **`36 / 37 (97.3%)`** | `146 / 165 (88.5%)` | `1,490 / 7,116 (20.9%)` | `uvm_bang_icu_pmu`, `uvm_mtp_cluster`, `uvm_mlu_chip_top` |
| 7 | `mlu_pmu_clock_gate.sv` | Power / Clock | **`21 / 21 (100.0%)`** | `87 / 93 (93.5%)` | **`816 / 1,776 (45.9%)`** | `uvm_bang_icu_pmu`, `uvm_mtp_cluster`, `uvm_mlu_chip_top` |
| 8 | `mlu_tfu_fractal_mac.sv` | Tensor Compute | **`47 / 48 (97.9%)`** | `146 / 189 (77.2%)` | **`6,834 / 10,674 (64.0%)`** | `uvm_tfu_sparse_quant`, `uvm_mtp_cluster`, `uvm_mlu_chip_top` |
| 9 | `mlu_vfu_sfu_pipe.sv` | Vector / SFU | **`59 / 68 (86.8%)`** | `184 / 252 (73.0%)` | **`5,679 / 12,306 (46.1%)`** | `uvm_vfu_llm_ops`, `uvm_mtp_cluster`, `uvm_mlu_chip_top` |
| 10 | `mlu_mfu_dma_engine.sv` | DMA / Decomp | **`28 / 29 (96.6%)`** | `105 / 120 (87.5%)` | `2,035 / 5,604 (36.3%)` | `uvm_mfu_dma_decomp`, `uvm_mtp_cluster`, `uvm_mlu_chip_top` |
| 11 | `mlu_link_noc_router.sv` | Interconnect | **`72 / 83 (86.7%)`** | `259 / 444 (58.3%)` | `727 / 2,844 (25.6%)` | `uvm_mlu_link_noc`, `uvm_mlu_chip_top`, `uvm_4chip_allreduce` |
| 12 | `mlu_c2c_serdes_pcs.sv` | Chiplet I/O | **`17 / 17 (100.0%)`** | `75 / 78 (96.2%)` | **`4,408 / 6,252 (70.5%)`** | `uvm_mlu_link_noc`, `uvm_mlu_chip_top`, `uvm_4chip_allreduce` |
| 13 | `mlu_ipu_core.sv` | Core Hierarchy | **`20 / 20 (100.0%)`** | `194 / 216 (89.8%)` | `15,859 / 57,840 (27.4%)` | `uvm_mtp_cluster`, `uvm_mlu_chip_top`, `uvm_soak_500k` |
| 14 | `mlu_mpu_core.sv` | Core Hierarchy | **`13 / 14 (92.9%)`** | `38 / 42 (90.5%)` | `1,874 / 7,992 (23.4%)` | `uvm_mtp_cluster`, `uvm_mlu_chip_top`, `uvm_soak_500k` |
| 15 | `mlu_mtp_cluster.sv` | Cluster Hier | **`13 / 13 (100.0%)`** | `36 / 36 (100.0%)` | `2,858 / 13,560 (21.1%)` | `uvm_mtp_cluster`, `uvm_mlu_chip_top`, `uvm_soak_500k` |
| 16 | `mlu_chip_top.sv` | Full-Chip Top | Structural (0 proc lines) | Structural (0 proc lines) | `869 / 3,428 (25.4%)` | `uvm_mlu_chip_top`, `uvm_4chip_allreduce`, `uvm_soak_500k` |
| 17 | `mlu_4chip_oam_node.sv` | 4-Chip Mesh | **`20 / 22 (90.9%)`** | `28 / 30 (93.3%)` | **`2,498 / 3,696 (67.6%)`** | `uvm_4chip_allreduce` |
| 18 | `mlu_cambricon_llm_flash_kv.sv` | LLM Flash/KV | **`23 / 32 (71.9%)`** | `28 / 39 (71.8%)` | **`3,308 / 4,058 (81.5%)`** | `uvm_cambricon_llm_kv` |
| — | **Total (All Synthesizable RTL)** | **Full Architecture** | **`469 / 507 (92.50%)`** | **`1,741 / 2,358 (73.83%)`** | **`61,846 / 177,964 (34.75%)`** | **All 10 UVM Suites + 500K-Cycle Soak** |

---

## 4. Annotated Source Analysis (`results/cov_annotated/`) & Closure Justification

Inspection of the line-annotated SystemVerilog sources in `results/cov_annotated/*.sv` confirms that:
1. **100% Unique Line Closure on 8 Critical RTL Modules**: `mlu_sram_secded_ecc`, `mlu_nram_banked_scratchpad`, `mlu_wram_weight_buffer`, `mlu_mpu_shared_sram`, `mlu_pmu_clock_gate`, `mlu_c2c_serdes_pcs`, `mlu_ipu_core`, and `mlu_mtp_cluster` achieve **100.0% unique source line coverage**.
2. **Remaining 7.50% (`38 / 507`) Unhit RTL Source Lines**:
   - **Defensive `default:` Case Branches**: Synthesizable `unique case` / `case` statements in `mlu_bang_icu.sv` (1 line), `mlu_tfu_fractal_mac.sv` (1 line), `mlu_mfu_dma_engine.sv` (1 line), and `mlu_mpu_core.sv` (1 line) include defensive `default:` assignments for illegal opcodes. Note that these branches are **mathematically proven unreachable/safe** under our Stage 9/10 Yosys Formal BMC (`formal/STAGE9_FORMAL_SUMMARY.md`, `formal/STAGE10_FORMAL_SUMMARY.md`).
   - **Port-Symmetric Mesh Routing Branches (`mlu_link_noc_router.sv`)**: Certain dimension-ordered routing branches for unused upper aperture coordinates (`dst_id[3:2]` combinations not mapped in the 4-chip OAM node) account for 11 lines in `mlu_link_noc_router.sv`, while 100% of active ports (Local, North, South, East/D2D, West/C2C) and both VCs (`VC0`, `VC1`) are verified both in UVM Suite 6/9 and in formal proofs.
   - **Multi-Instance Hierarchy Weighting**: Because `mlu_mtp_cluster` instantiates 4 `mlu_ipu_core` tiles (each containing 8 NRAM banks + 4 WRAM banks = 48 SRAM macros per cluster), testbench modes that specifically target standalone SRAM BIST/repair (`uvm_sram_nram_wram`) exercise 100% of the BIST FSM on the standalone macro while cluster-level tests focus on tensor/collective datapaths, explaining the difference between **92.50% unique RTL line coverage** and **73.83% instance-weighted line coverage**.
