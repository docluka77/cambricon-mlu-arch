#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

YOSYS=/usr/local/bin/yosys

echo "=== [1/4] Running prove_gate_equiv_core_ips.ys ==="
$YOSYS -s formal/prove_gate_equiv_core_ips.ys > formal/gate_equiv_core_ips.log 2>&1 &
PID1=$!

echo "=== [2/4] Running prove_gate_equiv_icu_pcs.ys ==="
$YOSYS -s formal/prove_gate_equiv_icu_pcs.ys > formal/gate_equiv_icu_pcs.log 2>&1 &
PID2=$!

echo "=== [3/4] Running prove_gate_equiv_sram_wram.ys ==="
$YOSYS -s formal/prove_gate_equiv_sram_wram.ys > formal/gate_equiv_sram_wram.log 2>&1 &
PID3=$!

echo "=== [4/4] Running prove_gate_equiv_expanded.ys ==="
$YOSYS -s formal/prove_gate_equiv_expanded.ys > formal/gate_equiv_expanded.log 2>&1 &
PID4=$!

wait $PID1
echo "=== [1/4] prove_gate_equiv_core_ips.ys PASSED ==="
wait $PID2
echo "=== [2/4] prove_gate_equiv_icu_pcs.ys PASSED ==="
wait $PID3
echo "=== [3/4] prove_gate_equiv_sram_wram.ys PASSED ==="
wait $PID4
echo "=== [4/4] prove_gate_equiv_expanded.ys PASSED ==="

echo "=== ALL 12 RTL-VS-ASAP7-GATE EQUIVALENCE PROOFS COMPLETE ==="
grep -H "SUCCESS!" formal/gate_equiv_*.log
