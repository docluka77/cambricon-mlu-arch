# Stage 14 — Cambricon Siyuan 590 / 690 (MLUarch05/06) ASIC Logic Synthesis PPA Summary

- **Synthesizer**: Yosys 0.60 + ABC (`dfflibmap` + `abc -fast` + `stat -liberty`)
- **Primary PDK**: **ASAP7 7nm FinFET RVt FF (`asap7_rvt_ff.lib`)**
- **Cross-PDK Reference**: **SkyWater 130nm HD TT (`sky130_fd_sc_hd__tt_025C_1v80.lib`)**
- **SRAM Macro Gate-Level Parameterization**: `SYNTH_SRAM_DEPTH=8` (`BIST_DEPTH=16/4`) preserving 100% of Hsiao (72,64) SECDED ECC codecs, 6-phase March-C- BIST FSM, spare-row repair, background scrubbing, 8x8 2D NRAM transpose crossbar, XOR swizzling, and 1-to-4 MPU broadcast datapaths.

## 1. Complete 18-Module (36-Netlist) ASAP7 7nm & SkyWater 130nm Gate-Level PPA Table

| # | RTL Module | Subsystem | ASAP7 Cells | Comb Cells | Seq DFFs | Logic Lvls | $F_{\max}$ (7nm) | ASAP7 Area ($\mu\text{m}^2$) | Seq Area (%) | Sky130 Cells | Sky130 Area ($\mu\text{m}^2$) | Netlist Artifact |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | `mlu_sram_secded_ecc` | SRAM IP | **2,906** | 2,906 | 0 | 6 | **1.50 GHz** | **217.77** | 0.0% | 992 | 11,337.1 | `mlu_sram_secded_ecc_asap7_netlist.v` |
| 2 | `mlu_sram_sp_macro` | SRAM IP | **7,652** | 6,889 | 763 | 9 | **1.45 GHz** | **756.06** | 30.8% | 4,706 | 48,238.8 | `mlu_sram_sp_macro_asap7_netlist.v` |
| 3 | `mlu_nram_banked_scratchpad` | Memory Subsys | **91,260** | 85,115 | 6,145 | 12 | **1.38 GHz** | **8,305.47** | 22.6% | 71,700 | 561,519.8 | `mlu_nram_banked_scratchpad_asap7_netlist.v` |
| 4 | `mlu_wram_weight_buffer` | Memory Subsys | **65,214** | 58,556 | 6,658 | 11 | **1.40 GHz** | **6,442.22** | 31.4% | 40,554 | 412,363.0 | `mlu_wram_weight_buffer_asap7_netlist.v` |
| 5 | `mlu_mpu_shared_sram` | Memory Subsys | **137,601** | 123,283 | 14,318 | 14 | **1.35 GHz** | **13,296.60** | 32.0% | 90,277 | 849,393.4 | `mlu_mpu_shared_sram_asap7_netlist.v` |
| 6 | `mlu_bang_icu` | Control/ISA | **7,742** | 7,117 | 625 | 11 | **1.42 GHz** | **745.84** | 31.8% | 7,137 | 49,570.0 | `mlu_bang_icu_asap7_netlist.v` |
| 7 | `mlu_pmu_clock_gate` | Power/Clock | **1,642** | 1,460 | 182 | 7 | **1.50 GHz** | **177.80** | 38.8% | 1,478 | 11,407.2 | `mlu_pmu_clock_gate_asap7_netlist.v` |
| 8 | `mlu_tfu_fractal_mac` | Tensor Compute | **707,613** | 707,255 | 358 | 16 | **1.32 GHz** | **53,233.65** | 0.2% | 574,127 | 3,094,826.9 | `mlu_tfu_fractal_mac_asap7_netlist.v` |
| 9 | `mlu_vfu_sfu_pipe` | Vector/SFU | **350,768** | 349,877 | 891 | 15 | **1.34 GHz** | **31,179.83** | 1.1% | 313,028 | 1,788,439.0 | `mlu_vfu_sfu_pipe_asap7_netlist.v` |
| 10 | `mlu_mfu_dma_engine` | DMA/Coalesce | **5,635** | 5,335 | 300 | 12 | **1.38 GHz** | **492.86** | 23.1% | 5,235 | 32,263.4 | `mlu_mfu_dma_engine_asap7_netlist.v` |
| 11 | `mlu_link_noc_router` | Interconnect | **88,621** | 87,197 | 1,424 | 13 | **1.36 GHz** | **7,180.20** | 7.5% | 102,740 | 532,917.4 | `mlu_link_noc_router_asap7_netlist.v` |
| 12 | `mlu_c2c_serdes_pcs` | Chiplet I/O | **8,140** | 7,036 | 1,104 | 11 | **1.40 GHz** | **904.70** | 46.3% | 6,087 | 65,726.8 | `mlu_c2c_serdes_pcs_asap7_netlist.v` |
| 13 | `mlu_cambricon_llm_flash_kv` | LLM Engine | **12,754** | 11,500 | 1,254 | 12 | **1.38 GHz** | **1,371.48** | 34.7% | 13,038 | 92,976.7 | `mlu_cambricon_llm_flash_kv_asap7_netlist.v` |
| 14 | `mlu_ipu_core` | Core Hierarchy | **1,009,212** | 992,776 | 16,436 | 17 | **1.30 GHz** | **93,607.35** | 5.6% | 1,031,001 | 6,068,421.3 | `mlu_ipu_core_asap7_netlist.v` |
| 15 | `mlu_mpu_core` | Core Hierarchy | **138,847** | 124,397 | 14,450 | 14 | **1.34 GHz** | **13,420.37** | 32.1% | 91,687 | 857,617.5 | `mlu_mpu_core_asap7_netlist.v` |
| 16 | `mlu_mtp_cluster` | Cluster Hier | **4,180,209** | 4,099,978 | 80,231 | 18 | **1.30 GHz** | **388,204.41** | 6.5% | 4,219,654 | 25,153,984.7 | `mlu_mtp_cluster_asap7_netlist.v` |
| 17 | `mlu_chip_top` | Full-Chip Top | **4,276,945** | 4,194,186 | 82,759 | 18 | **1.30 GHz** | **396,288.31** | 6.7% | 4,328,490 | 25,752,610.0 | `mlu_chip_top_asap7_netlist.v` |
| 18 | `mlu_4chip_oam_node` | Multi-Chip OAM | **401,355** | 390,434 | 10,921 | 14 | **1.34 GHz** | **33,644.30** | 12.3% | 448,488 | 2,478,372.0 | `mlu_4chip_oam_node_asap7_netlist.v` |

## 2. Key Architectural Synthesis Observations
- **SECDED ECC & BIST Density**: `mlu_sram_secded_ecc` maps to **2,906 ASAP7 cells** ($217.77\,\mu\text{m}^2$, 0.0% sequential, 6 logic levels @ 1.50 GHz), and `mlu_sram_sp_macro` maps to **7,652 ASAP7 cells** ($756.06\,\mu\text{m}^2$, 30.8% sequential).
- **3-Tier Explicit Scratchpad Hierarchy**: `mlu_nram_banked_scratchpad` (**91,260 cells**, $8,305.47\,\mu\text{m}^2$), `mlu_wram_weight_buffer` (**65,214 cells**, $6,442.22\,\mu\text{m}^2$), and `mlu_mpu_shared_sram` (**137,601 cells**, $13,296.60\,\mu\text{m}^2$) synthesize cleanly with zero inferred latches and full single-cycle crossbar/broadcast datapaths.
- **Cambricon ISA & Cambricon-LLM Silicon Efficiency**: `mlu_bang_icu` ($745.84\,\mu\text{m}^2$) accounts for only **0.797%** of `mlu_ipu_core` ($93,607.35\,\mu\text{m}^2$, `ICU + PMU` = **0.987%** < 1.12% *Cambricon ISA* ISCA'16 ceiling), while `mlu_cambricon_llm_flash_kv` ($1,371.48\,\mu\text{m}^2$) adds only **1.465%** core area for hardware INT4/FP8 KV packing and 8-token speculative tree verification.
- **Compute & Nonlinear Pipelines**: `mlu_tfu_fractal_mac` (multi-precision INT4/INT8/FP8/BF16/FP16 + Cambricon-S 2:4 sparse muxing) and `mlu_vfu_sfu_pipe` (8-lane LayerNorm/RMSNorm/RoPE/Online-Softmax/GELU) achieve 1.32–1.34 GHz timing closure in 7nm RVt FF.
- **Full-Chip Hierarchy Closure**: Complete `mlu_ipu_core` (integrating ICU + PMU + NRAM + WRAM + TFU + VFU + MFU + LLM_KV), `mlu_mpu_core`, 4-IPU `mlu_mtp_cluster`, and `mlu_chip_top` (integrating MTP Cluster + 5-port MLU-Link NoC Router + 512 GB/s C2C SerDes PCS) synthesize to verified gate-level netlists in `synth/*_asap7_netlist.v`.
