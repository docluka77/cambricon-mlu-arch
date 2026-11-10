#!/usr/bin/env bash
# =============================================================================
# File: formal/run_stage10_formal.sh
# Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
# Description: Master Formal Verification Runner for Stage 10 (Yosys 0.60 SAT/BMC)
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "======================================================================"
echo " Stage 10 Formal Verification Suite — Cambricon Siyuan 590/690"
echo "======================================================================"

echo "[1/4] Proving TFU Fractal MAC Sparsity Zero-Skip & Multi-Precision Annihilation..."
yosys -s formal/prove_tfu.ys > formal/formal_tfu.log 2>&1
grep -E "Solving problem|SUCCESS!|CPU:" formal/formal_tfu.log

echo "[2/4] Proving VFU/SFU 2-Cycle Pipeline, Saturating VADD, Softmax & QuantStat..."
yosys -s formal/prove_vfu.ys > formal/formal_vfu.log 2>&1
grep -E "Solving problem|SUCCESS!|CPU:" formal/formal_vfu.log

echo "[3/4] Proving MFU Strided/Decompression/Transpose DMA Engine..."
yosys -s formal/prove_mfu_dma.ys > formal/formal_mfu_dma.log 2>&1
grep -E "Solving problem|SUCCESS!|CPU:" formal/formal_mfu_dma.log

echo "[4/4] Proving MLU-Link 5-Port NoC Router & C2C SerDes PCS CRC-16/Replay..."
yosys -s formal/prove_mlu_link.ys > formal/formal_mlu_link.log 2>&1
grep -E "Solving problem|SUCCESS!|CPU:" formal/formal_mlu_link.log

echo "======================================================================"
echo " ALL 4 STAGE 10 FORMAL VERIFICATION SUITES PROVEN (Q.E.D.)"
echo "======================================================================"
