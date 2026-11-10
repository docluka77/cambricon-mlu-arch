#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TC="/nfs/share/home/chenpei/verisegue_agent_v0/agent_v26/runs/uvm_gate0_20261104_221700/toolchain"
export VERILATOR_ROOT="${TC}/verilator-5.054"
VERILATOR="${VERILATOR_ROOT}/bin/verilator"
YOSYS="/usr/local/bin/yosys"
LIB_ASAP7="/nfs/share/home/chenpei/hyr/latentcore_mla_dsa_20261103/synth/asap7_rvt_ff.lib"
LIB_SKY130="/nfs/share/home/chenpei/hyr/dac2027_llm_dsa_marathon/synth/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"

cd "${ROOT}"

echo "=== [1/4] Verilator 5.054 --lint-only -Wall on mlu_cambricon_llm_flash_kv.sv ==="
"${VERILATOR}" --lint-only -Wall --top-module mlu_cambricon_llm_flash_kv \
  -Irtl rtl/mlu_pkg.sv rtl/mlu_cambricon_llm_flash_kv.sv
echo "LINT_CLEAN_0_WARNINGS"

echo "=== [2/4] Yosys 0.60 ASAP7 7nm & Sky130 130nm Synthesis ==="
"${YOSYS}" -p "
  read_verilog -sv -Irtl rtl/mlu_pkg.sv rtl/mlu_cambricon_llm_flash_kv.sv;
  chformal -remove;
  synth -top mlu_cambricon_llm_flash_kv -noabc;
  dfflibmap -liberty ${LIB_ASAP7};
  abc -fast -liberty ${LIB_ASAP7};
  stat -liberty ${LIB_ASAP7};
  write_verilog -noattr synth/mlu_cambricon_llm_flash_kv_asap7_netlist.v
" > synth/synth_mlu_cambricon_llm_flash_kv_asap7.log 2>&1

"${YOSYS}" -p "
  read_verilog -sv -Irtl rtl/mlu_pkg.sv rtl/mlu_cambricon_llm_flash_kv.sv;
  chformal -remove;
  synth -top mlu_cambricon_llm_flash_kv -noabc;
  dfflibmap -liberty ${LIB_SKY130};
  abc -fast -liberty ${LIB_SKY130};
  stat -liberty ${LIB_SKY130};
  write_verilog -noattr synth/mlu_cambricon_llm_flash_kv_sky130_netlist.v
" > synth/synth_mlu_cambricon_llm_flash_kv_sky130.log 2>&1

grep -E "Number of cells:|Chip area for module" synth/synth_mlu_cambricon_llm_flash_kv_asap7.log

echo "=== [3/4] Yosys 0.60 Sequential SAT Formal Proof (seq 8) ==="
"${YOSYS}" -s formal/prove_cambricon_llm_kv.ys > formal/formal_cambricon_llm_kv.log 2>&1
grep -E "SUCCESS!|Q.E.D." formal/formal_cambricon_llm_kv.log

echo "=== [4/4] Accellera UVM Suite 10 (uvm_cambricon_llm_kv) ==="
chmod +x uvm_tb/uvm_cambricon_llm_kv/run_uvm_cambricon_llm_kv.sh
uvm_tb/uvm_cambricon_llm_kv/run_uvm_cambricon_llm_kv.sh
