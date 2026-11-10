#!/usr/bin/env python3
# =============================================================================
# File: formal/mutation_testing/run_20_mutants.py
# Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
# Description: Stage 17 Adversarial Mutation Testing Harness across 20 Synthetic
#              RTL Bugs (M01-M20). Runs each mutant in an isolated sandbox using
#              Yosys 0.60 SAT Formal Verification (sat -verify -prove-asserts)
#              without ever modifying the golden rtl/ or sram_ip/ directories.
# =============================================================================

import os
import re
import json
import time
import shutil
import subprocess
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT_DIR = Path(__file__).resolve().parents[2]
MUT_DIR  = ROOT_DIR / "formal" / "mutation_testing"
SBOX_DIR = MUT_DIR / "sandboxes"

MUTANTS = [
    {
        "id": "M01",
        "module": "mlu_sram_secded_ecc",
        "orig_rel": "sram_ip/mlu_sram_secded_ecc.sv",
        "ys_rel": "formal/prove_sram_ecc.ys",
        "description": "Flip bit 0 of H_ROW0 parity mask (8'h07 -> 8'h06) breaking Hsiao odd-weight column invariant",
        "target": "8'h15, 8'h0D, 8'h83, 8'h43, 8'h23, 8'h13, 8'h0B, 8'h07",
        "replacement": "8'h15, 8'h0D, 8'h83, 8'h43, 8'h23, 8'h13, 8'h0B, 8'h06",
        "property_violated": "SECDED Property 2/3: 100% Single-Bit Correction & Double-Bit Detection",
    },
    {
        "id": "M02",
        "module": "mlu_sram_secded_ecc",
        "orig_rel": "sram_ip/mlu_sram_secded_ecc.sv",
        "ys_rel": "formal/prove_sram_ecc.ys",
        "description": "Swap sec_err_o and ded_err_o parity classification condition",
        "target": "  assign sec_err_o = syn_nonzero & syn_odd_parity;\n  assign ded_err_o = syn_nonzero & (~syn_odd_parity);",
        "replacement": "  assign sec_err_o = syn_nonzero & (~syn_odd_parity);\n  assign ded_err_o = syn_nonzero & syn_odd_parity;",
        "property_violated": "SECDED Property 2/3: SEC vs DED Syndrome Parity Classification",
    },
    {
        "id": "M03",
        "module": "mlu_sram_sp_macro",
        "orig_rel": "sram_ip/mlu_sram_sp_macro.sv",
        "ys_rel": "formal/prove_sram_macro.ys",
        "description": "Disable spare-row repair address match (hit_spare_row = 1'b0)",
        "target": "  assign hit_spare_row = repair_en_i && (eff_addr == repair_bad_addr_i);",
        "replacement": "  assign hit_spare_row = 1'b0;",
        "property_violated": "SRAM Macro Property 1: Spare-Row Repair Remapping Invariance & Isolation",
    },
    {
        "id": "M04",
        "module": "mlu_sram_sp_macro",
        "orig_rel": "sram_ip/mlu_sram_sp_macro.sv",
        "ys_rel": "formal/prove_sram_macro.ys",
        "description": "Invert pwr_ready_o during light-sleep mode (slp_i)",
        "target": "  assign pwr_ready_o = (pwr_state_q == PWR_ACTIVE) && !slp_i && !dslp_i && !sd_i;",
        "replacement": "  assign pwr_ready_o = (pwr_state_q == PWR_ACTIVE) && slp_i && !dslp_i && !sd_i;",
        "property_violated": "SRAM Macro Property 2: Low-Power Gating Safety (!pwr_ready_o on slp_i)",
    },
    {
        "id": "M05",
        "module": "mlu_nram_banked_scratchpad",
        "orig_rel": "rtl/mlu_nram_banked_scratchpad.sv",
        "ys_rel": "formal/prove_nram_wram_mpu.ys",
        "description": "Break XOR bank-swizzling (bank_idx = lane_idx ignoring row_addr[2:0])",
        "target": "      lane_phys_bank[l] = swizzle_en_i ?\n                          (lane_raw_bank[l] ^ lane_row_addr[l][BANK_SEL_W-1:0]) :\n                          lane_raw_bank[l];",
        "replacement": "      lane_phys_bank[l] = lane_raw_bank[l];",
        "property_violated": "NRAM Property 1: XOR Bank-Swizzle Conflict-Free Column/Row Bijection",
    },
    {
        "id": "M06",
        "module": "mlu_nram_banked_scratchpad",
        "orig_rel": "rtl/mlu_nram_banked_scratchpad.sv",
        "ys_rel": "formal/prove_nram_wram_mpu.ys",
        "description": "Corrupt 2D matrix transpose indexing (out[r][c] = in[r][c] instead of in[c][r])",
        "target": "        if (transpose_en_i) begin\n          xbar_wdata_in[r][c*8 +: 8] = req_wdata_i[c][r*8 +: 8];",
        "replacement": "        if (transpose_en_i) begin\n          xbar_wdata_in[r][c*8 +: 8] = req_wdata_i[r][c*8 +: 8];",
        "property_violated": "NRAM Property 2: 8x8 Byte Matrix Transpose End-to-End Exactness",
    },
    {
        "id": "M07",
        "module": "mlu_wram_weight_buffer",
        "orig_rel": "rtl/mlu_wram_weight_buffer.sv",
        "ys_rel": "formal/prove_nram_wram_mpu.ys",
        "description": "Allow shadow DMA write into active ping_pong_sel_i bank",
        "target": "  assign shadow_buf_sel = ~ping_pong_sel_i;",
        "replacement": "  assign shadow_buf_sel = ping_pong_sel_i;",
        "property_violated": "WRAM Property 3: Ping-Pong Shadow DMA Write / Active Read Isolation",
    },
    {
        "id": "M08",
        "module": "mlu_mpu_shared_sram",
        "orig_rel": "rtl/mlu_mpu_shared_sram.sv",
        "ys_rel": "formal/prove_nram_wram_mpu.ys",
        "description": "Mask bit 3 of bcast_valid_o (4'b0111 instead of 4'b1111) during OP_MPU_BCAST_SRAM",
        "target": "  assign bcast_valid_o    = {NUM_IPUS{bcast_valid_q}};",
        "replacement": "  assign bcast_valid_o    = {1'b0, {(NUM_IPUS-1){bcast_valid_q}}};",
        "property_violated": "MPU SRAM Property 4: Multi-Cast Broadcast Consistency (4'b1111)",
    },
    {
        "id": "M09",
        "module": "mlu_bang_icu",
        "orig_rel": "rtl/mlu_bang_icu.sv",
        "ys_rel": "formal/prove_bang_icu_pmu.ys",
        "description": "Disable RAW hazard check on MEM_SPACE_NRAM in scoreboard",
        "target": "        if (is_scratchpad_space(dec_inst.src_space) &&\n            (sb_dst_space_q[s] == dec_inst.src_space) &&\n            (sb_dst_reg_q[s]   == dec_src_reg)) begin",
        "replacement": "        if (is_scratchpad_space(dec_inst.src_space) &&\n            (dec_inst.src_space != mlu_pkg::MEM_SPACE_NRAM) &&\n            (sb_dst_space_q[s] == dec_inst.src_space) &&\n            (sb_dst_reg_q[s]   == dec_src_reg)) begin",
        "property_violated": "BANG ICU Property 1: Scoreboard RAW Hazard Stall on MEM_SPACE_NRAM",
    },
    {
        "id": "M10",
        "module": "mlu_bang_icu",
        "orig_rel": "rtl/mlu_bang_icu.sv",
        "ys_rel": "formal/prove_bang_icu_pmu.ys",
        "description": "Allow instruction retirement/dispatch while OP_SYNC_CLUSTER barrier is active",
        "target": "  assign can_retire_ctrl = inst_valid_i && is_ctrl_inst && !dep_mask_hazard &&\n                           (is_sync_cluster ? (all_queues_idle && cluster_sync_ack_i) :\n                            is_sync_ipu     ? all_queues_idle : 1'b1);",
        "replacement": "  assign can_retire_ctrl = inst_valid_i && is_ctrl_inst && !dep_mask_hazard &&\n                           (is_sync_cluster ? 1'b1 :\n                            is_sync_ipu     ? all_queues_idle : 1'b1);",
        "property_violated": "BANG ICU Property 2: OP_SYNC_CLUSTER Barrier Queue-Idle Interlock",
    },
    {
        "id": "M11",
        "module": "mlu_pmu_clock_gate",
        "orig_rel": "rtl/mlu_pmu_clock_gate.sv",
        "ys_rel": "formal/prove_bang_icu_pmu.ys",
        "description": "Suppress 0-cycle wakeup on icu_dispatch_mask_i",
        "target": "      if (eng_busy_i[e] || icu_dispatch_mask_i[e]) begin",
        "replacement": "      if (eng_busy_i[e]) begin",
        "property_violated": "PMU Property 3: 0-Cycle Combinational Clock-Gate Wakeup on Dispatch",
    },
    {
        "id": "M12",
        "module": "mlu_tfu_fractal_mac",
        "orig_rel": "rtl/mlu_tfu_fractal_mac.sv",
        "ys_rel": "formal/prove_tfu.ys",
        "description": "Disable zero_skip_cnt_o increment in SPARSE_BLOCK_4X4 zero-block skip",
        "target": "              zero_skip_cnt_o <= zero_skip_cnt_o + 32'd1;",
        "replacement": "              zero_skip_cnt_o <= zero_skip_cnt_o;",
        "property_violated": "TFU Property 1: Cambricon-S SPARSE_BLOCK_4X4 Zero-Skip Telemetry Exactness",
    },
    {
        "id": "M13",
        "module": "mlu_tfu_fractal_mac",
        "orig_rel": "rtl/mlu_tfu_fractal_mac.sv",
        "ys_rel": "formal/prove_tfu.ys",
        "description": "Add +1 bias bug to PREC_INT8 dot product accumulation",
        "target": "        mlu_pkg::PREC_INT8: begin\n          mac_ops_beat = 32'd32;\n          for (int i = 0; i < 32; i++) begin",
        "replacement": "        mlu_pkg::PREC_INT8: begin\n          mac_ops_beat = 32'd32;\n          dot_prod_comb = 32'sd1;\n          for (int i = 0; i < 32; i++) begin",
        "property_violated": "TFU Property 2: Multi-Precision Zero-Operand Annihilation (PREC_INT8)",
    },
    {
        "id": "M14",
        "module": "mlu_tfu_fractal_mac",
        "orig_rel": "rtl/mlu_tfu_fractal_mac.sv",
        "ys_rel": "formal/prove_tfu.ys",
        "description": "Corrupt done_tag_o (tag_q ^ 8'h01)",
        "target": "  assign done_tag_o     = tag_q;",
        "replacement": "  assign done_tag_o     = tag_q ^ 8'h01;",
        "property_violated": "TFU Property 3: Completion Tag Preservation (done_tag_o == expected_tag_q)",
    },
    {
        "id": "M15",
        "module": "mlu_vfu_sfu_pipe",
        "orig_rel": "rtl/mlu_vfu_sfu_pipe.sv",
        "ys_rel": "formal/prove_vfu.ys",
        "description": "Replace saturating OP_BANG_VADD with wrapping 16-bit addition",
        "target": "      mlu_pkg::OP_BANG_VADD: begin\n        for (int i = 0; i < 8; i++)\n          res[(i*16) +: 16] = sat_s16(sext16(va[(i*16) +: 16]) + sext16(vb[(i*16) +: 16]));\n      end",
        "replacement": "      mlu_pkg::OP_BANG_VADD: begin\n        for (int i = 0; i < 8; i++)\n          res[(i*16) +: 16] = va[(i*16) +: 16] + vb[(i*16) +: 16];\n      end",
        "property_violated": "VFU Property 2: Saturating VADD Signed Overflow/Underflow Clamping",
    },
    {
        "id": "M16",
        "module": "mlu_vfu_sfu_pipe",
        "orig_rel": "rtl/mlu_vfu_sfu_pipe.sv",
        "ys_rel": "formal/prove_vfu.ys",
        "description": "Force softmax_sum_o to 0 on OP_BANG_SOFTMAX",
        "target": "            softmax_sum_o <= s1_l_new_q;",
        "replacement": "            softmax_sum_o <= 32'd0;",
        "property_violated": "VFU Property 3: Online Safe Softmax Strictly Positive Denominator (softmax_sum_o > 0)",
    },
    {
        "id": "M17",
        "module": "mlu_vfu_sfu_pipe",
        "orig_rel": "rtl/mlu_vfu_sfu_pipe.sv",
        "ys_rel": "formal/prove_vfu.ys",
        "description": "Swap min_val_o and max_val_o in OP_BANG_QUANT_STAT",
        "target": "            min_val_o   <= s1_min_q;\n            max_val_o   <= s1_max_q;",
        "replacement": "            min_val_o   <= s1_max_q;\n            max_val_o   <= s1_min_q;",
        "property_violated": "VFU Property 4: Cambricon-Q QuantStat Ordering Invariant (min_val_o <= max_val_o)",
    },
    {
        "id": "M18",
        "module": "mlu_mfu_dma_engine",
        "orig_rel": "rtl/mlu_mfu_dma_engine.sv",
        "ys_rel": "formal/prove_mfu_dma.ys",
        "description": "Write 8'hFF instead of 8'h00 for zero-masked bytes in OP_BANG_DECOMP_DMA",
        "target": "        dense_word[(k*8) +: 8] = 8'h00;",
        "replacement": "        dense_word[(k*8) +: 8] = 8'hFF;",
        "property_violated": "MFU DMA Property 1: Zero-Bitmap Hardware Decompression Zero-Byte Exactness",
    },
    {
        "id": "M19",
        "module": "mlu_link_noc_router",
        "orig_rel": "rtl/mlu_link_noc_router.sv",
        "ys_rel": "formal/prove_mlu_link.ys",
        "description": "Invert VC priority (grant VC0 over VC1 under contention)",
        "target": "          if (!out_grant_v[op] && vc1_valid_q[ip_idx] && (vc1_dst_p_q[ip_idx] == op[2:0])) begin\n            out_grant_v[op]    = 1'b1;\n            out_grant_in_p[op] = ip_idx;\n            out_grant_vc[op]   = 1'b1;\n            out_flit_s[op]     = vc1_flit_q[ip_idx];\n          end",
        "replacement": "          if (!out_grant_v[op] && vc0_valid_q[ip_idx] && (vc0_dst_p_q[ip_idx] == op[2:0])) begin\n            out_grant_v[op]    = 1'b1;\n            out_grant_in_p[op] = ip_idx;\n            out_grant_vc[op]   = 1'b0;\n            out_flit_s[op]     = vc0_flit_q[ip_idx];\n          end",
        "property_violated": "MLU-Link NoC Property 1: Strict VC1 Priority over VC0 under Contention",
    },
    {
        "id": "M20",
        "module": "mlu_c2c_serdes_pcs",
        "orig_rel": "rtl/mlu_c2c_serdes_pcs.sv",
        "ys_rel": "formal/prove_mlu_link.ys",
        "description": "Suppress nack_valid_o when CRC-16 check fails",
        "target": "        nack_valid_o = 1'b1;",
        "replacement": "        nack_valid_o = 1'b0;",
        "property_violated": "MLU-Link C2C PCS Property 2: Immediate NACK Assertion on CRC-16 Fault",
    },
]


def run_single_mutant(m: dict) -> dict:
    mid      = m["id"]
    sbox     = SBOX_DIR / mid
    sbox.mkdir(parents=True, exist_ok=True)

    orig_path = ROOT_DIR / m["orig_rel"]
    orig_text = orig_path.read_text(encoding="utf-8")
    if m["target"] not in orig_text:
        raise RuntimeError(f"[{mid}] Target snippet not found in {m['orig_rel']}")

    mut_text = orig_text.replace(m["target"], m["replacement"], 1)
    mut_sv   = sbox / orig_path.name
    mut_sv.write_text(mut_text, encoding="utf-8")

    ys_orig = (ROOT_DIR / m["ys_rel"]).read_text(encoding="utf-8")
    rel_mut_sv = f"formal/mutation_testing/sandboxes/{mid}/{orig_path.name}"
    ys_mut = ys_orig.replace(m["orig_rel"], rel_mut_sv)
    if m["ys_rel"] == "formal/prove_nram_wram_mpu.ys":
        ys_mut = ys_mut.replace("-seq 8", "-seq 4")

    ys_file  = sbox / f"prove_{mid}.ys"
    log_file = sbox / f"{mid}.log"
    ys_file.write_text(ys_mut, encoding="utf-8")

    t0 = time.time()
    proc = subprocess.run(
        ["yosys", "-s", str(ys_file)],
        cwd=str(ROOT_DIR),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    elapsed = round(time.time() - t0, 2)
    log_file.write_text(proc.stdout, encoding="utf-8")

    killed = ("FAIL!" in proc.stdout) or (proc.returncode != 0 and "ERROR: Assert" in proc.stdout)
    sat_probs = re.findall(r"Solving problem with (\d+) variables and (\d+) clauses", proc.stdout)
    vars_cnt  = int(sat_probs[-1][0]) if sat_probs else 0
    cls_cnt   = int(sat_probs[-1][1]) if sat_probs else 0

    return {
        "id": mid,
        "module": m["module"],
        "rtl_file": m["orig_rel"],
        "proof_script": m["ys_rel"],
        "description": m["description"],
        "property_violated": m["property_violated"],
        "killed": bool(killed),
        "status": "KILLED (SAT Counterexample Found)" if killed else "SURVIVED",
        "yosys_exit_code": proc.returncode,
        "sat_variables": vars_cnt,
        "sat_clauses": cls_cnt,
        "runtime_sec": elapsed,
        "sandbox_log": f"formal/mutation_testing/sandboxes/{mid}/{mid}.log",
    }


def main():
    SBOX_DIR.mkdir(parents=True, exist_ok=True)
    print("=" * 78)
    print(" Stage 17 Adversarial Mutation Testing Campaign (20 Synthetic RTL Mutants)")
    print("=" * 78)

    t_start = time.time()
    results_map = {}
    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = {ex.submit(run_single_mutant, m): m["id"] for m in MUTANTS}
        for fut in as_completed(futs):
            res = fut.result()
            results_map[res["id"]] = res
            print(f"  [{res['id']}] {res['module']:<28} | {res['status']} | {res['runtime_sec']:>5.2f}s | {res['sat_clauses']} clauses")

    ordered = [results_map[m["id"]] for m in MUTANTS]
    killed_cnt = sum(1 for r in ordered if r["killed"])
    total_cnt  = len(ordered)
    total_time = round(time.time() - t_start, 2)

    summary = {
        "campaign": "Cambricon Siyuan 590/690 Stage 17 Adversarial Mutation Testing",
        "engine": "Yosys 0.60 ezSAT / BMC Formal Verification (sat -verify -prove-asserts)",
        "total_mutants": total_cnt,
        "killed_mutants": killed_cnt,
        "survived_mutants": total_cnt - killed_cnt,
        "mutation_kill_rate_pct": round(100.0 * killed_cnt / total_cnt, 2),
        "wall_clock_sec": total_time,
        "golden_rtl_untouched": True,
        "mutants": ordered,
    }

    json_path = MUT_DIR / "mutation_results.json"
    json_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    md_lines = [
        "# Stage 17 Adversarial Mutation Testing Report (M01–M20)",
        "",
        f"- **Target Architecture**: Cambricon Siyuan 590 / 690 (`MLUarch05` / `MLUarch06` & `Cambricon-LLM/Q/S`)",
        f"- **Verification Engine**: Yosys 0.60 Formal SAT / Bounded Model Checking (`sat -verify -prove-asserts`)",
        f"- **Total Synthetic RTL Bugs Injected**: **{total_cnt}**",
        f"- **Mutants Killed (Counterexample Found)**: **{killed_cnt} / {total_cnt} ({summary['mutation_kill_rate_pct']:.1f}%)**",
        f"- **Golden RTL Integrity**: `rtl/` and `sram_ip/` 100% Untouched (Isolated Sandbox Execution)",
        f"- **Total Campaign Wall-Clock Time**: {total_time:.2f} s",
        "",
        "## Mutant-by-Mutant Kill Matrix",
        "",
        "| ID | Target RTL Module | Synthetic Bug Injected | Formal Property Violated | SAT Clauses | Time (s) | Result |",
        "|:--:|:------------------|:-----------------------|:-------------------------|------------:|---------:|:------:|",
    ]
    for r in ordered:
        badge = "**KILLED (`FAIL` CEX)**" if r["killed"] else "SURVIVED"
        md_lines.append(
            f"| `{r['id']}` | `{r['module']}` | {r['description']} | {r['property_violated']} | {r['sat_clauses']:,} | {r['runtime_sec']:.2f} | {badge} |"
        )
    md_path = MUT_DIR / "MUTATION_REPORT.md"
    md_path.write_text("\n".join(md_lines) + "\n", encoding="utf-8")

    print("=" * 78)
    print(f" MUTATION SCORE: {killed_cnt}/{total_cnt} ({summary['mutation_kill_rate_pct']:.1f}%) KILLED in {total_time:.2f}s")
    print("=" * 78)
    if killed_cnt != total_cnt:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
