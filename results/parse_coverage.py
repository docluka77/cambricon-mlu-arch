import glob
import os
import re
import subprocess

VC = "/nfs/share/home/chenpei/verisegue_agent_v0/agent_v26/runs/uvm_gate0_20261104_221700/toolchain/verilator-5.054/bin/verilator_coverage"

print("=== 1. INDIVIDUAL UVM SUITE RUN LOGS & COVERAGE.DAT METRICS ===")
suites = sorted(glob.glob("uvm_tb/uvm_*"))
for s in suites:
    sname = os.path.basename(s)
    run_log = os.path.join(s, "uvm_run.log")
    soak_log = os.path.join(s, "soak_500k.log")
    cov_dat = os.path.join(s, "coverage.dat")
    summary_line = ""
    if os.path.exists(run_log):
        with open(run_log, encoding="utf-8") as f:
            for line in f:
                if "PASS" in line or "SUMMARY" in line or "Summary" in line:
                    if "UVM_INFO" in line:
                        summary_line = line.strip().split("] ", 1)[-1]
    elif os.path.exists(soak_log):
        summary_line = "500,000 cycles, 99,960 insts, 559,280 MACs, 4,998 barriers, 0 mismatches"
    cov_info = ""
    if os.path.exists(cov_dat):
        tmp_dir = f"/tmp/cov_{sname}"
        res = subprocess.run([VC, "--annotate", tmp_dir, cov_dat], capture_output=True, text=True)
        m_line = re.search(r"line\s*:\s*([\d.]+%\s*\(\s*\d+/\s*\d+\))", res.stdout)
        m_tog  = re.search(r"toggle\s*:\s*([\d.]+%\s*\(\s*\d+/\s*\d+\))", res.stdout)
        m_cg   = re.search(r"covergroup\s*:\s*([\d.]+%\s*\(\s*\d+/\s*\d+\))", res.stdout)
        cov_info = f"line={m_line.group(1) if m_line else 'N/A'} | toggle={m_tog.group(1) if m_tog else 'N/A'} | cg={m_cg.group(1) if m_cg else 'N/A'}"
    print(f"{sname:24s} | {cov_info} | {summary_line}")

print("\n=== 2. PER-MODULE RTL & UVM PKG COVERAGE FROM MERGED_UVM_COVERAGE.DAT ===")
# Parse merged_uvm_coverage.dat directly for exact line, toggle, and covergroup counts per file
file_stats = {}
with open("results/merged_uvm_coverage.dat", encoding="utf-8") as f:
    for line in f:
        if not line.startswith("C '"):
            continue
        parts = line.rsplit("' ", 1)
        if len(parts) != 2:
            continue
        meta = parts[0][3:]
        cnt = int(parts[1].strip())
        fields = meta.split("\x01")
        kv = {}
        for fld in fields:
            if "\x02" in fld:
                k, v = fld.split("\x02", 1)
                kv[k] = v
        fname = os.path.basename(kv.get("f", "unknown"))
        ctype = kv.get("t", "unknown")
        lineno = kv.get("l", "0")
        if fname not in file_stats:
            file_stats[fname] = {
                "line_pts": 0, "line_hit": 0, "lines": {},
                "tog_pts": 0, "tog_hit": 0,
                "cg_pts": 0, "cg_hit": 0
            }
        st = file_stats[fname]
        if ctype == "line":
            st["line_pts"] += 1
            if cnt > 0:
                st["line_hit"] += 1
            st["lines"][lineno] = st["lines"].get(lineno, 0) + cnt
        elif ctype == "toggle":
            st["tog_pts"] += 1
            if cnt > 0:
                st["tog_hit"] += 1
        elif ctype == "user" or "cover" in ctype or kv.get("page", "").startswith("v_user"):
            st["cg_pts"] += 1
            if cnt > 0:
                st["cg_hit"] += 1

print(f"{'File Name':36s} | {'Unique Lines':>18s} | {'Inst Line Pts':>18s} | {'Toggle Pts':>20s} | {'Covergroup Bins':>16s}")
print("-" * 120)
rtl_ul_hit, rtl_ul_pts = 0, 0
rtl_l_hit, rtl_l_pts, rtl_t_hit, rtl_t_pts = 0, 0, 0, 0
pkg_cg_hit, pkg_cg_pts = 0, 0
for fn in sorted(file_stats.keys()):
    if fn.startswith("mlu_") or fn.startswith("tb_"):
        st = file_stats[fn]
        ul_tot = len(st["lines"])
        ul_hit = sum(1 for v in st["lines"].values() if v > 0)
        ulp = f"{ul_hit}/{ul_tot} ({100*ul_hit/ul_tot:.1f}%)" if ul_tot else "-"
        lp = f"{st['line_hit']}/{st['line_pts']} ({100*st['line_hit']/st['line_pts']:.1f}%)" if st['line_pts'] else "-"
        tp = f"{st['tog_hit']}/{st['tog_pts']} ({100*st['tog_hit']/st['tog_pts']:.1f}%)" if st['tog_pts'] else "-"
        cp = f"{st['cg_hit']}/{st['cg_pts']} ({100*st['cg_hit']/st['cg_pts']:.1f}%)" if st['cg_pts'] else "-"
        print(f"{fn:36s} | {ulp:>18s} | {lp:>18s} | {tp:>20s} | {cp:>16s}")
        if fn.startswith("mlu_") and not fn.endswith("_if.sv") and not fn.endswith("_pkg.sv"):
            rtl_ul_hit += ul_hit
            rtl_ul_pts += ul_tot
            rtl_l_hit += st["line_hit"]
            rtl_l_pts += st["line_pts"]
            rtl_t_hit += st["tog_hit"]
            rtl_t_pts += st["tog_pts"]
        if fn.endswith("_pkg.sv"):
            pkg_cg_hit += st["cg_hit"]
            pkg_cg_pts += st["cg_pts"]

print("-" * 120)
print(f"16 RTL Modules Aggregate: UniqueLines={rtl_ul_hit}/{rtl_ul_pts} ({100*rtl_ul_hit/rtl_ul_pts:.2f}%), InstLines={rtl_l_hit}/{rtl_l_pts} ({100*rtl_l_hit/rtl_l_pts:.2f}%), Toggle={rtl_t_hit}/{rtl_t_pts} ({100*rtl_t_hit/rtl_t_pts:.2f}%)")
print(f"10 UVM Packages Covergroups: {pkg_cg_hit}/{pkg_cg_pts} ({100*pkg_cg_hit/pkg_cg_pts if pkg_cg_pts else 0:.2f}%)")
