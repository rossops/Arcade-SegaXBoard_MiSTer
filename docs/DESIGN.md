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

## Sprites, 315-5211A (M3)

`xb_sprite_5211` (clk_ram) walks the renderer bank of sprite RAM and draws
into one of two 512x256x16 framebuffers in DDR3 through `xb_fb_if` (forked
from the System 32 core: pixel runs assembled per row and flushed as 64-bit
words with byte enables, whole-line reads into a ping-pong line RAM, line
erase). The row/zoom/pitch/end-code algorithm is MAME's
sega_outrun_sprite_device::draw with the X Board fields; MAME keeps the row
base (`addr`, advanced by pitch) separate from the row's working pointer
(`data[7]`), and so does the RTL. Sprite ROM comes from SDRAM port p2 in
128-bit bursts (four 32-bit words), cached one burst at a time.

Sequencing follows MacDonald, not MAME: a `$110000` write swaps the sprite
RAM banks and starts a render; the render first erases the back buffer (256
lines, ~33k clocks) and is aborted at the start of vblank; at vblank the
buffers swap only if a render ran. MAME re-renders the buffered list every
frame, which is an emulator convenience — an earlier version that also
re-rendered at vblank produced frames mixing two lists. Empty pixel = 0xFFFF
(MAME's transparent value). The sprite pixel keeps its shadow bit; the mixer
applies MAME's rule (bits 14 and 3:0 == 0x400A selects the effects palette of
the pixel underneath), so no read-modify-write is needed and `wr_shadow` is
tied low.

Render time on the captured attract lists: 2.6 / 4.9 / 3.8 ms per frame at
100 MHz (heaviest: 52k opaque pixels, 29% of a frame). Raw opaque throughput
is about 11 Mpix/s, under the 25 Mpix/s the plan pencilled in; the practical
criterion (every captured frame renders well inside a frame) holds with 3x
margin. If a real scene ever overruns, overlapping a row's DDR flush with the
next row's ROM fetch is the first optimisation.

### M3 verification

`tools/mame_capture.lua` taps the `$110000` write and saves the list about to
be rendered (`spritelist.bin`). `verif/models/sprite5211.py` + the tile mix
are pixel-exact against MAME's PNG on frames 60/150/300 (priorities and
shadow pen included). `verif/unit/sprite/run_sprite.py` drives the RTL
renderer, `xb_fb_if` and the DDRAM model with the same lists and is exact on
all three. `tools/board_check.py` (with the RTL's sprite RAM dumped at the
dump frame and the frame before) is exact on the whole board at frame 60.
`verif/board/check_m3.sh` runs this.

## Road, 315-5275 (M4)

`xb_road_5275` is a per-line port of MAME's segaic16_road_outrun_draw with
the X Board parameters (colour bases 0x1700/0x1720/0x1780, xoffs -166,
control mask 7). Per line it reads the six road RAM words (line words,
h positions, colours; direct scanline addressing when control bit 2 is set),
builds MAME's colour table, then produces one pixel per two clocks from the
two roads' bitplane bytes with the priority map. The 64 KB road ROM sits in
BRAM (`xb_roadrom`, two read ports), filled by the loader. Road RAM is the
double-buffered pair in `xb_core`, swapped on the control read; the renderer
reads the bank the sub CPU is not writing. The background pass (solid line
colour) and the foreground pass feed the mixer in MAME's order.

### M4 verification

The capture Lua taps the sub CPU's control read (`$EE000`; the main-CPU
mirror is never used) to save the buffer that will be displayed, and the
control write for its value. With `verif/models/road5275.py` the Python
model of tiles + sprites + road reproduces MAME's PNG on **every pixel** of
frames 60, 150 and 300 (`tools/road_check.py`). The standalone RTL bench
(`verif/unit/road/run_road.py`) is exact on all three, and the whole board is
exact at frame 60 (`tools/board_check.py`). `verif/board/check_m4.sh` runs
all of it. Note for the board sim: `+roadrom` and `+tilerom` read hex files
from the run directory, which `make run` links in; running the binary by
hand without them silently renders from empty ROMs.

## Sound (M5)

`xb_soundsys`: T80s Z80 with a 4 MHz enable (2 pulses per 25 clk_sys),
jt51 (cen 4 MHz, cen_p1 2 MHz), `xb_segapcm_5218` ticked at 4 MHz/128, a
1 KB ROM cache over SDRAM p5 (WAIT_n on a miss), 2 KB work RAM, the
315-5250 sound latch on port 0x40 (read clears NMI), YM2151 IRQ to INT,
Z80 reset from I/O chip port C bit 0, mute from port D bit 7. Mix is MAME's:
PCM x 0.35 + YM x 0.15 (90/256 and 38/256). The PCM engine is a sequential
port of MAME's per-channel loop (loop/end/stop semantics, bank bits 6:4,
address write-back and the 8-bit fraction), reading ROM bytes from SDRAM
port p6; the stream pads the PCM slot with 0xFF like MAME's ERASEFF region.
Simulation builds use the Verilog tv80 (`verif/board/tv80`, sim only,
behind XB_Z80_TV80, clocked from an 8 MHz enable toggle) because Verilator
and Icarus cannot compile the VHDL T80.

### M5 verification

`test_segapcm.py` (cocotb) matches the Python port of MAME's SegaPCM tick
for tick over 600 ticks of random channel programming, including register
write-back. The board test presses Coin 1 at frame 30 (`+coin`, and
`tools/mame_coin.lua` for MAME) so sound starts immediately; `tools/
wav_compare.py` compares the tb's 48 kHz capture with MAME's `-wavwrite`.
Result: per-second RMS 997/679/671 vs 953/668/648, identical dominant
tones, envelope (5 ms RMS) correlation 0.96 at 0 ms lag; sample-level
correlation is only 0.43 because two FM implementations with slightly
different CPU timing drift in phase, so the gate uses the envelope (>= 0.9).
`verif/board/check_m5.sh` runs it.

## Playability (M6)

- DIP switches come from the MRA `<switches>` block, delivered by the HPS
  as ioctl index 254 (byte 0 = SWA coinage, byte 1 = SWB). Defaults FF,DD
  are MAME's (1C/1C, upright 1, throttle lever, 3 lives, continue, normal).
  The `DIP;` line in the config string exposes them in the OSD.
- Backup RAM (2 x 16 KB) is NVRAM index 3: written from the host during a
  download (the CPU is in reset), read back through the RAMs' second ports
  on upload; the core raises `ioctl_upload_req` when the game writes the
  RAM, at most once every ~2 s.
- Analog: MiSTer's signed axes map to MAME's After Burner ranges (X
  0x20..0xE0, Y 0x40..0xC0 with PORT_REVERSE so stick up reads high),
  throttle on the right stick's Y; the D-pad emulates full deflection.
- Pause: a mapped button or "OSD open" freezes both 68000s and the sound
  section's clock enables.
- ROM caches: Quartus 17 built the sub-CPU cache out of flip-flops (16k
  ALMs), so `xb_rom_cache` instantiates `altsyncram` for its line and tag
  storage with a one-clock read pipeline. The first version of that pipeline
  re-decided the held request on the clock after a fill, reading a line the
  RAM had just been written with; the read is stale for a clock, so every
  miss became two fetches and the design depended on the RAM's
  read-during-write behaviour, which is where the behavioural simulation
  and the M10K differ. On hardware the Z80 ran but produced no sound (build
  #9); the 68000s got away with it. The cache now serves the held request
  straight from the fill data and never re-decides a served request.
  Confirmed on hardware with build #11 (2026-08-25): the previous
  implementation ran next to the fixed one on the Z80 as a shadow with
  divergence flags; both produced sound and never diverged. The scaffolding
  was removed afterwards; git history has it (`xb_rom_cache_ff`).

## More games (M7)

- Sets: `aburner` (After Burner ver 1.32) and its clone `aburner131`,
  `thndrbld1` (Thunder Blade deluxe/standing, unprotected) and `thndrbldd`
  (the decrypted bootleg of the upright set). The parent `thndrbld` is an
  FD1094 (317-0056) set and needs a decryption block the core does not have
  yet; the same applies to Super Monaco GP, Racing Hero, AB Cop, Line of
  Fire, GP Rider and Last Survivor.
- After Burner is After Burner II's board configuration (road under the
  tile layers) with its own DIP table: MAME's defaults are cabinet Upright,
  demo sounds on, "3x credits" lives, continue allowed, normal difficulty.
- Thunder Blade uses the default road priority (road over the bg/fg
  tilemaps, under text), 256 KB main and sub ROMs (the 512 KB slots keep
  the layout), and a different analog wiring: stick X on ADC0 reversed,
  throttle on ADC1, stick Y on ADC2, all full range. The descriptor's
  analog mode selects that mapping inside the core, which now does the
  range shaping (the top level passes raw MiSTer axes). MAME's
  `draw_write` writes 0xFFFF into word 0 of the sprite RAM bank handed back
  to the CPU after the swap ("hack for thunderblade"); After Burner II is
  pixel-exact without it, so it is enabled per game by the descriptor.
- After Burner (1.32) frames are not compared against MAME pixel for pixel:
  the game samples the stick in its timer interrupt and recomputes the
  plane's bank only when the sample moves by more than 2. In MAME the main
  loop runs between the first ADC read (0x00, the ADC0804's power-up value)
  and the second (0x80), takes 0x00 as the stick position and banks the
  plane by -127, and since every later sample is 0x80 it never recomputes,
  so MAME's demo plane stays banked. In the RTL the second sample lands
  first and the plane is level. A boot-time race on a power-up-undefined
  value; the frames are otherwise identical (tiles, road, other sprites)
  and the RTL frame is self-consistent with the models.
- Clone ROMs sit in subdirectories of the parent's merged zip; the MRAs
  name `clone.zip|parent.zip` and every tool matches ROM files by basename.
- Verification: `verif/board` takes `GAME=` (hex images under
  `verif/golden/<set>`, descriptor flags as plusargs), `board_check.py` and
  `model_check.py` take the set name.
- Frame comparisons against MAME now allow a small phase window
  (`tools/frame_match.py`, best of +-3 frames, 99%): the M6 ROM cache fix
  changed the CPUs' bus timing by a clock per access and After Burner II's
  timeline now sits two frames behind MAME's frame numbering (99.2-99.8%
  at the offset; the rest is blinking text and one frame of motion on fast
  sprites). Thunder Blade matches at offset 0. `check_m7.sh` runs the gate.

## Super Monaco GP (M8)

- Set: `smgpd`, MAME 0.289's decrypted bootleg of the World Rev B set; the
  official sets are FD1094 317-0126a and wait for the decryption block.
- Board differences, all selected by the descriptor: a second sound board
  (Z80 + 315-5218, the deluxe cabinet's rear speakers) fed by the same
  315-5250 latch and NMI, with its own 64 KB ROM and 512 KB PCM ROM as two
  extra stream regions on SDRAM ports p3 and p4 (the stream ends after the
  last region a set populates, so older MRAs are unchanged); its output is
  summed into L/R with saturation behind the "Rear speakers" OSD option.
  `xb_soundsys` takes `HAS_YM` (0 drops the YM2151) and base-address
  parameters. I/O chip 0 port A reads bits 5:0 as 0 (MAME `smgp_motor_r`).
  The `/EXCS` region (`$2F0000-$2F3FFF`, the link and motor boards) reads
  0xFFFF and ignores writes, as in MAME; single-machine play with the
  "Number of Machines" DIP at 1. There is no road ROM: the slot stays zero.
- Analog mode 2 (driving): steering 0x38..0xC8 on ADC0, gas 0x38..0xB8 on
  ADC1 and brake 0x28..0xA8 on ADC2 (MAME's ranges) from the right stick's
  Y axis (up = gas, down = brake) or the Gas/Brake buttons; Shift Down/Up
  on the first two buttons.

## FD1094 (M9)

- Several X Board sets run on a Hitachi FD1094, a 68000 with a decryptor
  and an 8 KB battery-backed key: Thunder Blade (317-0056), Super Monaco
  GP (317-0126a and friends), Racing Hero, AB Cop, Line of Fire, GP Rider
  and Last Survivor. Only program-space fetches are decrypted; the mapping
  is a per-word bitswap/XOR network driven by a key byte per address (the
  key repeats every 0x2000 words), three global key bytes and an 8-bit
  state. The state is 0 at reset, `key[0]` while in IRQ mode, and the
  program changes it with `CMPI.L #$00xxFFFF,D0` ($01xx also leaves IRQ
  mode, $02xx enters it, $03xx leaves it); an interrupt acknowledge enters
  IRQ mode and RTE leaves it. A last step replaces PC-relative opcodes with
  0xFFFF (a fixed list, plus the branch families when the key byte's F bit
  is set). MAME's `fd1094.cpp` is the reference.
- The RTL vendors jtcores' decryptor and control block (`rtl/cpu/fd1094/`,
  Jose Tejada, GPL-3): the control block watches supervisor program-space
  fetches on the bus and applies the state changes at fetch time, which is
  what the real chip evidently does since that model runs the FD1094
  System 16 games. `xb_fd1094` wraps them with the key RAM (filled from the
  stream's 8 KB key region by the loader; `+keyrom` preloads it in
  simulation), the function-code decode (program/data, supervisor,
  interrupt acknowledge from the raw AS) and a one-clock ack delay for the
  registered output. It sits between the main CPU's ROM cache and the bus
  and is transparent, without added latency, unless the descriptor's
  FD1094 flag is set.
- Verification: `verif/models/fd1094.py` is a line-for-line port of MAME's
  `decrypt_one` (the masked-opcode list is parsed from the vendored
  Verilog so both share one table); `test_fd1094.py` checks the RTL
  decryptor against it on 30k random address/state/value triples with the
  real Thunder Blade key, then the encrypted `thndrbld` and `smgp` parents
  run through the board against MAME frames and CPU traces. Results:
  both parents boot through the block and are pixel-exact against MAME at
  frames 60/150/300; Thunder Blade's main CPU trace matches 99.80%. Its
  sub CPU (plain ROM, untouched by the FD1094) scores 93% on the M1 gate
  in both the encrypted and the decrypted set: that game's boot is polling
  loops the collapse heuristic handles poorly, so the sub gate is not part
  of `check_m9.sh`.

## Racing Hero and A.B. Cop (M10)

- Sets: `rachero` (FD1094 317-0144) with its decrypted bootleg `racherod`;
  `abcop` / `abcopj` (317-0169b) with `abcopd` / `abcopjd`. Plain X Board
  configurations: default road priority, no motor, no second sound board;
  Racing Hero has no road ROM (zero slot, as Super Monaco GP), A.B. Cop has
  one. The merged `abcop.zip` stores the bootleg odd ROM shared by both
  bootlegs under `abcopd`'s name, so `abcopjd` references that name.
- Analog mode 3: steering 0x20..0xE0 reversed on ADC0 (MAME's PORT_REVERSE
  paddle, done in the mapping rather than through `adc_reverse` so the
  centre stays 0x80), gas 0x00..0xFF on ADC1 and brake on ADC2 from the
  right stick's Y axis or the Gas/Brake buttons. A.B. Cop's Jump is the
  second button; Racing Hero has none.
- DIP layout shared by both: Credits, Demo Sounds, Allow Continue, Time,
  Difficulty (MAME defaults `FF,F9`).

## Long-term: enhanced sprite resolution (parked)

An opt-in OSD mode rendering at 640x448 without touching gameplay timing.
The tile, text and road layers carry no detail beyond 320x224 (8x8 bitmaps
and per-line patterns at integer positions), so a 2x render of those is
plain pixel doubling; the gain is in the sprites, whose zoom accumulators
step through source pixels in 1/512 units: sampling at half steps makes
shrunk sprites sharper and steadier (magnified ones get smoother steps).
What it needs: a 2x video timing (800x524 at 12.5 MHz, same 262-line frame
and 59.64 Hz so the CPUs, interrupts and handshakes keep the hardware
timing), a sprite renderer sampling at 2x into 1024x512 DDR3 framebuffers
with two pixels per clock (the heaviest frame today takes ~4.9 ms of the
16.7 ms budget at one pixel per clock), `xb_fb_if` runs and line buffers at
the 2x rate, doublers for the other layers. Estimate: +4-6k ALMs. No MAME
reference exists for the 2x sprites; verification would compare against a
2x mode of `verif/models/sprite5211.py`. The accurate 320x224 path stays
the default and unchanged.

## Framework gamma correction (M15)

`arcade_video` was instantiated with `GAMMA(0)` from the first hardware
build (M5/M6): Quartus 17 could not see the `gamma_bus` port through the
framework's `.*` connection, and disabling gamma was the quick way past it.
It is now `GAMMA(1)` with `gamma_bus` declared in `emu` and connected
explicitly to both `hps_io` and `arcade_video`. That gives the framework's
standard "Gamma correction" OSD curves (the video mixer drives
`gamma_bus[21]` so the menu shows them) for a few hundred ALMs and one M10K
for the LUT; the game image itself is untouched and the board simulation
does not see the change. Scaling and interpolation stay with the framework's
scaler filters; a core-side "improved scaling" mode would only
re-interpolate the same 320x224 pixels.

The enhanced-sprite work (M14) is parked on the `m14-enhanced-sprites`
branch; its notes are in that branch's copy of this file.

### M10K budget

Build #22 fit at exactly 553 of 553 M10K blocks. Earlier builds only
logged block memory bits (74-78%), which hid how close the block count
had crept to the ceiling: 8- and 16-bit wide memories only use 80% of
each 10-bit-wide block, and the road ROM, a behavioural array with one
write and two read ports, was being built as two copies (64 + 32 blocks
for 64 KB). `xb_roadrom` is now an explicit true-dual-port altsyncram
(loader write and read 0 on port A, read 1 on port B): 64 blocks. Build
#23 landed at 545/553: the three-port version had cost more logic and
bits than blocks (1,400 ALMs and 232 Kbit came back, 8 blocks), so the
ceiling is still close. Check the "M10K blocks" line of `fit.rpt` after
every build. The next lever, if a milestone needs more, is the plan's
original SDRAM tile cache: the tile ROM is 192 blocks.

## MiSTer-devel standards (M16)

Changes made so the repository matches Template_MiSTer and the wiki's
"Contributing a Core" page, ahead of offering the core to MiSTer-devel:

- `sys/` is the template's, file for file. It had been the System 32
  core's snapshot with local edits (a 512-pixel scaler limit, extra
  `MISTER_DISABLE_DOWNSCALE`/`MISTER_DISABLE_SHADOWMASK` macros, an OSD
  register stage, an older `hps_io`/`ascal`/`sys_top.sdc`). Those macros
  are gone from the `.qsf`; the standard `MISTER_DOWNSCALE_NN`,
  `MISTER_DISABLE_ADAPTIVE`, `MISTER_DISABLE_YC`, `MISTER_DISABLE_ALSA`
  stay. The downscaler and shadow mask come back with the stock
  framework, which costs logic and a few M10K blocks; the block count
  after this change is the number to watch (545/553 before it).
- The git SHA in the OSD version line: `sys/build_id.tcl` cannot be
  edited, so the extended script lives in `tools/build_id.tcl` and the
  `.qsf` points `PRE_FLOW_SCRIPT_FILE` at it after `source sys/sys.tcl`.
- PLL where the framework expects it: `rtl/pll.v` and `rtl/pll.qip`
  (`sys/pll_q17.qip` includes `rtl/pll.qip`); `files.qip` no longer lists
  it.
- `.gitignore`, `clean.bat` and `Arcade-SegaXBoard.srf` from the template.
- `.qsf` from the template as well. The inherited one had the System 32
  core's fitter choices (physical synthesis off, multicorner analysis on,
  aggressive routability, power-up don't-care off); the template turns
  physical synthesis on and multicorner off. Only five lines differ from
  the template now: the project comment, "Lite Edition", the four
  standard trim macros switched on, the `PRE_FLOW_SCRIPT_FILE` for the git
  SHA, and `OPTIMIZE_HOLD_TIMING "ALL PATHS"` (builds #15 and #17 had
  hold violations on MLAB paths with the default). Build #25 is the
  first with these fitter settings.
- MRAs: one primary per game in `releases/`, the other versions under
  `releases/_alternatives/_<game>/` (`alt` field in `romsets.py`,
  `gen_mra.py`, `make_db.py`).
- Still to do: rename the repository `Arcade-SegaXBoard_MiSTer` (README
  and `make_db.py --repo` follow), then the adoption email.

## Analog sensitivity (M17)

The stick and wheel axes map linearly from the MiSTer axis (-128..127)
onto each game's ADC range (`xb_core`: After Burner +-0x60/+-0x40, Super
Monaco GP +-0x48, Racing Hero and A.B. Cop +-0x60, Thunder Blade and GP
Rider full range). A cabinet stick or wheel has travel and a spring; a
thumbstick reaches full deflection in a few millimetres, so the games felt
twitchy around centre.

- OSD "Analog response": Linear (the board's mapping, bit-exact
  pass-through), Soft (`|out| = |in|^2 / 128`: half deflection gives a
  quarter of the range), Softer (`|in|^3 / 16384`). Full lock stays
  reachable (-128 maps to -128): After Burner's rolls and the driving
  games' full steering need the extremes, so a plain gain cut would have
  been the wrong tool. The curves flatten the centre enough that a stick
  resting a few counts off zero reads as zero; there is no separate
  deadzone.
- OSD "Analog range": 100 / 75 / 50%, scales the magnitude after the curve
  for people who want less reach as well. Off (100%) by default.
- `rtl/io/xb_ana_shape.sv`: three registered stages (magnitude, square,
  cube) and a combinational pick; one instance each for the P1 stick's X
  and Y and the throttle axis (the right stick's Y, which is also gas and
  brake in the driving games). Applied in `xb_core` before the per-game
  mapping, only for analog modes 0..4: Line of Fire's lightgun and cursor
  paths and the D-pad path take the raw axes. Latency is four `clk_sys`
  clocks against a 1.25 MHz ADC sample.
- Status bits O[24:23] and O[26:25] (O[22] is the parked M14 branch's).
- Verification: `verif/unit/chips/test_ana_shape.py` checks every input
  value against a Python model for all curves and ranges (2304 cases);
  the board frame check confirms Linear/100% leaves the 1x path exact.
  MAME has no equivalent, so the feel itself is a hardware judgement.

## Later: CPU overclock (parked)

An opt-in OSD "CPU speed" (12.5 / 15 / 18.75 / 25 MHz) for both 68000s,
default 12.5. The CPU clock enables come from `clk_sys`: 25 MHz is the /2
pattern (fx68k's documented maximum, two clocks per phase, which the ROM
caches and SDRAM already serve), 15 and 18.75 MHz are uneven patterns
(3-in-10, 3-in-8) of the kind the sound section already uses. Everything
else keeps the hardware rate: the 262-line frame and vblank, the 315-5250
scanline timer, the sound section, the ADC conversion enable (kept
independent of the CPU clock), sprite and road generators. The games run
their logic once per frame, so the visible effect is the removal of
slowdown in scenes that overrun a frame on the PCB; nothing else changes.
Risk: cross-CPU races and timing assumptions can flip (After Burner's
stick-sampling race is an example), the usual "may cause glitches" caveat.
Both CPUs change together. Work: the enable generator in `xb_core`, a
check that `xb_m68k_bus` is enable-agnostic at two clocks per phase, and
boot/self-consistency sims at each speed (no MAME reference for the
timing). No timing-closure impact, `clk_sys` is unchanged.

## GP Rider (M11)

- Single-board sets `gpriders` (World, 317-0163), `gpriderus` (US,
  317-0162, files under `gprideru/` in the merged zip) and `gpriderjs`
  (Japan, 317-0161, `gpriderj/`); the twin-cabinet sets need a second PCB
  and are out of scope. No decrypted bootlegs exist, so bring-up went
  straight through the FD1094.
- MAME's `m_gprider_hack`: with the link board absent the game must never
  see interrupt level 6, so when the timer and vblank interrupts coincide
  the main CPU is presented level 4 and the timer follows (descriptor flag,
  byte 1 bit 6).
- Analog mode 4: steering full range, gas and brake 0x10..0xEF (MAME's
  ranges); Shift Down/Up on the first two buttons. DIPs: Cabinet
  (Upright/Ride On), ID No. (Main/Slave), Demo Sounds, Difficulty
  (default `FF,FE`). The analog mode field is now 3 bits.

## Last Survivor (M12)

- Sets `lastsurv` (FD1094 317-0083) and `lastsurvd` (decrypted bootleg,
  `lastsurvd/` in the merged zip). Plain X Board configuration without a
  road ROM; the network board is not modelled (Network DIP off).
- Inputs go through a multiplexer (descriptor byte 1 bit 7): I/O chip 0
  port D bits 6:5 select what I/O chip 1 port B returns - group 0 = P2
  stick and aim, 1 = P1 stick and aim, 2 = the two attack buttons, 3 =
  nothing (MAME `lastsurv_muxer_w` / `lastsurv_port_r`; bit 7 of the same
  port is the mute the core already models). Each player's aim is an
  8-position rotary read back as a 4-bit active-low direction pattern
  (MAME `lastsurv_position_table`); the core derives it from the player's
  right stick and holds the last direction when the stick is released
  (up after reset). Player 2 comes from the second controller; the top
  level now takes both players' analog sticks from `hps_io`.
- DIPs: I.D. No, Network, Difficulty, Demo Sounds, Coin Chute (default
  `FF,BF`). MAME maps this game's I/O chip 1 port A bit 3 to Service 2
  rather than Start; the core keeps Start there, which acts as that
  service input.

## Line of Fire (M13)

- Sets: `loffire` (World, FD1094 317-0136), `loffireu` (US, 317-0135),
  `loffirej` (Japan, 317-0134) and their decrypted bootlegs `loffired`,
  `loffireud`, `loffirejd`. Plain X Board configuration without a road
  ROM. MAME's `loffire_sync0_w` only tightens its scheduler on writes to
  shared RAM; a cycle-based board needs nothing there.
- Two guns on the ADC: P1 X/Y on channels 0/1, P2 X/Y on 2/3, the Y
  channels reversed through the descriptor's `adc_reverse` (MAME
  `install_loffire`); trigger and bomb for both players on I/O chip 1 port
  B bits 7:4 (descriptor byte 6 bit 0). MAME maps I/O chip 1 port A bits 3
  and 2 to Service 1 and 2; the core's Start button lands on bit 3, so it
  acts as that service input.
- OSD "Gun control": Lightgun takes the mapped player's analog X/Y as an
  absolute 0..255 position (how MiSTer's USB gun support delivers
  coordinates); Gamepad keeps a per-player cursor in 1/16 pixel units,
  moved once per frame by the stick or D-pad at the "cursor speed" option
  (the request was a 1..100 slider; the OSD only offers lists, so it is
  10..100 in steps of 10, default 50, ordered so the default is the first
  entry). "Crosshair" draws a small cross per player (P1 white, P2
  yellow) in gamepad mode, mapping the 0..255 positions to 320x224 the
  way MAME's crosshairs do. Player 2 uses the second controller.

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
