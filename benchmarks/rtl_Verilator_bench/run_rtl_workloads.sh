#!/usr/bin/env bash
# =============================================================================
# File: benchmarks/rtl_Verilator_bench/run_rtl_workloads.sh
# Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
# Description: Compiles and runs the Cycle-Accurate Full-Chip & 4-Chip OAM
#              AI Workload Benchmark Suite on Verilator 5.054.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

RTL_DIR="../../rtl"
if [ -f "${RTL_DIR}/mlu_sram_secded_ecc.sv" ]; then
  SRAM_DIR="${RTL_DIR}"
else
  SRAM_DIR="../../sram_ip"
fi

DEFAULT_VERILATOR="/nfs/share/home/chenpei/verisegue_agent_v0/agent_v26/runs/uvm_gate0_20261104_221700/toolchain/verilator-5.054/bin/verilator"
if [ -x "${DEFAULT_VERILATOR}" ]; then
  VERILATOR_BIN="${VERILATOR_BIN:-${DEFAULT_VERILATOR}}"
else
  VERILATOR_BIN="${VERILATOR_BIN:-verilator}"
fi

echo "[1/2] Compiling Cycle-Accurate RTL AI Workload Suite with ${VERILATOR_BIN}..."
"${VERILATOR_BIN}" --binary --timing -O3 \
  -Wno-fatal -Wno-TIMESCALEMOD -Wno-UNOPTFLAT -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
  -I"${RTL_DIR}" -I"${SRAM_DIR}" \
  --top-module tb_rtl_ai_workloads \
  "${RTL_DIR}/mlu_pkg.sv" \
  "${SRAM_DIR}/mlu_sram_secded_ecc.sv" \
  "${SRAM_DIR}/mlu_sram_sp_macro.sv" \
  "${RTL_DIR}/mlu_nram_banked_scratchpad.sv" \
  "${RTL_DIR}/mlu_wram_weight_buffer.sv" \
  "${RTL_DIR}/mlu_mpu_shared_sram.sv" \
  "${RTL_DIR}/mlu_bang_icu.sv" \
  "${RTL_DIR}/mlu_pmu_clock_gate.sv" \
  "${RTL_DIR}/mlu_tfu_fractal_mac.sv" \
  "${RTL_DIR}/mlu_vfu_sfu_pipe.sv" \
  "${RTL_DIR}/mlu_mfu_dma_engine.sv" \
  "${RTL_DIR}/mlu_cambricon_llm_flash_kv.sv" \
  "${RTL_DIR}/mlu_link_noc_router.sv" \
  "${RTL_DIR}/mlu_c2c_serdes_pcs.sv" \
  "${RTL_DIR}/mlu_ipu_core.sv" \
  "${RTL_DIR}/mlu_mpu_core.sv" \
  "${RTL_DIR}/mlu_mtp_cluster.sv" \
  "${RTL_DIR}/mlu_chip_top.sv" \
  "${RTL_DIR}/mlu_4chip_oam_node.sv" \
  "tb_rtl_ai_workloads.sv" \
  -o Vtb_rtl_ai_workloads

echo "[2/2] Running Cycle-Accurate Hardware Workload Simulation..."
./obj_dir/Vtb_rtl_ai_workloads | tee rtl_workloads_sim.log

echo "[DONE] Generated rtl_workloads_sim.log and rtl_workload_cycles.json"
