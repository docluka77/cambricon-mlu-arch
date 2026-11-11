#!/usr/bin/env python3
import glob
import os
import re

LIB_PATH = "/nfs/share/home/chenpei/hyr/latentcore_mla_dsa_20261103/synth/asap7_rvt_ff.lib"
FF_PATH  = "formal/asap7_ff_noninv.v"
OUT_CELLS = "uvm_tb/gls_asap7_sim/asap7_cells_sim.v"
OUT_NETS  = "uvm_tb/gls_asap7_sim/asap7_netlists_gls.v"

TARGET_MODULES = [
    "mlu_sram_secded_ecc",
    "mlu_pmu_clock_gate",
    "mlu_bang_icu",
    "mlu_mfu_dma_engine",
    "mlu_c2c_serdes_pcs",
    "mlu_cambricon_llm_flash_kv",
    "mlu_sram_sp_macro",
    "mlu_mpu_core",
]

def liberty_func_to_verilog(expr: str) -> str:
    s = expr.strip().strip('"').strip()
    if s == "0":
        return "1'b0"
    if s == "1":
        return "1'b1"
    # Handle postfix negation A' or (..)'
    while "'" in s:
        s = re.sub(r"([A-Za-z0-9_]+)'", r"(~\1)", s)
        s = re.sub(r"\(([^()]+)\)'", r"(~(\1))", s)
        if "'" in s:
            s = s.replace("'", "")
    s = s.replace("!", "~").replace("*", " & ").replace("+", " | ")
    # Insert implicit AND where two operands/parens are separated by space
    prev = None
    while prev != s:
        prev = s
        s = re.sub(r"([A-Za-z0-9_\)])\s+([A-Za-z0-9_\(~])", r"\1 & \2", s)
    return s

def parse_liberty(lib_path: str):
    with open(lib_path, "r", encoding="utf-8", errors="ignore") as f:
        text = f.read()
    cells = {}
    cell_iter = re.finditer(r"\bcell\s*\(\s*([A-Za-z0-9_]+)\s*\)\s*\{", text)
    for m in cell_iter:
        cname = m.group(1)
        start = m.end()
        depth = 1
        pos = start
        n = len(text)
        while pos < n and depth > 0:
            if text[pos] == "{":
                depth += 1
            elif text[pos] == "}":
                depth -= 1
            pos += 1
        body = text[start:pos-1]
        if "ff (" in body or "ff(" in body or "latch (" in body or "statetable" in body:
            continue
        inputs = []
        outputs = []
        for pm in re.finditer(r"\bpin\s*\(\s*([A-Za-z0-9_]+)\s*\)\s*\{", body):
            pname = pm.group(1)
            pstart = pm.end()
            pdepth = 1
            ppos = pstart
            bn = len(body)
            while ppos < bn and pdepth > 0:
                if body[ppos] == "{":
                    pdepth += 1
                elif body[ppos] == "}":
                    pdepth -= 1
                ppos += 1
            pbody = body[pstart:ppos-1]
            dm = re.search(r"direction\s*:\s*([A-Za-z]+)", pbody)
            fm = re.search(r"function\s*:\s*\"([^\"]+)\"", pbody)
            if not dm:
                continue
            dval = dm.group(1).lower()
            if dval == "input":
                inputs.append(pname)
            elif dval == "output" and fm:
                outputs.append((pname, liberty_func_to_verilog(fm.group(1))))
        if outputs:
            cells[cname] = (inputs, outputs)
    return cells

def main():
    os.makedirs("uvm_tb/gls_asap7_sim", exist_ok=True)
    cells = parse_liberty(LIB_PATH)
    with open(OUT_CELLS, "w", encoding="utf-8") as out:
        out.write("// Auto-generated ASAP7 7nm Standard-Cell Behavioral Primitives for Verilator GLS\n")
        out.write("/* verilator lint_off DECLFILENAME */\n")
        out.write("/* verilator lint_off UNOPTFLAT */\n\n")
        for cname in sorted(cells.keys()):
            ins, outs = cells[cname]
            ports = [f"input wire {p}" for p in ins] + [f"output wire {p}" for p, _ in outs]
            out.write(f"module {cname} ({', '.join(ports)});\n")
            out.write("  /* verilator inline_module */\n")
            for p, func_v in outs:
                out.write(f"  assign {p} = {func_v};\n")
            out.write("endmodule\n\n")
        # Append sequential DFF cells with deterministic 0 init
        with open(FF_PATH, "r", encoding="utf-8") as ff_f:
            ff_txt = ff_f.read().replace("reg Q;", "/* verilator inline_module */\n    reg Q = 1'b0;")
            out.write(ff_txt + "\n")
        out.write("/* verilator lint_on UNOPTFLAT */\n")
        out.write("/* verilator lint_on DECLFILENAME */\n")

    with open(OUT_NETS, "w", encoding="utf-8") as nout:
        nout.write("// Auto-wrapped ASAP7 7nm Gate-Level Netlists (prefixed with gls_)\n")
        nout.write("/* verilator lint_off DECLFILENAME */\n")
        nout.write("/* verilator lint_off UNOPTFLAT */\n")
        nout.write("/* verilator lint_off UNUSED */\n")
        nout.write("/* verilator lint_off UNDRIVEN */\n")
        nout.write("/* verilator lint_off PINCONNECTEMPTY */\n\n")
        for mod in TARGET_MODULES:
            npath = f"synth/{mod}_asap7_netlist.v"
            with open(npath, "r", encoding="utf-8") as nf:
                ntxt = nf.read()
            if mod == "mlu_mpu_core":
                idx = ntxt.find("module mlu_mpu_core(")
                if idx != -1:
                    ntxt = ntxt[idx:]
                ntxt = re.sub(
                    r"\\\$paramod\$[A-Za-z0-9_]+\\mlu_mpu_shared_sram\s+",
                    "mlu_mpu_shared_sram ",
                    ntxt,
                )
            mod_defs = re.findall(r"(?m)^\s*module\s+(\S+?)\s*\(", ntxt)
            sub_idx = 0
            for mname in mod_defs:
                if mname == mod:
                    ntxt = re.sub(rf"\bmodule\s+{re.escape(mod)}\b", f"module gls_{mod}", ntxt)
                else:
                    sub_new = f"gls_{mod}_sub_{sub_idx}"
                    sub_idx += 1
                    if mname.startswith("\\"):
                        ntxt = ntxt.replace(mname + " ", sub_new + " ")
                        ntxt = ntxt.replace(mname + "(", sub_new + "(")
                    else:
                        ntxt = re.sub(rf"\b{re.escape(mname)}\b", sub_new, ntxt)
            nout.write(ntxt + "\n\n")
        nout.write("/* verilator lint_on PINCONNECTEMPTY */\n")
        nout.write("/* verilator lint_on UNDRIVEN */\n")
        nout.write("/* verilator lint_on UNUSED */\n")
        nout.write("/* verilator lint_on UNOPTFLAT */\n")
        nout.write("/* verilator lint_on DECLFILENAME */\n")
    print(f"[GLS Gen] Emitted {len(cells)} combinational cells + 2 sequential DFF cells to {OUT_CELLS}")
    print(f"[GLS Gen] Emitted {len(TARGET_MODULES)} ASAP7 gate-level netlists to {OUT_NETS}")

if __name__ == "__main__":
    main()
