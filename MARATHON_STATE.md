# Cambricon Siyuan 590 / 690 (MLUarch05/06 & Cambricon-LLM/Q/S) Marathon State Machine

- **Target Server**: `ict-eda-9` (`gpu09.edacluster.com`, `10.19.20.9`)
- **NFS Workspace**: `/nfs/share/home/chenpei/hyr/cambricon_mlu590_690_marathon` (symlinked at `/home/chenpei1/hyr/cambricon_mlu590_690_marathon`)
- **Toolchains on `ict-eda-9`**:
  - **Verilator 5.054 + IEEE 1800.2-2020 UVM 2020.3.1**:
    - `VERILATOR_ROOT=/nfs/share/home/chenpei/verisegue_agent_v0/agent_v26/runs/uvm_gate0_20261104_221700/toolchain/verilator-5.054`
    - `UVM_SRC=/nfs/share/home/chenpei/verisegue_agent_v0/agent_v26/runs/uvm_gate0_20261104_221700/toolchain/uvm-core-2020.3.1/src`
  - **Yosys 0.60 + Formal Verification (`yosys`, `yosys-smtbmc`, `yosys-abc`)**: `/usr/local/bin/yosys`
  - **ASIC Synthesis PDKs**:
    - ASAP7 7nm: `/nfs/share/home/chenpei/hyr/latentcore_mla_dsa_20261103/synth/asap7_rvt_ff.lib`
    - SkyWater 130nm: `/nfs/share/home/chenpei/hyr/groq_lpu_tsp_20261106/synth/` (or standard liberty in `/nfs/share/home/chenpei/hyr`)

## Architectural Baseline & Quantitative Targets (MLU590 / MLU690 + Cambricon Academic Series)
| Parameter | Target Specification (MLU590 / MLU690 & Cambricon-LLM/Q/S) | Verification / Closure Method |
| :--- | :--- | :--- |
| **Architecture Generation** | **MLUarch05 / MLUarch06** (Dual-Die / Multi-Chiplet MTP Hierarchy) | Cycle-accurate RTL + Golden Model |
| **Compute Hierarchy** | Device -> MTP Cluster (4× **IPU Cores** + 1× **MPU Memory Core**) | `mlu_chip_top` -> `mlu_mtp_cluster` -> `mlu_ipu_core` + `mlu_mpu_core` |
| **Core Scratchpad (`NRAM`)** | **768 KB / IPU Core** (Banked SRAM + SECDED ECC + 2D Transpose Crossbar) | `mlu_nram_banked_scratchpad.sv` |
| **Weight Scratchpad (`WRAM`)** | **512 KB / IPU Core** (Ping-Pong Double-Buffered + Cambricon-S Block-Sparse Index) | `mlu_wram_weight_buffer.sv` |
| **Cluster Shared (`SRAM`)** | **4 MB / MTP Cluster** inside **MPU Core** (Multi-Cast Broadcast + Atomic Sync) | `mlu_mpu_shared_sram.sv` |
| **Peak Compute Throughput** | **512 TOPS (INT8 Dense) / 1024 TOPS (INT4/Sparse)**, **256–345 TFLOPS (BF16/FP16)**, **688 TFLOPS (FP8)** | Scaled Array PPA + Cycle-Accurate Roofline |
| **Off-Chip Memory (GDRAM)** | **96 GB HBM2e / HBM3e**, **2.0–2.8 TB/s** w/ 2D/3D Strided & LZ4/Entropy Decomp DMA | `mlu_mfu_dma_engine.sv` |
| **Inter-Chip Interconnect** | **MLU-Link™** (**512 GB/s** Coherent Packetized NoC + C2C SerDes PCS w/ CRC-16 Replay) | `mlu_link_noc_router.sv` + `mlu_c2c_serdes_pcs.sv` |
| **Power & Energy Efficiency** | **~350W TDP**, **~1.46 TOPS/W (INT8)**, **~0.11 pJ/MAC (7nm Core)**, **>82% HBM Traffic Reduction** via NRAM/WRAM/SRAM reuse | ASAP7 7nm Synthesis + Energy Model |

---

## 20-Stage Execution Roadmap & Status

| Stage | Milestone Description | Key Deliverables | Status |
| :--- | :--- | :--- | :--- |
| **Stage 1** | Deep Literature Survey, MLUarch05/06 & BANG ISA Spec, Shared Package (`mlu_pkg.sv`), & Bit-Exact Python Golden Model | `docs/CAMBRICON_MLU590_690_ARCH_SPEC.md`, `rtl/mlu_pkg.sv`, `arch_model/cambricon_mlu_golden.py` | `VERIFIED` |
| **Stage 2** | Complex On-Chip Memory Subsystem RTL: SECDED ECC, BIST/Repair SRAM Macro, Banked `NRAM` (Transpose), Ping-Pong `WRAM` (Sparse Index), & MPU Shared `SRAM` | `sram_ip/mlu_sram_secded_ecc.sv`, `sram_ip/mlu_sram_sp_macro.sv`, `rtl/mlu_nram_banked_scratchpad.sv`, `rtl/mlu_wram_weight_buffer.sv`, `rtl/mlu_mpu_shared_sram.sv` | `VERIFIED` |
| **Stage 3** | BANG ISA Instruction Control Unit (`mlu_bang_icu.sv`), Multi-Queue Hazard Scoreboard, Union-Task Sync Barrier, & Dynamic Clock/Power Gating (`mlu_pmu_clock_gate.sv`) | `rtl/mlu_bang_icu.sv`, `rtl/mlu_pmu_clock_gate.sv` | `VERIFIED` |
| **Stage 4** | Tensor Function Unit (`mlu_tfu_fractal_mac.sv`): Fractal Multi-Precision (FP16/BF16/FP8/INT8/INT4) Systolic/Tree MAC + Cambricon-S Sparsity + Cambricon-Q Quantizer | `rtl/mlu_tfu_fractal_mac.sv` | `VERIFIED` |
| **Stage 5** | Vector Function Unit (`mlu_vfu_sfu_pipe.sv`): BANG Vector ALU + Special Function Unit (FlashAttention Online Softmax, RoPE, RMSNorm, SwiGLU) | `rtl/mlu_vfu_sfu_pipe.sv` | `VERIFIED` |
| **Stage 6** | Memory Function Unit (`mlu_mfu_dma_engine.sv`): 2D/3D Strided & Gather/Scatter Asynchronous DMA (`GDRAM <-> SRAM <-> NRAM/WRAM`) + Hardware Weight Decompressor | `rtl/mlu_mfu_dma_engine.sv` | `VERIFIED` |
| **Stage 7** | Hierarchical Integration: `mlu_ipu_core.sv`, `mlu_mpu_core.sv`, `mlu_mtp_cluster.sv` (4 IPU + 1 MPU), `mlu_link_noc_router.sv`, `mlu_c2c_serdes_pcs.sv`, & `mlu_chip_top.sv` | 6 Top/Cluster/Interconnect RTL modules | `VERIFIED` |
| **Stage 8** | Verilator 5.054 Zero-Warning Lint Closure & Standalone Cycle-Accurate RTL-vs-Golden Co-Simulation across all 14 RTL Modules | `results/stage8_lint_and_cosim_summary.md` | `VERIFIED` |
| **Stage 9** | Formal Verification Phase 1 (Yosys SMT-BMC / SAT): Proofs for SRAM SECDED ECC, NRAM/WRAM Bank Arbiters, BANG ICU Scoreboard/Barrier, & PMU Clock/Power Gate | `formal/prove_sram_ecc.ys`, `formal/prove_nram_wram.ys`, `formal/prove_bang_icu.ys`, `formal/prove_pmu.ys` | `VERIFIED` |
| **Stage 10** | Formal Verification Phase 2 (Yosys SMT-BMC / SAT): Proofs for TFU Fractal MAC/Sparsity, VFU SFU Pipe, MFU Strided DMA, & MLU-Link NoC + C2C SerDes PCS | `formal/prove_tfu.ys`, `formal/prove_vfu.ys`, `formal/prove_mfu_dma.ys`, `formal/prove_mlu_link.ys` | `VERIFIED` |
| **Stage 11** | Accellera IEEE 1800.2-2020 UVM Phase 1 (Verilator 5.054 + UVM 2020.3.1): Suites 1–3 (`uvm_sram_nram_wram`, `uvm_bang_icu_pmu`, `uvm_tfu_sparse_quant`) | 3 Complete UVM Environments + Coverage | `VERIFIED` |
| **Stage 12** | Accellera IEEE 1800.2-2020 UVM Phase 2 (Verilator 5.054 + UVM 2020.3.1): Suites 4–6 (`uvm_vfu_llm_ops`, `uvm_mfu_dma_decomp`, `uvm_mlu_link_noc`) | 3 Complete UVM Environments + Coverage | `VERIFIED` |
| **Stage 13** | Accellera IEEE 1800.2-2020 UVM Phase 3 (Verilator 5.054 + UVM 2020.3.1): Suites 7–8 (`uvm_mtp_cluster` Union Tasks, `uvm_mlu_chip_top` End-to-End LLM Layer) | 2 Complete Cluster/Chip UVM Environments | `VERIFIED` |
| **Stage 14** | ASIC Synthesis on ASAP7 7nm PDK & Sky130 PDK for all 14 RTL Modules + `mlu_chip_top` | `synth/*_asap7_netlist.v`, `synth/PPA_SUMMARY.md` | `VERIFIED` |
| **Stage 15** | Gate-Level Netlist vs. RTL Formal Equivalence Proofs (Miter SAT on Synthesized ASAP7 7nm Netlists — 7/7 Modules `SUCCESS! Q.E.D.`) | `formal/STAGE15_GATE_EQUIV_SUMMARY.md`, `formal/prove_gate_equiv_*.ys` | `VERIFIED` |
| **Stage 16** | Quantitative Energy Efficiency, Roofline, & MLU590/MLU690 Parity Closure (`TOPS/W`, `pJ/MAC`, NRAM/WRAM HBM Traffic Reduction Proof) | `energy_ppa/cambricon_energy_efficiency_model.py`, `energy_ppa/ENERGY_PARITY_REPORT.md` | `VERIFIED` |
| **Stage 17** | Adversarial Mutation Testing (20/20 Synthetic RTL Mutants Killed in 43.03s) & 500,000-Cycle Randomized Soak Stress (`SOAK_500K_STRESS_TEST_PASS`) | `formal/mutation_testing/MUTATION_REPORT.md`, `uvm_tb/uvm_soak_500k/soak_500k.log` | `VERIFIED` |
| **Stage 18** | Multi-Chiplet 4-Way MLU-Link OAM Node (`mlu_4chip_oam_node.sv`) + Hardware Ring/Butterfly AllReduce UVM Suite 9 & Formal Proof (`19.86M` SAT vars `SUCCESS! Q.E.D.`) | `rtl/mlu_4chip_oam_node.sv`, `formal/formal_4chip_oam_node.log`, `uvm_tb/uvm_4chip_allreduce/` | `VERIFIED` |
| **Stage 19** | Cambricon-LLM (MICRO'24) Flash-Assisted INT4/FP8 KV-Cache & Speculative Tree Decode Engine (`mlu_cambricon_llm_flash_kv.sv`) + UVM Suite 10 & Formal Proof | `rtl/mlu_cambricon_llm_flash_kv.sv`, `formal/formal_cambricon_llm_kv.log`, `uvm_tb/uvm_cambricon_llm_kv/` | `VERIFIED` |
| **Stage 20** | Master Regression Audit (All 18 RTL Modules + All 10 UVM Suites + All 13 Formal/Equiv Logs + 20/20 Mutants + 500k Soak + Dual-PDK Synthesis + Energy Parity) & Final Report | `results/master_audit_summary.json`, `FINAL_CAMBRICON_MLU_REPORT.md` | `VERIFIED` |
