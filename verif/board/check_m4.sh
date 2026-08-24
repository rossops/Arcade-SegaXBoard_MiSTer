#!/bin/sh
# M4 gate: (1) the Python model with tiles + sprites + road reproduces MAME's
# screenshot on every pixel of every capture; (2) the standalone 315-5275
# renderer is exact against the model; (3) the whole board's frame 60 is
# pixel-exact against the model rendered from the RTL's own RAM state.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
for d in verif/golden/aburner2/f*/; do
  [ -f "$d/roadbuf.bin" ] || continue
  verif/.venv/bin/python tools/road_check.py "$d" | tail -1
  printf "   rtl: "; (cd verif/unit/road && ../../.venv/bin/python run_road.py "$ROOT/$d" | tail -1)
done
make -C verif/board build >/dev/null
make -C verif/board run FRAMES=62 DUMPFRAME=60 >/dev/null 2>&1
verif/.venv/bin/python tools/board_check.py verif/board/out 60
