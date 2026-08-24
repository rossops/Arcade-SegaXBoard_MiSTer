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

## CPU buses (M1)

Both 68000s are fx68k behind `xb_m68k_bus`. A cycle is presented to the
board once AS is low and, for writes, UDS/LDS too (the 68000 asserts the data
strobes one state after AS on writes). Interrupt acknowledge cycles are
autovectored (VPA). Program ROM sits behind a 4 KB direct-mapped cache per
CPU (`xb_rom_cache`, 8-byte lines from a 4-word SDRAM burst); misses hold
DTACK.

The main 68000's `RESET` instruction resets the sub CPU (MAME
`m68k_reset_callback`; fx68k `oRESETn`). After Burner II's main program does
this three times during boot, so the sub restarts mid-initialisation exactly
as on the PCB.

Main accesses to 0x200000-0x2FFFFF go through the sub-space arbiter in
`xb_core`: a sub cycle that has started completes first; a sub cycle that
starts while the main holds the bus is deferred and replayed. The sub sees
DTACK withheld meanwhile (MacDonald: "the sub CPU is halted while an access
occurs").

### M1 verification

`tools/mame_trace.py` records MAME's executed PCs for both CPUs (MAME's
`-debugger osx` backend runs the script; `none` does not). The Verilator
harness (`verif/board`) logs each executed instruction's address by following
fx68k's prefetch queue (the address of the word captured into Irc, shifted
along with Ir and Ird), so the list is directly comparable to MAME's. `tools/trace_compare.py` then requires every MAME PC
to appear in order in the RTL list, tolerating two things MAME does not model
cycle-exactly: iteration counts of polling loops (collapsed on both sides)
and the instruction at which an interrupt lands (resync with a report).
Measured over 120 frames (2 s, 1.9M main / 2.3M sub instructions): main
97.7% matched with 745 resyncs, sub 99.6% with 299. Every remaining main
resync site reads data the sub CPU produces (`$014610` polls `$29C048`,
`$008AF8` and `$00B67E` read shared RAM) or depends on interrupt counts
(`$01461C` is the IRQ2 handler, `$014640` its ADC channel rotation); the sub's
are its handshake loops (`$556`, `$568`) and IRQ4 placement. `verif/board/
check_m1.sh` runs this gate. A note on the 315-5249: games read the quotient
with the instruction after the trigger write, so the divider completes in
8 clocks (4 bits/clock); the DTACK stall is only a safety net.

The service-mode memory test needs the text layer to read its result, so
that part of the M1 gate moves to M2.

## Video, tile layers (M2)

The 192 KB tile ROM lives in BRAM (`xb_tilerom`, three 64 KB planes, ~154
M10K) and is filled by the ioctl loader, instead of the SDRAM tile cache the
plan sketched: it removes an arbitration client and a worst-case miss storm,
and the BRAM budget still ends around 60%. `xb_tilemap_5197` renders the
next scanline of fg (register set 0), bg (set 1) and text into 320-entry
double-buffered line buffers at one pixel per clock (~1,050 clocks of the
3,200 per line), following MAME's tilemap_16b_draw_layer exactly: sets
latched at line 261, row scroll per 8 lines with the alternate-set bit,
column scroll per 16 pixels, 2x2 page quadrants, x = (0xC0 - xscroll). The
mixer is a direct port of screen_update's layer order and priority marks;
the palette applies MAME's resistor-weight tables (generated into
`xb_pal_lut.svh` by `verif/models/palette5242.py`).

Lessons: `xb_dpram` and `xb_tilerom` both register their outputs, so a
registered address costs two clocks to data; the tile colour field is bits
12:6 (it overlaps the code) and the text colour bits 11:9.

### M2 verification

`tools/mame_capture.py` (Lua autoboot) dumps tile/text/palette/sprite/road
RAM and a PNG at a chosen frame. `verif/models/tilemap16b.py` renders from
such a dump and is pixel-exact against MAME's PNG on every tile-opaque pixel
of frames 60, 150, 300 and 240 (attract). `verif/unit/tilemap/run_tilemap.py`
drives the RTL renderer with the same dumps under Icarus and is pixel-exact
per layer on all four. `tools/board_check.py` renders the model from the
RTL's own RAM dump (`+dumpframe`) and the whole board's frame is exact
(71,680/71,680 at frame 60). Board frames cannot be compared directly to
MAME's PNG at the same frame number because the game state drifts by a few
frames (cross-CPU timing), so the gate uses the RTL's own RAM state.

The service-mode capture (`--test`) does not yet engage the switch through
Lua; MAME input playback is the fallback when a text-only screen is needed.

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
