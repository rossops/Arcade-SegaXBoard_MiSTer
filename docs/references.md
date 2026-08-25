# Hardware and IP references

## Behavioural references
- MAME (behavioural reference, GPL-2.0+/BSD-3): local checkout `/Users/rossesposito/Code/mame`,
  commit `f528cd6210bfc15b277ed3ff428a4973b9b912a5` (mame0284-123). Files used:
  `src/mame/sega/segaxbd.cpp`, `segaxbd.h`, `segaic16.cpp`, `sega16sp.cpp`, `segaic16_road.cpp`,
  `segaic16_m.cpp`, `src/devices/sound/segapcm.cpp`, `src/devices/machine/cxd1095.cpp`.
  Installed binary for captures: `/opt/homebrew/bin/mame` (0.289).
- Charles MacDonald, "Sega X-Board hardware notes" (2004-12-03), real-hardware tested:
  `docs/xboard_macdonald.txt` (copied from jotego/jtcores `cores/sx/doc/xboard.txt`).

Where MAME and MacDonald disagree, MAME wins by default (it cites the After Burner
schematic) and the disagreement is listed in `docs/DESIGN.md` under open questions.

## Vendored IP (pinned)
| Path | Upstream | Commit | Licence |
| --- | --- | --- | --- |
| `sys/` | MiSTer framework, copied from `/Volumes/roms/s32/sys` | (as s32) | GPL-3 / mixed, see files |
| `rtl/cpu/fx68k/` | https://github.com/ijor/fx68k | `0602ee4627b10f301298f2673d826cdd6baa9327` | GPL-3 |
| `rtl/audio/jt51/` | https://github.com/jotego/jt51 (`hdl/`) | `985a573dcfc1ff135553a39f7eae21d18ba57cbe` | GPL-3 |
| `rtl/cpu/fd1094/` | https://github.com/jotego/jtcores (`cores/s16/hdl/jts16_fd1094_{ctrl,dec}.v`) | `c96437c1eb2e2e99dfe6f523d9b6bfc45a74689f` | GPL-3 |
| `rtl/audio/T80/` | copied from `/Volumes/roms/s32/rtl/audio/T80` (Wallner/MikeJ/Sorgelig) | (as s32) | BSD-style |
| `verif/board/tv80/` | tv80 (Guy Hutchison, opencores), simulation-only Z80 | (as vendored) | MIT-style |
| `rtl/mem/sdram.sv` | forked from `/Volumes/roms/s32/rtl/mem/sdram.sv` | 2026-08-23 | GPL-3 |
| `rtl/mem/xb_fb_if.sv` | forked from `/Volumes/roms/s32/rtl/mem/s32_fb_if.sv` | 2026-08-23 | GPL-3 |

## ROM sets
MAME 0.289 merged sets in `/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/`: `aburner2.zip`
(parent, includes `aburner2g`), `aburner.zip`, `thndrbld.zip`.
