# Sega X Board core — design notes

The approved plan lives in the project planning file; this document tracks
the decisions that matter for anyone reading the RTL, and the open questions.

## Clocking

One PLL: `clk_ram` 100 MHz, `clk_sys` 50 MHz (equal to the board's master
crystal, so the 68000 /4, pixel /8 and ADC /40 enables are exact), `SDRAM_CLK`
100 MHz at 180 degrees. The sound section (Z80, YM2151, 315-5218) really runs
from a 16 MHz crystal /4. The core keeps it in `clk_sys` with a modulo-25
enable (two pulses per 25 clocks, spacing 12/13) which averages exactly 4 MHz
with 10 ns jitter. A 16 MHz PLL output is reserved but unused.

## Memory map

BRAM: every CPU-visible RAM (tile, text, sprite x2, palette, road x2, backup
x2, shared sub RAM x2, Z80 RAM, PCM registers), the ROM caches and the line
buffers. SDRAM: every ROM, see `rtl/xb_pkg.sv` for the slots. DDR3 (MiSTer
DDRAM port): the two 512x256x16 sprite framebuffers.

The main CPU reaches the sub CPU's whole address space; on the PCB the sub
CPU is halted for the duration (MacDonald). The RTL models this as a bus
request/grant on the sub bus rather than dual-porting the shared RAM.

## ROM stream

`tools/pack_roms.py` and `tools/gen_mra.py` share `tools/romsets.py`. The
index-0 stream is `[64-byte descriptor][main][sub][z80][road][pcm][sprite]
[tile]`, each region padded to its slot. 68000 ROMs are interleaved so the
little-endian stream word reads back as the big-endian 68000 word; sprite ROMs
follow MAME's `REGION32_LE` order. `tools/tests/test_stream.py` expands the
MRA and checks it equals the packer output.

## Open questions (MAME vs real hardware)

| Topic | MAME | MacDonald | Core default |
| --- | --- | --- | --- |
| ADC channel select | IO#1 port C bits 4:2 (cites After Burner schematic) | bits 5:3 | MAME |
| Sprite x origin | 0xBE = screen x 0 | 0xB8 = framebuffer pixel 0 | MAME (parameter) |
| Zoom clamp | min 0x40 | valid range 0..0x3FF, odd behaviour above | MAME (parameter) |
| Sprite re-render without a $110000 write | re-renders every frame | not documented | re-render (parameter) |
| Framebuffer erase | fills before draw | not documented | erase on scanout |
| Timer at count 0xFFF | fires regardless of enable | same | same |
| Port C bit 1 (CONT) | ignored | "affects sprite hardware" | logged, ignored |
