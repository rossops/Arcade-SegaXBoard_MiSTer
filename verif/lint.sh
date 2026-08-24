#!/bin/sh
# Verilator lint of the board (everything below emu; the vendored sys/ is not
# linted). Run from the repo root: sh verif/lint.sh
set -e
cd "$(dirname "$0")/.."
verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PROCASSINIT -Wno-IMPORTSTAR \
  rtl/xb_pkg.sv \
  rtl/video/xb_video_timing.sv \
  rtl/mem/sdram.sv \
  rtl/mem/xb_rom_loader.sv \
  rtl/xb_core.sv \
  --top-module xb_core
echo "lint clean"
