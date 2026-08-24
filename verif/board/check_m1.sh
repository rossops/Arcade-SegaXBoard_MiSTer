#!/bin/sh
# M1 gate: both 68000s track MAME's executed-PC trace over 120 frames (2 s).
# Thresholds reflect what MAME can validate: remaining resyncs are cross-CPU
# handshakes and interrupt placement (see docs/DESIGN.md, "M1 verification").
set -e
cd "$(dirname "$0")/../.."
[ -f verif/golden/aburner2/trace_main_mame.txt ] || python3 tools/mame_trace.py aburner2 --seconds 2 --out verif/golden/aburner2
[ -f verif/golden/aburner2/main.hex ] || python3 tools/pack_roms.py aburner2 --zip "/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/aburner2.zip" --out /dev/null --hexdir verif/golden/aburner2
make -C verif/board build >/dev/null
make -C verif/board run FRAMES=120 >/dev/null 2>&1
python3 tools/trace_compare.py verif/golden/aburner2/trace_main_mame.txt verif/board/out/trace_main_pc.txt --max 2500000 --slack 1 --min-match 97 --max-resync 1000 | grep -v "^  resync"
python3 tools/trace_compare.py verif/golden/aburner2/trace_sub_mame.txt  verif/board/out/trace_sub_pc.txt  --max 2500000 --slack 1 --min-match 99 --max-resync 400  | grep -v "^  resync"
