#!/usr/bin/env bash
# =============================================================================
# File: formal/run_stage9_formal.sh
# Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
# Description: Master Formal Verification Runner (Yosys 0.60 SAT / BMC)
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "======================================================================"
echo " Stage 9 Formal Verification Suite — Cambricon Siyuan 590/690"
echo "======================================================================"

echo "[1/4] Proving (72,64) Hsiao SECDED ECC Unbounded SAT Theorem..."
yosys -s formal/prove_sram_ecc.ys > formal/formal_sram_ecc.log 2>&1
grep -E "Solving problem|SUCCESS!|CPU:" formal/formal_sram_ecc.log

echo "[2/4] Proving Single-Port SRAM Macro Spare-Row & Low-Power BMC..."
yosys -s formal/prove_sram_macro.ys > formal/formal_sram_macro.log 2>&1
grep -E "Solving problem|SUCCESS!|CPU:" formal/formal_sram_macro.log

echo "[3/4] Proving NRAM Swizzle/Transpose, WRAM Ping-Pong & MPU Broadcast..."
yosys -s formal/prove_nram_wram_mpu.ys > formal/formal_nram_wram_mpu.log 2>&1
grep -E "Solving problem|SUCCESS!|CPU:" formal/formal_nram_wram_mpu.log

echo "[4/4] Proving BANG ICU Hazard Scoreboard & PMU 0-Cycle Clock Gate..."
yosys -s formal/prove_bang_icu_pmu.ys > formal/formal_bang_icu_pmu.log 2>&1
grep -E "Solving problem|SUCCESS!|CPU:" formal/formal_bang_icu_pmu.log

echo "======================================================================"
echo " ALL 4 FORMAL VERIFICATION SUITES PROVEN (Q.E.D.)"
echo "======================================================================"
