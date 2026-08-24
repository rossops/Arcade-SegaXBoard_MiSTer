// Verilator driver: 50 MHz clk_sys and 100 MHz clk_ram, phase-aligned.
#include "Vtb_board.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    int frames = 10;
    for (int i = 1; i < argc; i++) if (!strncmp(argv[i], "+frames=", 8)) frames = atoi(argv[i] + 8);
    Vtb_board* top = new Vtb_board;
    top->max_frames = frames;
    top->reset = 1;
    top->clk_sys = 0; top->clk_ram = 0;
    long cycle = 0;
    while (!Verilated::gotFinish()) {
        // clk_ram toggles every 5 ns, clk_sys every 10 ns
        top->clk_ram = !top->clk_ram;
        if (top->clk_ram) { /* rising clk_ram */ }
        if ((cycle & 1) == 0) top->clk_sys = !top->clk_sys;
        top->eval();
        cycle++;
        if (cycle == 40) top->reset = 0;
        if (cycle > 40 && (cycle % 20000000) == 0) fprintf(stderr, "frame %u\n", top->frame);
    }
    top->final();
    delete top;
    return 0;
}
