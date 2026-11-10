#!/usr/bin/env bash
# =============================================================================
# File: uvm_tb/uvm_soak_500k/run_soak_500k.sh
# Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
# Description: Stage 17 — 500,000-Cycle Full-Chip Randomized Soak Stress Runner
# =============================================================================
set -euo pipefail

ROOT="/nfs/share/home/chenpei/hyr/cambricon_mlu590_690_marathon"
DIR="${ROOT}/uvm_tb/uvm_soak_500k"
RTL="${ROOT}/rtl"
SRAM_IP="${ROOT}/sram_ip"
TC="/nfs/share/home/chenpei/verisegue_agent_v0/agent_v26/runs/uvm_gate0_20261104_221700/toolchain"
export VERILATOR_ROOT="${TC}/verilator-5.054"
VERILATOR="${VERILATOR_ROOT}/bin/verilator"

cd "${ROOT}"
mkdir -p "${DIR}/obj_dir"

echo "[SOAK-500K] Compiling mlu_chip_top + tb_soak_500k with Verilator 5.054..."
"${VERILATOR}" --cc --exe --build -j 8 -O3 -Wno-fatal \
  --top-module tb_soak_500k \
  -I"${RTL}" -I"${SRAM_IP}" \
  --Mdir "${DIR}/obj_dir" \
  "${RTL}/mlu_pkg.sv" \
  "${SRAM_IP}/mlu_sram_secded_ecc.sv" \
  "${SRAM_IP}/mlu_sram_sp_macro.sv" \
  "${RTL}/mlu_nram_banked_scratchpad.sv" \
  "${RTL}/mlu_wram_weight_buffer.sv" \
  "${RTL}/mlu_mpu_shared_sram.sv" \
  "${RTL}/mlu_bang_icu.sv" \
  "${RTL}/mlu_pmu_clock_gate.sv" \
  "${RTL}/mlu_tfu_fractal_mac.sv" \
  "${RTL}/mlu_vfu_sfu_pipe.sv" \
  "${RTL}/mlu_mfu_dma_engine.sv" \
  "${RTL}/mlu_cambricon_llm_flash_kv.sv" \
  "${RTL}/mlu_ipu_core.sv" \
  "${RTL}/mlu_mpu_core.sv" \
  "${RTL}/mlu_mtp_cluster.sv" \
  "${RTL}/mlu_link_noc_router.sv" \
  "${RTL}/mlu_c2c_serdes_pcs.sv" \
  "${RTL}/mlu_chip_top.sv" \
  "${DIR}/tb_soak_500k.sv" \
  "${DIR}/sim_soak_500k.cpp" \
  -CFLAGS "-O3 -std=c++17" \
  -o Vtb_soak_500k > "${DIR}/compile.log" 2>&1

echo "[SOAK-500K] Executing 500,000-cycle full-chip randomized soak simulation..."
"${DIR}/obj_dir/Vtb_soak_500k" | tee "${DIR}/soak_500k.log"
