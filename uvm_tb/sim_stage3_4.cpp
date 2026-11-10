// =============================================================================
// File: uvm_tb/sim_stage3_4.cpp
// Description: Verilator 5.054 C++ Cycle-Accurate Driver for tb_stage3_4_icu_tfu
// =============================================================================
#include <iostream>
#include <verilated.h>
#include "Vtb_stage3_4_icu_tfu.h"

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vtb_stage3_4_icu_tfu* top = new Vtb_stage3_4_icu_tfu;

    top->clk_i  = 0;
    top->rst_ni = 0;

    // Reset for 4 cycles
    for (int i = 0; i < 8; ++i) {
        top->clk_i = !top->clk_i;
        top->eval();
    }
    top->rst_ni = 1;

    int cycle = 0;
    while (!top->test_done_o && cycle < 200) {
        top->clk_i = 0;
        top->eval();
        top->clk_i = 1;
        top->eval();
        cycle++;
    }

    bool pass = top->test_pass_o && (top->err_cnt_o == 0);
    std::cout << "[SIM_STAGE3_4] Completed at cycle " << cycle
              << " | pass=" << pass
              << " | errors=" << top->err_cnt_o << std::endl;

    delete top;
    return pass ? 0 : 1;
}
