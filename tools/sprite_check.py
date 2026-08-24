#!/usr/bin/env python3
"""Validate the Python sprite model against MAME: render tiles + sprites
from a capture (spritelist.bin is the list latched at the $110000 write)
and compare every pixel that is tile- or sprite-opaque with the PNG.

    sprite_check.py verif/golden/aburner2/f60
"""
import os, sys, zipfile
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "verif"))
from models import tilemap16b as tm, palette5242 as pal, sprite5211 as sp

SPRITE_ROMS = ["mpr-10932.90", "mpr-10934.94", "mpr-10936.98", "mpr-10938.102",
               "mpr-10933.91", "mpr-10935.95", "mpr-10937.99", "mpr-10939.103",
               "epr-11103.92", "epr-11104.96", "epr-11105.100", "epr-11106.104",
               "epr-11116.93", "epr-11117.97", "epr-11118.101", "epr-11119.105"]


def words(p):
    b = open(p, "rb").read(); return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


def main(dumpdir, zippath="/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/aburner2.zip"):
    zf = zipfile.ZipFile(zippath)
    tileram, textram = words(os.path.join(dumpdir, "tileram.bin")), words(os.path.join(dumpdir, "textram.bin"))
    palram = words(os.path.join(dumpdir, "paletteram.bin"))
    splist = words(os.path.join(dumpdir, "spritelist.bin"))
    planes = [zf.read("epr-11115.154"), zf.read("epr-11114.153"), zf.read("epr-11113.152")]
    rom = sp.load_rom_dwords(zf, SPRITE_ROMS)
    regs = tm.latch_regs(textram)
    fg = tm.render_layer(0, tileram, textram, planes, regs)
    bg = tm.render_layer(1, tileram, textram, planes, regs)
    tx = tm.render_text(textram, planes)
    idx, mark = tm.mix(fg, bg, tx)
    fb = sp.render(splist, rom, len(rom) * 4 // 0x40000)
    img = Image.open(os.path.join(dumpdir, "frame.png")).convert("RGB")
    out = Image.new("RGB", (320, 224))
    total = ok = 0
    first = None
    for y in range(224):
        for x in range(320):
            pix = fb[y][x]
            i, eff, opaque = idx[y][x], False, bool(mark[y][x])
            if pix != 0xFFFF:
                prio = (pix >> 12) & 3
                if (1 << prio) > mark[y][x]:
                    opaque = True
                    if (pix & 0x400f) == 0x400a: eff = True
                    else: i = pix & 0xfff
            rgb = pal.entry_rgb(palram[i], eff)
            out.putpixel((x, y), rgb)
            if opaque:
                total += 1
                if img.getpixel((x, y)) == rgb: ok += 1
                elif first is None: first = (x, y, rgb, img.getpixel((x, y)), hex(pix), hex(i))
    out.save(os.path.join(dumpdir, "model_sprites.png"))
    print(f"{dumpdir}: opaque {total}/71680, matching MAME {ok} ({100.0*ok/max(1,total):.2f}%) first mismatch {first}")
    return 0 if ok == total else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1]))
