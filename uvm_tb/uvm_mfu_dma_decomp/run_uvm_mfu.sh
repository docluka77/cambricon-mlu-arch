#!/usr/bin/env bash
set -euo pipefail

DIR="/nfs/share/home/chenpei/hyr/cambricon_mlu590_690_marathon/uvm_tb/uvm_mfu_dma_decomp"
RTL="/nfs/share/home/chenpei/hyr/cambricon_mlu590_690_marathon/rtl"
TC="/nfs/share/home/chenpei/verisegue_agent_v0/agent_v26/runs/uvm_gate0_20261104_221700/toolchain"
export VERILATOR_ROOT="${TC}/verilator-5.054"
VERILATOR="${VERILATOR_ROOT}/bin/verilator"
VERILATOR_COV="${VERILATOR_ROOT}/bin/verilator_coverage"
UVM_SRC="${TC}/uvm-core-2020.3.1/src"

cd "${DIR}"
mkdir -p build

echo "[1/2] Compiling Suite 5 (uvm_mfu_dma_decomp) with Accellera UVM 2020.3.1 + Verilator 5.054..."
"${VERILATOR}" --cc --exe --build --timing \
  --coverage-line --coverage-toggle --coverage-user \
  -j 8 -Wno-fatal \
  --top-module tb_mfu_uvm_top \
  --Mdir "${DIR}/build" \
  +define+UVM_NO_DPI \
  +incdir+"${UVM_SRC}" \
  +incdir+"${RTL}" \
  +incdir+"${DIR}" \
  "${UVM_SRC}/uvm_pkg.sv" \
  "${RTL}/mlu_pkg.sv" \
  "${RTL}/mlu_mfu_dma_engine.sv" \
  "${DIR}/mlu_mfu_if.sv" \
  "${DIR}/mlu_mfu_uvm_pkg.sv" \
  "${DIR}/tb_mfu_uvm_top.sv" \
  "${DIR}/dpi_mfu_ref.cpp" \
  "${DIR}/sim_main.cpp" \
  -CFLAGS "-O1 -std=c++17" \
  -o uvm_mfu_sim > "${DIR}/compile.log" 2>&1

echo "[2/2] Running Suite 5 (uvm_mfu_dma_decomp)..."
"${DIR}/build/uvm_mfu_sim" > "${DIR}/uvm_run.log" 2>&1
"${VERILATOR_COV}" --write-info "${DIR}/coverage.info" "${DIR}/coverage.dat"
"${VERILATOR_COV}" --annotate "${DIR}/annotated_cov" "${DIR}/coverage.dat" > "${DIR}/cov_annotate.log" 2>&1 || true
echo "SUITE 5 (uvm_mfu_dma_decomp) PASSED!"
