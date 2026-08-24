#!/usr/bin/env python3
"""Full-frame model check: tiles + sprites + road from a MAME capture must
reproduce MAME's PNG on every pixel.

    road_check.py verif/golden/aburner2/f60
"""
import os, sys, zipfile
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "verif"))
from models import tilemap16b as tm, palette5242 as pal, sprite5211 as sp, road5275 as rd
from sprite_check import SPRITE_ROMS, words


def compose(idx, mark, fb, road_bg, road_fg, road_priority, palram):
    """MAME screen_update order -> (r,g,b) grid."""
    out = [[None] * 320 for _ in range(224)]
    for y in range(224):
        for x in range(320):
            i = 0
            drawn = False
            if road_bg[y][x] is not None: i = road_bg[y][x]; drawn = True
            if road_priority == 0 and road_fg[y][x] is not None: i = road_fg[y][x]; drawn = True
            # tile layers (mix() merged them with their marks); with
            # road_priority 1 the road foreground goes between fg and text
            m = mark[y][x]
            if m:
                i = idx[y][x]; drawn = True
            if road_priority == 1 and road_fg[y][x] is not None and not (m & 0x4) and not (m & 0x8):
                i = road_fg[y][x]; drawn = True
            eff = False
            pix = fb[y][x]
            if pix != 0xFFFF and (1 << ((pix >> 12) & 3)) > m:
                drawn = True
                if (pix & 0x400f) == 0x400a: eff = True
                else: i = pix & 0xfff
            out[y][x] = pal.entry_rgb(palram[i], eff) if drawn else (0, 0, 0)
    return out


def main(dumpdir, zippath="/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/aburner2.zip", road_priority=0):
    zf = zipfile.ZipFile(zippath)
    tileram, textram = words(os.path.join(dumpdir, "tileram.bin")), words(os.path.join(dumpdir, "textram.bin"))
    palram = words(os.path.join(dumpdir, "paletteram.bin"))
    splist = words(os.path.join(dumpdir, "spritelist.bin"))
    roadbuf = words(os.path.join(dumpdir, "roadbuf.bin"))
    control = int(open(os.path.join(dumpdir, "roadctl.txt")).read().strip())
    planes = [zf.read("epr-11115.154"), zf.read("epr-11114.153"), zf.read("epr-11113.152")]
    regs = tm.latch_regs(textram)
    fg = tm.render_layer(0, tileram, textram, planes, regs)
    bg = tm.render_layer(1, tileram, textram, planes, regs)
    tx = tm.render_text(textram, planes)
    idx, mark = tm.mix(fg, bg, tx)
    fb = sp.render(splist, sp.load_rom_dwords(zf, SPRITE_ROMS), 8)
    gfx = rd.decode(zf.read("epr-10922.40"))
    road_bg, road_fg = rd.render(roadbuf, control, gfx)
    out = compose(idx, mark, fb, road_bg, road_fg, road_priority, palram)
    img = Image.open(os.path.join(dumpdir, "frame.png")).convert("RGB")
    ok = 0
    first = None
    res = Image.new("RGB", (320, 224))
    for y in range(224):
        for x in range(320):
            res.putpixel((x, y), out[y][x])
            if img.getpixel((x, y)) == out[y][x]: ok += 1
            elif first is None: first = (x, y, out[y][x], img.getpixel((x, y)))
    res.save(os.path.join(dumpdir, "model_full.png"))
    print(f"{dumpdir}: control={control} full frame {ok}/71680 exact; first mismatch {first}")
    return 0 if ok == 71680 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1]))
