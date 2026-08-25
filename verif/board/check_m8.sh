#!/bin/bash
# M8 gate: Super Monaco GP (smgpd) frames match MAME within the phase window,
# the board is self-consistent, and the audio envelope (both sound boards
# summed) follows MAME's.
set -e
cd "$(dirname "$0")/../.."
PY=verif/.venv/bin/python
P="+road_priority=1 +ana_mode=2 +has_snd2=1 +motor_zero=1 +dswb=7F"
make -C verif/board build >/dev/null
make -C verif/board run GAME=smgpd FRAMES=305 DUMPFRAME=150 PLUSARGS="$P" | grep -c finish
$PY tools/board_check.py verif/board/out 150 smgpd
for f in 60 150 300; do $PY tools/frame_match.py verif/board/out verif/golden/smgpd/f$f/frame.png $f; done
if [ -f verif/golden/smgpd/mame.wav ]; then
  make -C verif/board run GAME=smgpd FRAMES=120 PLUSARGS="$P" | grep -c finish
  $PY tools/wav_compare.py verif/board/out/audio.raw verif/golden/smgpd/mame.wav --skip 0.3
fi
