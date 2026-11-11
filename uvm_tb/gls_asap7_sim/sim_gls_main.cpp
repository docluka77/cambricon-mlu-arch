#include "Vtb_gls_asap7.h"
#include "verilated.h"
#include "verilated_cov.h"
#include <memory>

int main(int argc, char** argv) {
  const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
  contextp->commandArgs(argc, argv);
  const std::unique_ptr<Vtb_gls_asap7> top{new Vtb_gls_asap7{contextp.get(), "TOP"}};

  top->clk_i  = 0;
  top->rst_ni = 0;

  while (!contextp->gotFinish() && contextp->time() < 120000) {
    contextp->timeInc(5);
    top->clk_i = !top->clk_i;
    if (contextp->time() >= 40) {
      top->rst_ni = 1;
    }
    top->eval();
  }

  top->final();
#if VM_COVERAGE
  VerilatedCov::write("uvm_tb/gls_asap7_sim/gls_coverage.dat");
#endif
  return 0;
}
