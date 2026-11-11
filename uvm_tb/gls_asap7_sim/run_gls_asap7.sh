#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

TC="${VERILATOR_ROOT:-/nfs/share/home/chenpei/verisegue_agent_v0/agent_v26/runs/uvm_gate0_20261104_221700/toolchain/verilator-5.054}"
if [ -d "$TC/bin" ]; then
  export VERILATOR_ROOT="$TC"
  VERILATOR="$TC/bin/verilator"
else
  VERILATOR="verilator"
fi

echo "[Stage 22 GLS] Step 1: Generating ASAP7 7nm behavioral cell library and wrapped gate-level netlists..."
python3 uvm_tb/gls_asap7_sim/gen_asap7_cells_and_netlists.py

echo "[Stage 22 GLS] Step 2: Compiling RTL + ASAP7 7nm Gate-Level Netlists under Verilator 5.054..."
rm -rf uvm_tb/gls_asap7_sim/obj_dir
"$VERILATOR" --cc --exe --build -j 8 -CFLAGS "-O0" --inline-mult -1 \
  -DSYNTH_SRAM_DEPTH=8 \
  -Wno-fatal -Wno-UNOPTFLAT -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-PINCONNECTEMPTY -Wno-DECLFILENAME \
  --top-module tb_gls_asap7 \
  -Irtl -Isram_ip \
  rtl/mlu_pkg.sv \
  sram_ip/mlu_sram_secded_ecc.sv \
  sram_ip/mlu_sram_sp_macro.sv \
  rtl/mlu_mpu_shared_sram.sv \
  rtl/mlu_pmu_clock_gate.sv \
  rtl/mlu_bang_icu.sv \
  rtl/mlu_mfu_dma_engine.sv \
  rtl/mlu_c2c_serdes_pcs.sv \
  rtl/mlu_cambricon_llm_flash_kv.sv \
  rtl/mlu_mpu_core.sv \
  uvm_tb/gls_asap7_sim/asap7_cells_sim.v \
  uvm_tb/gls_asap7_sim/asap7_netlists_gls.v \
  uvm_tb/gls_asap7_sim/tb_gls_asap7.sv \
  uvm_tb/gls_asap7_sim/sim_gls_main.cpp \
  --Mdir uvm_tb/gls_asap7_sim/obj_dir

echo "[Stage 22 GLS] Step 3: Running 5,000-cycle lockstep Gate-Level Netlist vs. RTL simulation..."
./uvm_tb/gls_asap7_sim/obj_dir/Vtb_gls_asap7 | tee uvm_tb/gls_asap7_sim/gls_asap7_sim.log
