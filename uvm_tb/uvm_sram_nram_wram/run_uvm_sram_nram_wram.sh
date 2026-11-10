#!/usr/bin/env bash
set -euo pipefail

ROOT="/nfs/share/home/chenpei/hyr/cambricon_mlu590_690_marathon"
DIR="${ROOT}/uvm_tb/uvm_sram_nram_wram"
RTL="${ROOT}/rtl"
SRAM_IP="${ROOT}/sram_ip"
TC="/nfs/share/home/chenpei/verisegue_agent_v0/agent_v26/runs/uvm_gate0_20261104_221700/toolchain"
export VERILATOR_ROOT="${TC}/verilator-5.054"
VERILATOR="${VERILATOR_ROOT}/bin/verilator"
VERILATOR_COV="${VERILATOR_ROOT}/bin/verilator_coverage"
UVM_SRC="${TC}/uvm-core-2020.3.1/src"

cd "${DIR}"
mkdir -p build

echo "[Suite 1] Compiling Accellera IEEE 1800.2-2020 UVM + Verilator 5.054 (uvm_sram_nram_wram)..."
"${VERILATOR}" --cc --exe --build --timing \
  --coverage-line --coverage-toggle --coverage-user \
  -j 8 -Wno-fatal \
  --top-module tb_sram_nram_wram_top \
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
  "${DIR}/mlu_sram_nram_wram_if.sv" \
  "${DIR}/mlu_sram_nram_wram_uvm_pkg.sv" \
  "${DIR}/tb_sram_nram_wram_top.sv" \
  "${DIR}/dpi_sram_ref.cpp" \
  "${DIR}/sim_main.cpp" \
  -CFLAGS "-O1 -std=c++17" \
  -o uvm_sram_nram_wram_sim > "${DIR}/compile.log" 2>&1

echo "[Suite 1] Running UVM simulation..."
"${DIR}/build/uvm_sram_nram_wram_sim" > "${DIR}/uvm_run.log" 2>&1
"${VERILATOR_COV}" --write-info "${DIR}/coverage.info" "${DIR}/coverage.dat" || true
grep -E "SUITE 1 PASS|UVM_INFO|UVM_WARNING|UVM_ERROR|UVM_FATAL" "${DIR}/uvm_run.log" | tail -n 15
