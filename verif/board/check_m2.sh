#!/bin/sh
# M2 gate: (1) the standalone 315-5197 renderer is pixel-exact against the
# Python model (a port of MAME segaic16.cpp) on every captured RAM dump;
# (2) the whole board's frame 60 is pixel-exact against the model rendered
# from the RTL's own RAM state (renderer + mixer + palette + pipeline).
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
for d in verif/golden/aburner2/f*/ verif/golden/aburner2/t*/; do
  [ -f "$d/tileram.bin" ] || continue
  echo "== $d"; (cd verif/unit/tilemap && ../../.venv/bin/python run_tilemap.py "$ROOT/$d" | tail -3)
done
make -C verif/board build >/dev/null
make -C verif/board run FRAMES=62 DUMPFRAME=60 >/dev/null 2>&1
verif/.venv/bin/python tools/board_check.py verif/board/out 60
