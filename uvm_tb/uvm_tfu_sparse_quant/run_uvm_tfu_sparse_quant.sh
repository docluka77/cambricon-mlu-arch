#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="${ROOT}/uvm_tb/uvm_tfu_sparse_quant"
RTL="${ROOT}/rtl"
TC="/nfs/share/home/chenpei/verisegue_agent_v0/agent_v26/runs/uvm_gate0_20261104_221700/toolchain"
export VERILATOR_ROOT="${TC}/verilator-5.054"
VERILATOR="${VERILATOR_ROOT}/bin/verilator"
VERILATOR_COV="${VERILATOR_ROOT}/bin/verilator_coverage"
UVM_SRC="${TC}/uvm-core-2020.3.1/src"

cd "${DIR}"
mkdir -p build

echo "[Suite 3] Compiling Accellera IEEE 1800.2-2020 UVM + Verilator 5.054 (uvm_tfu_sparse_quant)..."
"${VERILATOR}" --cc --exe --build --timing \
  --coverage-line --coverage-toggle --coverage-user \
  -j 8 -Wno-fatal \
  --top-module tb_tfu_sparse_quant_top \
  --Mdir "${DIR}/build" \
  +define+UVM_NO_DPI \
  +incdir+"${UVM_SRC}" \
  +incdir+"${RTL}" \
  +incdir+"${DIR}" \
  "${UVM_SRC}/uvm_pkg.sv" \
  "${RTL}/mlu_pkg.sv" \
  "${RTL}/mlu_tfu_fractal_mac.sv" \
  "${DIR}/mlu_tfu_sparse_quant_if.sv" \
  "${DIR}/mlu_tfu_sparse_quant_uvm_pkg.sv" \
  "${DIR}/tb_tfu_sparse_quant_top.sv" \
  "${DIR}/dpi_tfu_ref.cpp" \
  "${DIR}/sim_main.cpp" \
  -CFLAGS "-O1 -std=c++17" \
  -o uvm_tfu_sparse_quant_sim > "${DIR}/compile.log" 2>&1

echo "[Suite 3] Running UVM simulation..."
"${DIR}/build/uvm_tfu_sparse_quant_sim" > "${DIR}/uvm_run.log" 2>&1
"${VERILATOR_COV}" --write-info "${DIR}/coverage.info" "${DIR}/coverage.dat" || true
grep -E "SUITE 3 PASS|UVM_INFO|UVM_WARNING|UVM_ERROR|UVM_FATAL" "${DIR}/uvm_run.log" | tail -n 15
