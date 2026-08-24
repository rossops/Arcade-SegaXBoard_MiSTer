#!/usr/bin/env python3
"""Compare an RTL frame (PPM) with a MAME screenshot (PNG).

    frame_diff.py rtl.ppm mame.png [--dump DIR] [--out diff.png]

With --dump (a mame_capture directory) the comparison is restricted to
pixels the Python tilemap model marks as tile-opaque, so sprite and road
areas (not implemented yet) do not count. Prints match statistics and
writes a diff image (red = mismatch).
"""
import argparse, os, sys, zipfile
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "verif"))


def tile_mask(dumpdir, zippath):
    from models import tilemap16b as tm
    def lw(p):
        b = open(p, "rb").read(); return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]
    tileram, textram = lw(os.path.join(dumpdir, "tileram.bin")), lw(os.path.join(dumpdir, "textram.bin"))
    zf = zipfile.ZipFile(zippath)
    planes = [zf.read("epr-11115.154"), zf.read("epr-11114.153"), zf.read("epr-11113.152")]
    regs = tm.latch_regs(textram)
    fg = tm.render_layer(0, tileram, textram, planes, regs)
    bg = tm.render_layer(1, tileram, textram, planes, regs)
    tx = tm.render_text(textram, planes)
    _, mark = tm.mix(fg, bg, tx)
    return mark


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rtl"); ap.add_argument("mame")
    ap.add_argument("--dump")
    ap.add_argument("--zip", default="/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/aburner2.zip")
    ap.add_argument("--out")
    ap.add_argument("--tol", type=int, default=0)
    a = ap.parse_args()
    rtl = Image.open(a.rtl).convert("RGB"); mame = Image.open(a.mame).convert("RGB")
    assert rtl.size == mame.size == (320, 224), (rtl.size, mame.size)
    mask = tile_mask(a.dump, a.zip) if a.dump else None
    diff = Image.new("RGB", (320, 224))
    total = ok = 0
    first = None
    for y in range(224):
        for x in range(320):
            if mask is not None and not mask[y][x]:
                diff.putpixel((x, y), (0, 0, 40)); continue
            p, q = rtl.getpixel((x, y)), mame.getpixel((x, y))
            total += 1
            if all(abs(p[i] - q[i]) <= a.tol for i in range(3)):
                ok += 1; diff.putpixel((x, y), tuple(v // 2 for v in q))
            else:
                diff.putpixel((x, y), (255, 0, 0))
                if first is None: first = (x, y, p, q)
    print(f"compared {total} pixels: {ok} match ({100.0*ok/max(1,total):.2f}%)")
    if first: print("first mismatch at", first)
    if a.out: diff.save(a.out)
    return 0 if ok == total else 1


if __name__ == "__main__":
    raise SystemExit(main())
