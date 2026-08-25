#!/bin/bash
# M12 gate: Last Survivor (bootleg and FD1094 parent) boots to MAME's frame 60.
set -e
cd "$(dirname "$0")/../.."
PY=verif/.venv/bin/python
make -C verif/board build >/dev/null
for s in lastsurvd lastsurv; do
  case $s in lastsurv) X="+fd1094=1 +keyrom";; *) X="";; esac
  make -C verif/board run GAME=$s FRAMES=70 DUMPFRAME=60 PLUSARGS="+road_priority=1 +mux_inputs=1 +dswb=BF $X" | grep -c finish
  $PY tools/board_check.py verif/board/out 60 $s
  $PY tools/frame_match.py verif/board/out verif/golden/$s/f60/frame.png 60
done
