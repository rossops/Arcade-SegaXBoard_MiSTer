# Sega X Board for MiSTer FPGA

MiSTer core for Sega's X Board arcade hardware (834-6280 family), starting with
After Burner II. The aim is a simulation of the actual board, not a
re-implementation of the game: two 68000s, a Z80, the 315-5197 tilemap chip,
the 315-5211A sprite generator with its double framebuffer, the 315-5275 road
generator, the 315-5248/5249/5250 math and timer chips, two CXD1095 port
expanders, a YM2151 and a 315-5218 PCM chip.

Nothing playable yet. This is milestone 0: the repository layout, the build
flow, the ROM stream tools and a stub board that shows colour bars.

## Status

| Milestone | What it proves | State |
| --- | --- | --- |
| M0 | Skeleton compiles, MRA/stream tools agree with MAME CRCs | done on the Mac side, Quartus build pending |
| M1 | Both 68000s boot, math/timer/IO chips pass unit tests, PC traces track MAME | done in sim (self-test screen check moves to M2) |
| M2 | Tilemap/text/palette pixel-exact against MAME | not started |
| M3 | Sprites via DDR3 framebuffers | not started |
| M4 | Road | not started |
| M5 | Sound | not started |
| M6 | Hardware bring-up and timing closure | not started |
| M7 | After Burner and Thunder Blade | not started |

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
python3 tools/gen_mra.py                      # writes releases/*.mra
python3 tools/pack_roms.py aburner2 --zip aburner2.zip --out stream.bin --hexdir verif/golden/aburner2
```

The ROM table in `tools/romsets.py` is copied from MAME's `segaxbd.cpp`. The
MRA and the packer are checked against each other so the SDRAM layout the RTL
expects is the one the MiSTer host actually sends.

## Installing

Copy the `.rbf` and `.mra` to `/media/fat/_Arcade/` and the MAME
`aburner2.zip` to `/media/fat/games/mame/`. Commercial ROMs are not included.

## References

See `docs/references.md` for the pinned MAME commit, Charles MacDonald's
hardware notes and the vendored IP (fx68k, jt51, T80) with licences. The core
is GPL-3.
