#!/usr/bin/env python3
"""Board-level video self-consistency: render the Python tilemap model from
the RTL's own RAM dump (tb +dumpframe=N) and require the RTL frame N to be
pixel-exact everywhere (tile layers and the black background).

    board_check.py verif/board/out 60
"""
import os, sys, zipfile
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "verif"))
from models import tilemap16b as tm, palette5242 as pal, sprite5211 as sp, road5275 as rd
SPRITE_ROMS = ["mpr-10932.90", "mpr-10934.94", "mpr-10936.98", "mpr-10938.102",
               "mpr-10933.91", "mpr-10935.95", "mpr-10937.99", "mpr-10939.103",
               "epr-11103.92", "epr-11104.96", "epr-11105.100", "epr-11106.104",
               "epr-11116.93", "epr-11117.97", "epr-11118.101", "epr-11119.105"]


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
    # sprites: the frame shown was rendered from the list the CPU handed over
    # one frame earlier; try both sprite RAM banks and keep the better one
    fbs = [None]
    rom = None
    for name in ("rtl_spriteram.bin", "rtl_spriteram_prev.bin"):
        sprfile = os.path.join(outdir, name)
        if os.path.exists(sprfile):
            if rom is None:
                rom = sp.load_rom_dwords(zf, SPRITE_ROMS)
                fbs = []
            allw = words(sprfile)
            fbs.append(sp.render(allw[0:2048], rom, 8))
            fbs.append(sp.render(allw[2048:4096], rom, 8))
    # road: the renderer reads the bank the CPU is not writing (~road_bank)
    road_bg = road_fg = None
    ctlfile = os.path.join(outdir, "rtl_roadctl.txt")
    if os.path.exists(ctlfile) and os.path.exists(os.path.join(outdir, "rtl_roadram.bin")):
        control, road_bank = [int(v) for v in open(ctlfile).read().split()]
        rr = words(os.path.join(outdir, "rtl_roadram.bin"))
        rbuf = rr[2048:4096] if road_bank == 0 else rr[0:2048]
        gfx = rd.decode(zf.read("epr-10922.40"))
        road_bg, road_fg = rd.render(rbuf, control, gfx)
    best = None
    for bank, fb in enumerate(fbs):
        ok = opaque = 0
        first = None
        mism = []
        for y in range(224):
            for x in range(320):
                i, eff, op = idx[y][x], False, bool(mark[y][x])
                if road_bg is not None:
                    m = mark[y][x]
                    if road_bg[y][x] is not None: op = True; i = road_bg[y][x] if not m else i
                    if road_fg[y][x] is not None and not m: op = True; i = road_fg[y][x]
                if fb is not None and fb[y][x] != 0xFFFF:
                    pix = fb[y][x]
                    if (1 << ((pix >> 12) & 3)) > mark[y][x]:
                        op = True
                        if (pix & 0x400f) == 0x400a: eff = True
                        else: i = pix & 0xfff
                exp = pal.entry_rgb(palram[i], eff) if op else (0, 0, 0)
                opaque += 1 if op else 0
                got = rtl.getpixel((x, y))
                if got == exp: ok += 1
                else:
                    if first is None: first = (x, y, exp, got)
                    mism.append((x, y, exp, got))
        if best is None or ok > best[0]: best = (ok, opaque, first, bank, mism)
    ok, opaque, first, bank, mism = best
    print(f"frame {frame}: {ok}/71680 pixels exact ({opaque} opaque, sprite bank {bank}); first mismatch {first}")
    if os.environ.get("LIST"):
        for m in mism[:60]: print("   ", m)
    return 0 if ok == 71680 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1], int(sys.argv[2])))
