#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/nfs/share/home/chenpei/hyr/cambricon_mlu590_690_marathon"
VC="/nfs/share/home/chenpei/verisegue_agent_v0/agent_v26/runs/uvm_gate0_20261104_221700/toolchain/verilator-5.054/bin/verilator_coverage"

cd "${ROOT_DIR}"

echo "[Stage 21] 3/6 Running uvm_mlu_link_noc..."
bash uvm_tb/uvm_mlu_link_noc/run_uvm_link_noc.sh

echo "[Stage 21] 4/6 Running uvm_mlu_chip_top..."
bash uvm_tb/uvm_mlu_chip_top/run_uvm_mlu_chip_top.sh

echo "[Stage 21] 5/6 Running uvm_4chip_allreduce..."
bash uvm_tb/uvm_4chip_allreduce/run_uvm_4chip_allreduce.sh

echo "[Stage 21] 6/6 Running uvm_cambricon_llm_kv..."
bash uvm_tb/uvm_cambricon_llm_kv/run_uvm_cambricon_llm_kv.sh

echo "[Stage 21] Merging all 10 UVM coverage databases..."
"${VC}" --write results/merged_uvm_coverage.dat \
        --write-info results/merged_uvm_coverage.info \
        uvm_tb/uvm_*/coverage.dat

rm -rf results/cov_annotated
mkdir -p results/cov_annotated
"${VC}" --annotate results/cov_annotated results/merged_uvm_coverage.dat > results/cov_annotate_summary.log 2>&1 || true

python3 results/parse_coverage.py | tee results/stage21_coverage_table.txt
