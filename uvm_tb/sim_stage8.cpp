#include <iostream>
#include <verilated.h>
#include "Vtb_stage8_full_chip_cosim.h"

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vtb_stage8_full_chip_cosim* top = new Vtb_stage8_full_chip_cosim;

    top->clk   = 0;
    top->rst_n = 0;

    for (int half_cyc = 0; half_cyc < 400 && !Verilated::gotFinish(); ++half_cyc) {
        if (half_cyc == 4) {
            top->rst_n = 1;
        }
        top->clk = !top->clk;
        top->eval();
    }

    top->final();
    delete top;
    return 0;
}
