// =============================================================================
// File: uvm_tb/uvm_soak_500k/sim_soak_500k.cpp
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Verilator 5.054 C++ Top-Level Driver for 500,000-Cycle Full-Chip
//              Randomized Soak Stress Test on mlu_chip_top (tb_soak_500k).
// =============================================================================
#include <chrono>
#include <iostream>
#include <verilated.h>
#include "Vtb_soak_500k.h"

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vtb_soak_500k* top = new Vtb_soak_500k;

    top->clk   = 0;
    top->rst_n = 0;

    auto t0 = std::chrono::steady_clock::now();
    long long half_cyc = 0;
    const long long max_half_cyc = 1000050LL;

    for (half_cyc = 0; half_cyc < max_half_cyc && !Verilated::gotFinish(); ++half_cyc) {
        if (half_cyc == 4) {
            top->rst_n = 1;
        }
        top->clk = !top->clk;
        top->eval();
    }

    auto t1 = std::chrono::steady_clock::now();
    double elapsed_sec = std::chrono::duration<double>(t1 - t0).count();
    double sim_khz     = (half_cyc / 2.0) / (elapsed_sec * 1000.0);

    std::cout << "[VERILATOR-5.054] Completed " << (half_cyc / 2)
              << " cycles in " << elapsed_sec << " s ("
              << sim_khz << " kHz)" << std::endl;

    top->final();
    delete top;
    return 0;
}
