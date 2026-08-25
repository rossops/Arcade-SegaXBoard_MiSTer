#!/bin/bash
# M11 gate: GP Rider (World) boots through the FD1094 to MAME's frame 60.
set -e
cd "$(dirname "$0")/../.."
PY=verif/.venv/bin/python
make -C verif/board build >/dev/null
make -C verif/board run GAME=gpriders FRAMES=70 DUMPFRAME=60 PLUSARGS="+road_priority=1 +ana_mode=4 +irq_hack=1 +dswb=FE +fd1094=1 +keyrom" | grep -c finish
$PY tools/board_check.py verif/board/out 60 gpriders
$PY tools/frame_match.py verif/board/out verif/golden/gpriders/f60/frame.png 60
