#!/bin/bash
# M9 gate: the FD1094 decryptor equals MAME's decrypt_one (unit test), and the
# encrypted Thunder Blade and Super Monaco GP parents boot through it and
# match MAME frames within the phase window.
set -e
cd "$(dirname "$0")/../.."
PY=verif/.venv/bin/python
(cd verif/unit/chips && ../../.venv/bin/python -m pytest -q test_fd1094.py)
make -C verif/board build >/dev/null
make -C verif/board run GAME=thndrbld FRAMES=305 DUMPFRAME=150 PLUSARGS="+road_priority=1 +thndrbld_hack=1 +ana_mode=1 +dswb=FD +fd1094=1 +keyrom" | grep -c finish
$PY tools/board_check.py verif/board/out 150 thndrbld
for f in 60 150 300; do $PY tools/frame_match.py verif/board/out verif/golden/thndrbld/f$f/frame.png $f; done
python3 tools/trace_compare.py verif/golden/thndrbld/trace_main_mame.txt verif/board/out/trace_main_pc.txt --max 2500000 --slack 1 --min-match 97 --max-resync 1000
make -C verif/board run GAME=smgp FRAMES=305 DUMPFRAME=150 PLUSARGS="+road_priority=1 +ana_mode=2 +has_snd2=1 +motor_zero=1 +dswb=7F +fd1094=1 +keyrom" | grep -c finish
$PY tools/board_check.py verif/board/out 150 smgp
for f in 60 150 300; do $PY tools/frame_match.py verif/board/out verif/golden/smgp/f$f/frame.png $f; done
