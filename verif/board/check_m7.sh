#!/bin/bash
# M7 gate: Thunder Blade (thndrbld1) frames match MAME within a small phase
# window; After Burner sets are self-consistent (their demo plane depends on
# a boot-time ADC race MAME resolves differently, see docs/DESIGN.md).
set -e
cd "$(dirname "$0")/../.."
PY=verif/.venv/bin/python
make -C verif/board build >/dev/null
make -C verif/board run GAME=thndrbld1 FRAMES=305 DUMPFRAME=150 PLUSARGS="+road_priority=1 +thndrbld_hack=1 +ana_mode=1 +dswb=FD" | grep -c finish
$PY tools/board_check.py verif/board/out 150 thndrbld1
for f in 60 150 300; do $PY tools/frame_match.py verif/board/out verif/golden/thndrbld1/f$f/frame.png $f; done
for s in aburner aburner131 thndrbldd; do
  case $s in thndrbldd) P="+road_priority=1 +thndrbld_hack=1 +ana_mode=1 +dswb=FD";; *) P="+dswb=C9";; esac
  make -C verif/board run GAME=$s FRAMES=160 DUMPFRAME=150 PLUSARGS="$P" | grep -c finish
  $PY tools/board_check.py verif/board/out 150 $s
done
