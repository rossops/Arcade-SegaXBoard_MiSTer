# Sega X Board for MiSTer FPGA

MiSTer core for Sega's X Board arcade hardware (834-6280 family), starting with
After Burner II. The aim is a simulation of the actual board, not a
re-implementation of the game: two 68000s, a Z80, the 315-5197 tilemap chip,
the 315-5211A sprite generator with its double framebuffer, the 315-5275 road
generator, the 315-5248/5249/5250 math and timer chips, two CXD1095 port
expanders, a YM2151 and a 315-5218 PCM chip.

## Status

| Milestone | What it proves | State |
| --- | --- | --- |
| M0 | Skeleton compiles, MRA/stream tools agree with MAME CRCs | done on the Mac side, Quartus build pending |
| M1 | Both 68000s boot, math/timer/IO chips pass unit tests, PC traces track MAME | done in sim (self-test screen check moves to M2) |
| M2 | Tilemap/text/palette pixel-exact against MAME | done in sim |
| M3 | Sprites via DDR3 framebuffers | done in sim |
| M4 | Road | done in sim |
| M5 | Sound | done in sim |
| M6 | Hardware bring-up and timing closure | done: DIPs, NVRAM, MAME analog ranges, pause; zero negative slack all corners, 49% ALMs; ROM cache fill defect fixed and confirmed on hardware (build #11) |
| M7 | After Burner and Thunder Blade | done: aburner (1.32/1.31), thndrbld1, thndrbldd confirmed on hardware; Thunder Blade pixel-exact vs MAME; FD1094 parent sets need a decryption block (M8) |
| M8 | Super Monaco GP | done: smgpd (decrypted bootleg) with the second sound board and driving inputs, pixel-exact vs MAME, confirmed on hardware; official FD1094 sets need M9 |
| M9 | FD1094 | done: decryptor unit-verified against MAME; encrypted Thunder Blade and Super Monaco GP (World, Rev B) pixel-exact vs MAME and confirmed on hardware |
| M10 | Racing Hero and A.B. Cop | done: six sets (bootlegs pixel-exact vs MAME, FD1094 parents), confirmed on hardware |
| M11 | GP Rider | done: three single-board FD1094 sets, confirmed on hardware |
| M12 | Last Survivor | done: input multiplexer, two players, bootleg and FD1094 sets, confirmed on hardware |
| M13 | Line of Fire | done: six sets, lightgun/gamepad gun control with cursor speed and crosshair, confirmed on hardware |
| M14 | Enhanced sprites (640x448 sprite rendering, opt-in) | parked in 2026-08 (did not fit alongside the road ROM in BRAM), picked up again as M19 |
| M15 | Gamma correction (framework OSD option, disabled since M5) | done: confirmed on hardware; road ROM rebuilt as a true-dual-port RAM (build #23, 545/553 M10K) |
| M16 | MiSTer-devel standards (stock `sys/`, template layout, MRA alternatives) | in source, hardware build pending |
| M18 | Road ROM in SDRAM (line prefetch, frees 64 M10K blocks) | done: confirmed on hardware (build #28, 488/553 M10K) |
| M19 | Enhanced sprites (640x448 sprite rendering, opt-in OSD option) | done: confirmed on hardware (build #29, 488/553 M10K). Known issue: with the option on, Racing Hero loses rows at the bottom of the screen from the start of a race (fine with it off), fixed in M20 (build #31) |
| M20 | Renderer speed for the 2x mode (duplicate rows, erase at the swap) and MiSTer-devel OSD feedback (button order, D-pad default) | done: confirmed on hardware (build #31, 488/553 M10K); Racing Hero start grid renders in 12.1 ms against a 15.7 ms window, no aborts |
| later | CPU overclock (12.5/15/18.75/25 MHz, opt-in) | parked, see docs/DESIGN.md |
| M17 | Analog sensitivity (response curves for stick and wheel games) and per-game OSD | done: confirmed on hardware (build #27) |

## Fully playable games

One MRA per game sits in `releases/` (installed as `_Arcade/<game>.mra`);
the other versions of each game are under `releases/_alternatives/_<game>/`,
the standard MiSTer layout, and show up in the Arcade menu's alternatives
folder.

| Game | MAME set | ROM zips (MAME 0.289) | Main CPU |
|---|---|---|---|
| After Burner II | `aburner2` | `aburner2.zip` | plain |
| After Burner (Ver 1.32) | `aburner` | `aburner.zip` | plain |
| After Burner (Ver 1.31) | `aburner131` | `aburner.zip` + `aburner131.zip` | plain |
| Thunder Blade (deluxe, standing) | `thndrbld1` | `thndrbld.zip` + `thndrbld1.zip` | plain |
| Thunder Blade (upright, bootleg decrypted) | `thndrbldd` | `thndrbld.zip` + `thndrbldd.zip` | plain |
| Thunder Blade (upright) | `thndrbld` | `thndrbld.zip` | FD1094 |
| Super Monaco GP (World, bootleg decrypted) | `smgpd` | `smgp.zip` + `smgpd.zip` | plain |
| Super Monaco GP (World, Rev B) | `smgp` | `smgp.zip` | FD1094 |
| Racing Hero | `rachero` | `rachero.zip` | FD1094 |
| Racing Hero (bootleg decrypted) | `racherod` | `rachero.zip` + `racherod.zip` | plain |
| A.B. Cop (World) | `abcop` | `abcop.zip` | FD1094 |
| A.B. Cop (Japan) | `abcopj` | `abcop.zip` + `abcopj.zip` | FD1094 |
| A.B. Cop (World, bootleg decrypted) | `abcopd` | `abcop.zip` + `abcopd.zip` | plain |
| A.B. Cop (Japan, bootleg decrypted) | `abcopjd` | `abcop.zip` + `abcopjd.zip` | plain |
| GP Rider (World) | `gpriders` | `gprider.zip` + `gpriders.zip` | FD1094 |
| GP Rider (US) | `gpriderus` | `gprider.zip` + `gpriderus.zip` | FD1094 |
| GP Rider (Japan) | `gpriderjs` | `gprider.zip` + `gpriderjs.zip` | FD1094 |
| Last Survivor | `lastsurv` | `lastsurv.zip` | FD1094 |
| Last Survivor (bootleg decrypted) | `lastsurvd` | `lastsurv.zip` + `lastsurvd.zip` | plain |
| Line of Fire (World) | `loffire` | `loffire.zip` | FD1094 |
| Line of Fire (US) | `loffireu` | `loffire.zip` + `loffireu.zip` | FD1094 |
| Line of Fire (Japan) | `loffirej` | `loffire.zip` + `loffirej.zip` | FD1094 |
| Line of Fire (World, bootleg decrypted) | `loffired` | `loffire.zip` + `loffired.zip` | plain |
| Line of Fire (US, bootleg decrypted) | `loffireud` | `loffire.zip` + `loffireud.zip` | plain |
| Line of Fire (Japan, bootleg decrypted) | `loffirejd` | `loffire.zip` + `loffirejd.zip` | plain |

## Controls and options

Player 1's left stick is the flight stick or wheel; the right stick's Y
axis is the throttle (After Burner, Thunder Blade) or gas and brake (the
driving games), with Gas/Brake or Speed Up/Slow Down buttons as the
digital alternative. The button list puts what you bind first at the front
(Gas and Brake lead on the driving games, the throttle buttons follow the
fire buttons on After Burner and Thunder Blade), Test and Service last. OSD options: Stick (D-pad by
default, analog, or both), Analog response (Linear is the
board's own mapping; Soft and Softer flatten the centre for thumbsticks
while keeping full lock), Analog range (100/75/50%), Gun control for Line
of Fire (lightgun or gamepad cursor, with per-player cursor speed and an
optional crosshair), rear speakers for Super Monaco GP, and pause while
the OSD is open. Options that do not apply to the loaded game are hidden
(the MRA's board descriptor drives the framework's menu mask).

## Layout

```
Arcade-SegaXBoard.{sv,qsf,qpf,sdc}   MiSTer emu top and Quartus project
files.qip                            file list (edit this, never the IDE)
build.bat / clean.bat                Windows build with Quartus Prime 17.0 Lite
sys/                                 MiSTer framework (vendored)
rtl/                                 the board: xb_pkg, xb_core, cpu/ video/ audio/ io/ mem/ pll/
tools/                               ROM table, MRA generator, stream packer, MAME capture
verif/                               golden models, cocotb unit tests, Verilator board sim
docs/                                design notes and hardware references
releases/                            .mra files and dated .rbf builds
```

## Building the .rbf (Windows)

Install Quartus Prime 17.0 Lite, clone the repo, then run `build.bat`. It
compiles `Arcade-SegaXBoard` and copies the result to
`releases\Arcade-SegaXBoard_YYYYMMDD.rbf`. `clean.bat` removes every generated
file. If Quartus lives somewhere other than `C:\intelFPGA_lite\17.0\quartus`,
set `QUARTUS_ROOTDIR` first.

The OSD's version line is `v<yymmdd>-<git sha>`, generated into `build_id.v` at compile time by `tools/build_id.tcl` (the framework's script plus the SHA, hooked from the `.qsf`) (a `*` after the SHA means the tree had uncommitted changes; `git` on the build machine is optional, the script falls back to reading `.git/HEAD`).

## Simulation and tests (macOS/Linux)

Needs Verilator, Icarus Verilog, Python 3.12 and MAME. cocotb does not build
on Python 3.14, so `verif/` keeps its own venv:

```
python3.12 -m venv verif/.venv && verif/.venv/bin/pip install cocotb pytest
sh verif/lint.sh                              # Verilator lint of the board
sh verif/lint_emu.sh                          # elaborate the MiSTer top against the framework
verif/.venv/bin/python -m pytest tools/tests  # MRA == packer stream, ROM CRCs
(cd verif/unit && ../.venv/bin/python -m pytest -q chips)   # cocotb chip tests vs MAME models
python3 tools/mame_trace.py aburner2 --seconds 2 --out verif/golden/aburner2
make -C verif/board run FRAMES=30             # Verilator board sim: traces + PPM frames
python3 tools/trace_compare.py verif/golden/aburner2/trace_main_mame.txt verif/board/out/trace_main_pc.txt --slack 2
python3 tools/mame_capture.py aburner2 --frame 60 --out verif/golden/aburner2/f60   # RAM dumps + PNG
sh verif/board/check_m1.sh                    # CPU trace gate
sh verif/board/check_m2.sh                    # tilemap/text/palette gate
sh verif/board/check_m3.sh                    # sprite gate
sh verif/board/check_m4.sh                    # road gate (full-frame exact vs MAME)
sh verif/board/check_m5.sh                    # sound gate (PCM cocotb + audio envelope vs MAME)
python3 tools/gen_mra.py                      # writes releases/*.mra
python3 tools/pack_roms.py aburner2 --zip aburner2.zip --out stream.bin --hexdir verif/golden/aburner2
```

The ROM table in `tools/romsets.py` is copied from MAME's `segaxbd.cpp`. The
MRA and the packer are checked against each other so the SDRAM layout the RTL
expects is the one the MiSTer host actually sends.

What the tests show: the custom chips are checked against Python ports of
MAME's C++ (the 315-5248/5249/5250 over 10^5 random operations, the
FD1094 over 30,000 words with a real key, the sprite and road generators
on lists and tables captured from MAME), the board simulation's 68000
program-counter traces track MAME's for the first seconds of every game,
and the frames it renders match MAME's screenshots pixel for pixel
(After Burner II, Thunder Blade, Super Monaco GP, Racing Hero, A.B. Cop
and Line of Fire at frames 60/150/300; the other sets on their boot
frame). Every set has been run on a DE10-Nano. `docs/DESIGN.md` records
the results per milestone, and where the RTL deliberately differs from
MAME.

## Installing

Copy `releases/Arcade-SegaXBoard_<date>.rbf` to `/media/fat/_Arcade/cores/`,
the `.mra` files to `/media/fat/_Arcade/` and the MAME 0.289 zips listed in
the games table to `/media/fat/games/mame/`, then launch a game from the
Arcade menu. Commercial ROMs are not included.

For automatic installation, add this to `/media/fat/downloader.ini` and run
Update All:

```
[rossops/Arcade-SegaXBoard_MiSTer]
db_url = https://raw.githubusercontent.com/rossops/Arcade-SegaXBoard_MiSTer/main/db.json.zip
```

The database (`db.json.zip`, built by `tools/make_db.py`) lists every MRA
and the current core with their MD5s, pointing at the files in this
repository; it is regenerated with each release. The repository used to be
`rossops/sxboard`; GitHub redirects the old address, so an ini section
written for that name keeps working, but the one above is the current one.

## Audio filter

The MiSTer framework applies a selectable low-pass filter to the core's
audio (OSD system page, "Audio filter", files under `/media/fat/Filters_Audio/`).
The X Board's 315-5218 plays 8-bit samples at 31.25 kHz without
interpolation, so its output carries staircase imaging above ~15 kHz that
sounds gritty on a flat system, while the YM2151 side is clean; the PCB
itself has an analog low-pass before the amplifier. Recommended:
`General LPF/LPF 12khz 1st + AA.txt`, a gentle first-order roll-off that
tames the PCM grit without dulling the FM. `Arcade LPF/Arcade LPF 8khz 2nd.txt`
gives the warmer sound of a period cabinet speaker. To make one the core's
default add to `MiSTer.ini`:

```
[Arcade-SegaXBoard]
afilter_default=General LPF/LPF 12khz 1st + AA.txt
```

## Credits

The Sega custom chips, the board glue, the loader and the tooling in this
repository were written for this core from the references below. Several
pieces are other people's work, vendored under their own licences (pinned
commits in `docs/references.md`):

- **MAME** (mamedev.org) — the behavioural reference for the whole board:
  `segaxbd.cpp` and the 16-bit Sega device family (`segaic16`, `sega16sp`,
  `segaic16_road`, `segaic16_m`), `segapcm.cpp`, `cxd1095.cpp`, and
  `fd1094.cpp` by Nicola Salmoria, Andreas Naive and Charles MacDonald.
  Every custom chip model in `verif/models/` is a port of the MAME code,
  and MAME 0.289 produced the golden frames, traces and audio the RTL is
  checked against. GPL-2.0+ / BSD-3.
- **Charles MacDonald** — "Sega X-Board hardware notes" (2004), the
  real-hardware description of the sprite sequencing, memory map and I/O
  used where MAME simplifies (`docs/xboard_macdonald.txt`, via jtcores).
- **Jose Tejada (jotego)** — the YM2151 (`jt51`) and the FD1094 decryptor
  and control block from jtcores (`cores/s16`), GPL-3.
- **Jorge Cwik (ijor)** — `fx68k`, the cycle-accurate 68000 used for both
  CPUs, GPL-3.
- **Daniel Wallner, MikeJ, Sorgelig** — the T80 Z80 core, BSD-style.
- **Guy Hutchison** — `tv80`, the Verilog Z80 used by the Verilator
  simulations in place of the VHDL T80, MIT-style.
- **Alexey Melnikov (Sorgelig) and the MiSTer project** — the MiSTer
  framework (`sys/`), the MRA/ROM loading conventions, the audio filter
  and the DE10-Nano platform this runs on.
- **Meathax** — the Sega System 32 MiSTer core
  (https://github.com/meathax/s32), GPL-3: the repository layout follows
  it, and the SDRAM controller (`rtl/mem/sdram.sv`) and the DDR3 sprite
  framebuffer interface (`rtl/mem/xb_fb_if.sv`) are forks of its
  `sdram.sv` and `s32_fb_if.sv`; the `sys/` framework copy and the T80
  came from it as well.
- **Tools**: Verilator, Icarus Verilog, cocotb, capstone, numpy and Pillow
  for the verification flow; Quartus Prime 17.0 Lite for the FPGA build.

The core itself is GPL-3. Commercial ROMs are not included.
