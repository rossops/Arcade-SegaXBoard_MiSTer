#!/usr/bin/env python3
"""Render the tile layers from a MAME RAM dump with the Python model and
compare against MAME's screenshot. Pixels where the model says a tile layer
is opaque must match the PNG unless a sprite/road covers them (those are
reported as 'covered' not as errors when --allow-cover is given: a covered
pixel is one where the PNG colour differs but equals some sprite/road colour;
we cannot know without the sprite model, so we only report the raw stats)."""
import os, sys, zipfile
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "verif"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from romsets import ROMSETS
from models import tilemap16b as tm
from models import palette5242 as pal


def load_words(path):
    b = open(path, "rb").read()
    return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


ZIPDIR = "/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)"


def main(dumpdir, setname="aburner2"):
    rs = ROMSETS[setname]
    zippath = os.path.join(ZIPDIR, rs["zipfile"] + ".zip")
    tileram = load_words(os.path.join(dumpdir, "tileram.bin"))
    textram = load_words(os.path.join(dumpdir, "textram.bin"))
    palram = load_words(os.path.join(dumpdir, "paletteram.bin"))
    zf = zipfile.ZipFile(zippath)
    planes = [zf.read([m for m in zf.namelist() if m.split("/")[-1] == n][0]) for n, _, _ in rs["regions"]["tile"][1]]
    regs = tm.latch_regs(textram)
    fg = tm.render_layer(0, tileram, textram, planes, regs)
    bg = tm.render_layer(1, tileram, textram, planes, regs)
    tx = tm.render_text(textram, planes)
    idx, mark = tm.mix(fg, bg, tx)
    img = Image.open(os.path.join(dumpdir, "frame.png")).convert("RGB")
    assert img.size == (320, 224), img.size
    normal, _, _ = pal.tables()
    total = match = opaque = 0
    out = Image.new("RGB", (320, 224))
    for y in range(224):
        for x in range(320):
            rgb = pal.entry_rgb(palram[idx[y][x]])
            out.putpixel((x, y), rgb)
            if mark[y][x]:
                opaque += 1
                if img.getpixel((x, y)) == rgb:
                    match += 1
            total += 1
    out.save(os.path.join(dumpdir, "model.png"))
    print(f"tile-opaque pixels {opaque}/{total}; matching MAME PNG: {match} ({100.0*match/max(1,opaque):.2f}%)")
    print("regs pages/ysc/xsc:", [hex(v) for v in regs[0]], [hex(v) for v in regs[1]], [hex(v) for v in regs[2]])


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "aburner2")
