#!/bin/bash
# M10 gate: Racing Hero and A.B. Cop decrypted bootlegs match MAME frames
# within the phase window and are self-consistent; the FD1094 parents (same
# code through the verified decryptor) only need to boot to the same frame.
set -e
cd "$(dirname "$0")/../.."
PY=verif/.venv/bin/python
P="+road_priority=1 +ana_mode=3 +dswb=F9"
make -C verif/board build >/dev/null
for s in racherod abcopd; do
  make -C verif/board run GAME=$s FRAMES=305 DUMPFRAME=150 PLUSARGS="$P" | grep -c finish
  $PY tools/board_check.py verif/board/out 150 $s
  for f in 60 150 300; do $PY tools/frame_match.py verif/board/out verif/golden/$s/f$f/frame.png $f; done
done
for s in rachero abcop; do
  make -C verif/board run GAME=$s FRAMES=70 DUMPFRAME=60 PLUSARGS="$P +fd1094=1 +keyrom" | grep -c finish
  $PY tools/board_check.py verif/board/out 60 $s
  $PY tools/frame_match.py verif/board/out verif/golden/$s/f60/frame.png 60
done
