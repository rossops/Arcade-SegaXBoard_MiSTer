#!/bin/sh
# M3 gate: (1) the standalone 315-5211A renderer + DDR3 framebuffer path is
# pixel-exact against the Python model (a port of MAME sega16sp.cpp) on every
# captured sprite list; (2) the whole board's frame 60 is pixel-exact with
# sprites against the model rendered from the RTL's own RAM state.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
for d in verif/golden/aburner2/f*/; do
  [ -f "$d/spritelist.bin" ] || continue
  printf "== %s: " "$d"; (cd verif/unit/sprite && ../../.venv/bin/python run_sprite.py "$ROOT/$d" | tail -1)
done
make -C verif/board build >/dev/null
make -C verif/board run FRAMES=62 DUMPFRAME=60 >/dev/null 2>&1
verif/.venv/bin/python tools/board_check.py verif/board/out 60
