// =============================================================================
// File: uvm_tb/sim_stage7a.cpp
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Verilator C++ Cycle-Accurate Testbench Harness for Stage 7A
//              (MLU-Link 5-Port Coherent NoC Router & C2C SerDes PCS).
// =============================================================================
#include <iostream>
#include <verilated.h>
#include "Vtb_stage7a_mlu_link.h"

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vtb_stage7a_mlu_link* top = new Vtb_stage7a_mlu_link;

    top->clk   = 0;
    top->rst_n = 0;

    // Reset for 5 cycles
    for (int i = 0; i < 10; ++i) {
        top->clk = !top->clk;
        top->eval();
    }
    top->rst_n = 1;

    int max_half_cycles = 200;
    int hcyc = 0;
    while (!Verilated::gotFinish() && hcyc < max_half_cycles) {
        top->clk = !top->clk;
        top->eval();
        if (top->clk && top->test_done_o) {
            break;
        }
        hcyc++;
    }

    bool pass = top->test_done_o && top->test_pass_o;
    std::cout << "[SIM_STAGE7A] Completed at half-cycle " << hcyc
              << " | PASS=" << (pass ? "YES" : "NO") << std::endl;

    delete top;
    return pass ? 0 : 1;
}
