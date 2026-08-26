#!/bin/sh
# Verilator -Wall lint of the board (everything below emu; vendored code
# gets only the waivers it needs). Run from the repo root: sh verif/lint.sh
set -e
cd "$(dirname "$0")/.."
W="-Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PROCASSINIT -Wno-IMPORTSTAR -Wno-PINCONNECTEMPTY"
FX="-Wno-EOFNEWLINE -Wno-VARHIDDEN -Wno-ALWCOMBORDER -Wno-BLKANDNBLK -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-BLKSEQ -Wno-UNOPTFLAT -Wno-CASEOVERLAP -Wno-LATCH -Wno-MULTIDRIVEN -Wno-IMPLICIT -Wno-UNDRIVEN -Wno-SYNCASYNCNET -Wno-COMBDLY -Wno-INITIALDLY -Wno-TIMESCALEMOD -Wno-CASEX -Wno-IMPLICITSTATIC -Wno-PROCASSWIRE"
OWN="rtl/xb_pkg.sv rtl/video/xb_video_timing.sv rtl/mem/sdram.sv rtl/mem/xb_rom_loader.sv rtl/mem/xb_dpram.sv \
  rtl/cpu/xb_math_5248.sv rtl/cpu/xb_math_5249.sv rtl/cpu/xb_cmptimer_5250.sv rtl/io/xb_cxd1095.sv rtl/io/xb_adc0804.sv rtl/io/xb_ana_shape.sv \
  rtl/cpu/xb_rom_cache.sv rtl/cpu/fd1094/jts16_fd1094_ctrl.v rtl/cpu/fd1094/jts16_fd1094_dec.v rtl/cpu/xb_fd1094.sv rtl/cpu/xb_m68k_bus.sv \
  rtl/audio/xb_segapcm_5218.sv rtl/audio/xb_soundsys.sv rtl/mem/xb_fb_if.sv rtl/video/xb_sprite_5211.sv rtl/video/xb_roadrom.sv rtl/video/xb_road_5275.sv rtl/video/xb_tilerom.sv rtl/video/xb_tilemap_5197.sv rtl/video/xb_palette_5242.sv rtl/video/xb_mixer.sv rtl/xb_core.sv"
FXF="rtl/cpu/fx68k/fx68k.sv rtl/cpu/fx68k/fx68kAlu.sv rtl/cpu/fx68k/uaddrPla.sv rtl/audio/jt51/*.v verif/board/tv80/*.v"
W="$W -DXB_Z80_TV80 -Wno-PINCONNECTEMPTY"
# our own files: strict
for f in $OWN; do
  case $f in rtl/xb_core.sv|rtl/cpu/xb_m68k_bus.sv|rtl/audio/xb_soundsys.sv) continue;; esac
  case $f in rtl/xb_pkg.sv) continue;; esac
  verilator --lint-only $W -Irtl/video -y rtl/cpu/fd1094 +libext+.v rtl/xb_pkg.sv $f --top-module $(basename ${f%.*}) >/dev/null
done
# board with fx68k inside: fx68k's own warnings waived, ours still fatal
verilator --lint-only $W $FX -Irtl/video $OWN $FXF --top-module xb_core 2>&1 | grep -E "%Warning|%Error" | grep -v "Exiting due|jt51|tv80" && exit 1
echo "lint clean"
