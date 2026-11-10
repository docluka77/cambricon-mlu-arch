// =============================================================================
// File: uvm_tb/sim_stage2.cpp
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Verilator 5.054 C++ Cycle-Accurate Driver for Stage 2 Memory
//              Subsystem Verification (SECDED ECC, BIST, NRAM, WRAM, MPU SRAM).
// =============================================================================
#include <iostream>
#include <verilated.h>
#include "Vtb_stage2_mem_subsystem.h"

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vtb_stage2_mem_subsystem* top = new Vtb_stage2_mem_subsystem;

  top->clk   = 0;
  top->rst_n = 0;

  // Reset phase (10 half-cycles = 5 clock cycles)
  for (int i = 0; i < 10; ++i) {
    top->clk = !top->clk;
    top->eval();
  }
  top->rst_n = 1;

  int max_cycles = 1000;
  int cyc = 0;
  while (cyc < max_cycles && !top->test_done_o) {
    top->clk = 1;
    top->eval();
    top->clk = 0;
    top->eval();
    cyc++;
  }

  bool pass = top->test_done_o && top->test_pass_o;
  std::cout << "[SIM_STAGE2] Finished after " << cyc << " cycles. Verdict: "
            << (pass ? "PASS" : "FAIL") << std::endl;

  delete top;
  return pass ? 0 : 1;
}
