#!/usr/bin/env python3
"""Board-level video self-consistency: render the Python tilemap model from
the RTL's own RAM dump (tb +dumpframe=N) and require the RTL frame N to be
pixel-exact everywhere (tile layers and the black background).

    board_check.py verif/board/out 60
"""
import os, sys, zipfile
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "verif"))
from models import tilemap16b as tm, palette5242 as pal


def words(p):
    b = open(p, "rb").read(); return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


def main(outdir, frame, zippath="/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/aburner2.zip"):
    tileram = words(os.path.join(outdir, "rtl_tileram.bin"))
    textram = words(os.path.join(outdir, "rtl_textram.bin"))
    palram = words(os.path.join(outdir, "rtl_paletteram.bin"))
    zf = zipfile.ZipFile(zippath)
    planes = [zf.read("epr-11115.154"), zf.read("epr-11114.153"), zf.read("epr-11113.152")]
    regs = tm.latch_regs(textram)
    fg = tm.render_layer(0, tileram, textram, planes, regs)
    bg = tm.render_layer(1, tileram, textram, planes, regs)
    tx = tm.render_text(textram, planes)
    idx, mark = tm.mix(fg, bg, tx)
    rtl = Image.open(os.path.join(outdir, f"frame_{frame:04d}.ppm")).convert("RGB")
    ok = opaque = 0
    first = None
    for y in range(224):
        for x in range(320):
            exp = pal.entry_rgb(palram[idx[y][x]]) if mark[y][x] else (0, 0, 0)
            opaque += 1 if mark[y][x] else 0
            got = rtl.getpixel((x, y))
            if got == exp: ok += 1
            elif first is None: first = (x, y, exp, got)
    print(f"frame {frame}: {ok}/71680 pixels exact ({opaque} tile-opaque); first mismatch {first}")
    return 0 if ok == 71680 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1], int(sys.argv[2])))
