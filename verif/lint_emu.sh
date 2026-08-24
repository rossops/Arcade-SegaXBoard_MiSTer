#!/bin/sh
# Elaborate the MiSTer emu top against the real framework modules with
# Verilator. Catches port-list mismatches and multiply-driven nets that only
# Quartus would otherwise report (unlike verif/lint.sh this is not -Wall).
set -e
cd "$(dirname "$0")/.."
verilator --lint-only -DSIMULATION --top-module emu -Isys -Irtl/video \
  -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PROCASSINIT \
  -Wno-IMPORTSTAR -Wno-WIDTH -Wno-PINCONNECTEMPTY -Wno-CASEINCOMPLETE \
  -Wno-BLKSEQ -Wno-TIMESCALEMOD -Wno-PINMISSING -Wno-UNOPTFLAT \
  -Wno-CASEOVERLAP -Wno-LATCH -Wno-SYNCASYNCNET -Wno-COMBDLY -Wno-INITIALDLY \
  -Wno-ASCRANGE -Wno-LITENDIAN -Wno-PROCASSWIRE -Wno-IMPLICIT -Wno-IMPLICITSTATIC -Wno-CASEX \
  verif/fx68k.vlt rtl/xb_pkg.sv rtl/video/xb_video_timing.sv rtl/mem/sdram.sv \
  rtl/mem/xb_rom_loader.sv rtl/mem/xb_dpram.sv rtl/cpu/xb_math_5248.sv rtl/cpu/xb_math_5249.sv rtl/cpu/xb_cmptimer_5250.sv rtl/io/xb_cxd1095.sv rtl/io/xb_adc0804.sv rtl/cpu/xb_rom_cache.sv rtl/cpu/xb_m68k_bus.sv rtl/mem/xb_fb_if.sv rtl/video/xb_sprite_5211.sv rtl/video/xb_tilerom.sv rtl/video/xb_tilemap_5197.sv rtl/video/xb_palette_5242.sv rtl/video/xb_mixer.sv rtl/cpu/fx68k/fx68k.sv rtl/cpu/fx68k/fx68kAlu.sv rtl/cpu/fx68k/uaddrPla.sv rtl/xb_core.sv rtl/pll/pll.v \
  sys/hps_io.sv sys/arcade_video.v sys/video_freak.sv sys/scandoubler.v \
  sys/scanlines.v sys/gamma_corr.sv sys/video_cleaner.sv sys/video_mixer.sv \
  sys/hq2x.sv sys/math.sv sys/sys_top.v \
  Arcade-SegaXBoard.sv
echo "emu elaborates"
