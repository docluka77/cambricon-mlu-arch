# ==============================================================================
# Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
# Top-Level Build, Verification, Formal Proof & ASIC Synthesis Makefile
# ==============================================================================

SHELL := /bin/bash
PYTHON ?= python3
VERILATOR ?= verilator
YOSYS ?= yosys

UVM_SUITES := \
	uvm_sram_nram_wram \
	uvm_bang_icu_pmu \
	uvm_tfu_sparse_quant \
	uvm_vfu_llm_ops \
	uvm_mfu_dma_decomp \
	uvm_mlu_link_noc \
	uvm_mtp_cluster \
	uvm_mlu_chip_top \
	uvm_4chip_allreduce \
	uvm_cambricon_llm_kv

.PHONY: all help lint golden uvm formal gate-equiv mutate soak synth parity audit clean

all: lint golden parity audit

help:
	@echo "================================================================================"
	@echo " Cambricon Siyuan 590/690 (MLUarch05/06 & Cambricon-LLM/Q/S) Open-Source Suite"
	@echo "================================================================================"
	@echo "  make lint        - Run Verilator 5.054 --lint-only -Wall across all 18 RTL modules"
	@echo "  make golden      - Run Python bit-exact BANG ISA & LLM Golden Model test suite"
	@echo "  make uvm         - Run all 10 Accellera IEEE 1800.2-2020 UVM verification suites"
	@echo "  make formal      - Run all 10 Yosys 0.60 SAT/BMC RTL formal verification suites"
	@echo "  make gate-equiv  - Run 12-module ASAP7 7nm gate-level vs. RTL equivalence miters"
	@echo "  make mutate      - Run 20-mutant adversarial formal/UVM mutation testing suite"
	@echo "  make soak        - Run 500,000-cycle full-chip randomized BANG ISA soak stress test"
	@echo "  make synth       - Run Yosys 0.60 dual-foundry (ASAP7 7nm + Sky130) ASIC synthesis"
	@echo "  make parity      - Run energy/PPA & 10-paper / 6-patent / 5-MLU parity verifier"
	@echo "  make audit       - Run end-to-end 20-stage master regression & consistency audit"
	@echo "  make clean       - Remove simulation build directories (obj_dir*)"
	@echo "================================================================================"

lint:
	@echo "[LINT] Auditing all 18 SystemVerilog RTL modules with Verilator -Wall..."
	@$(PYTHON) -c "import subprocess, sys, run_master_audit as m; \
	fails = 0; \
	[print(f'  [PASS] {top}') if subprocess.run([m.VERILATOR if hasattr(m, \"VERILATOR\") else \"verilator\", \"--lint-only\", \"-Wall\", \"-sv\", \"-Irtl\", \"-Isram_ip\", \"--top-module\", top] + files).returncode == 0 else (print(f'  [FAIL] {top}'), setattr(sys.modules[__name__], 'fails', 1)) for top, files in m.RTL_MODULES]; \
	sys.exit(fails)"

golden:
	@echo "[GOLDEN] Running Python bit-exact BANG ISA & Cambricon-LLM/Q/S Golden Model..."
	@$(PYTHON) arch_model/test_cambricon_golden.py

uvm:
	@echo "[UVM] Executing all 10 Accellera UVM 2020.3.1 verification suites..."
	@for suite in $(UVM_SUITES); do \
		echo "  --> Running $$suite..."; \
		(cd uvm_tb/$$suite && bash run_$${suite}.sh); \
	done
	@$(PYTHON) results/parse_coverage.py

formal:
	@echo "[FORMAL] Running Yosys 0.60 SAT/BMC RTL formal verification suites (10/10)..."
	@bash formal/run_stage9_formal.sh
	@bash formal/run_stage10_formal.sh
	@cd formal && $(YOSYS) -s prove_4chip_oam_node.ys > formal_4chip_oam_node.log 2>&1
	@cd formal && $(YOSYS) -s prove_cambricon_llm_kv.ys > formal_cambricon_llm_kv.log 2>&1

gate-equiv:
	@echo "[GATE-EQUIV] Proving 12-module ASAP7 7nm Gate-Level Netlist vs. RTL Equivalence..."
	@bash formal/run_stage15_gate_equiv.sh

mutate:
	@echo "[MUTATION] Running 20-mutant adversarial formal & UVM fault-injection suite..."
	@$(PYTHON) formal/mutation_testing/run_20_mutants.py

soak:
	@echo "[SOAK] Running 500,000-cycle full-chip randomized stress test..."
	@cd uvm_tb/uvm_soak_500k && bash run_soak_500k.sh

synth:
	@echo "[SYNTH] Running dual-foundry (ASAP7 7nm + SkyWater 130nm) ASIC synthesis (36 netlists)..."
	@bash synth/run_synth_all.sh
	@bash synth/run_refresh_36.sh

parity:
	@echo "[PARITY] Auditing CMOS energy scaling, 10 ICT-CAS papers, 6 CN patents & MLU590/690 specs..."
	@$(PYTHON) energy_ppa/cambricon_energy_efficiency_model.py
	@$(PYTHON) energy_ppa/verify_literature_patent_parity.py

audit:
	@echo "[AUDIT] Running Master 20-Stage Quantitative Audit..."
	@$(PYTHON) run_master_audit.py

clean:
	@echo "[CLEAN] Removing Verilator simulation build caches..."
	@rm -rf obj_dir obj_dir_* obj_stage* uvm_tb/obj_stage* uvm_tb/*/obj_dir uvm_tb/*/build formal/mutation_testing/work*
