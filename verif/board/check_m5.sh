#!/bin/sh
# M5 gate: (1) the 315-5218 engine matches the MAME port tick for tick
# (cocotb); (2) the board's audio with a coin at frame 30 correlates with
# MAME's recording of the same scenario (48 kHz, tools/wav_compare.py).
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
(cd verif/unit && ../.venv/bin/python -m pytest -q chips/test_segapcm.py | tail -1)
[ -f verif/golden/aburner2/mame_coin30.wav ] || python3 tools/mame_wav.py aburner2 --seconds 6 --coin 30 --out verif/golden/aburner2/mame_coin30.wav
make -C verif/board build >/dev/null
make -C verif/board run FRAMES=150 COIN=30 >/dev/null 2>&1
verif/.venv/bin/python tools/wav_compare.py verif/board/out/audio.raw verif/golden/aburner2/mame_coin30.wav --skip 0.3 --out verif/board/out/rtl.wav
