#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="${ROOT}/uvm_tb/uvm_mlu_chip_top"
RTL="${ROOT}/rtl"
SRAM_IP="${ROOT}/sram_ip"
TC="/nfs/share/home/chenpei/verisegue_agent_v0/agent_v26/runs/uvm_gate0_20261104_221700/toolchain"
export VERILATOR_ROOT="${TC}/verilator-5.054"
VERILATOR="${VERILATOR_ROOT}/bin/verilator"
VERILATOR_COV="${VERILATOR_ROOT}/bin/verilator_coverage"
UVM_SRC="${TC}/uvm-core-2020.3.1/src"

cd "${DIR}"
mkdir -p build

echo "[Suite 8] Compiling Accellera IEEE 1800.2-2020 UVM + Verilator 5.054 (uvm_mlu_chip_top)..."
"${VERILATOR}" --cc --exe --build --timing \
  --coverage-line --coverage-toggle --coverage-user \
  -j 8 -Wno-fatal \
  --top-module tb_mlu_chip_top \
  --Mdir "${DIR}/build" \
  +define+UVM_NO_DPI \
  +incdir+"${UVM_SRC}" \
  +incdir+"${RTL}" \
  +incdir+"${SRAM_IP}" \
  +incdir+"${DIR}" \
  "${UVM_SRC}/uvm_pkg.sv" \
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
  "${DIR}/mlu_chip_top_if.sv" \
  "${DIR}/mlu_chip_top_uvm_pkg.sv" \
  "${DIR}/tb_mlu_chip_top.sv" \
  "${DIR}/dpi_chip_top_ref.cpp" \
  "${DIR}/sim_main.cpp" \
  -CFLAGS "-O1 -std=c++17" \
  -o uvm_mlu_chip_top_sim > "${DIR}/compile.log" 2>&1

echo "[Suite 8] Running UVM simulation..."
"${DIR}/build/uvm_mlu_chip_top_sim" > "${DIR}/uvm_run.log" 2>&1
"${VERILATOR_COV}" --write-info "${DIR}/coverage.info" "${DIR}/coverage.dat" || true
grep -E "SUITE 8 PASS|UVM_INFO|UVM_WARNING|UVM_ERROR|UVM_FATAL" "${DIR}/uvm_run.log" | tail -n 15
