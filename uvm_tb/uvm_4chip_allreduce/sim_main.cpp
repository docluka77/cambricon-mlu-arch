// =============================================================================
// File: uvm_tb/uvm_4chip_allreduce/sim_main.cpp
// Description: Verilator 5.054 C++ main entry point for Accellera UVM 2020.3.1
//              Suite 9 (mlu_4chip_oam_node 4-Way Ring/Butterfly AllReduce).
// =============================================================================
#include "Vtb_4chip_allreduce_top.h"
#include "verilated.h"
#include "verilated_cov.h"
#include <memory>

extern "C" int dpi_4chip_get_status();

int main(int argc, char** argv) {
  auto context = std::make_unique<VerilatedContext>();
  context->commandArgs(argc, argv);
  auto top = std::make_unique<Vtb_4chip_allreduce_top>(context.get());
  while (!context->gotFinish()) {
    top->eval();
    if (!top->eventsPending()) break;
    context->time(top->nextTimeSlot());
  }
  top->final();
  context->coveragep()->write("coverage.dat");
  return dpi_4chip_get_status();
}
