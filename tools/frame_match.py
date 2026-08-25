#!/usr/bin/env python3
"""Compare a MAME screenshot with the RTL frames around the same frame number
and report the best match.

    frame_match.py verif/board/out verif/golden/aburner2/f60/frame.png 60 [--window 3] [--min 99]

The RTL and MAME run the same code but their bus timing differs by a few
clocks per access, so the game's timeline sits at a slightly different phase
relative to the frame boundary (After Burner II runs about two frames behind
MAME since the ROM cache fix). A frame within the window that matches to the
threshold shows the video pipeline is right; the remaining pixels are
elements that move between two consecutive frames (blinking text, fast
sprites). Exit status 0 when the best match reaches --min percent.
"""
import argparse, os
from PIL import Image


def match(rtl_path, png):
    a = Image.open(rtl_path).convert("RGB")
    w, h = a.size
    pa, pb = a.load(), png.load()
    same = sum(1 for y in range(h) for x in range(w) if pa[x, y] == pb[x, y])
    return 100.0 * same / (w * h)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outdir"); ap.add_argument("mame"); ap.add_argument("frame", type=int)
    ap.add_argument("--window", type=int, default=3)
    ap.add_argument("--min", type=float, default=99.0)
    a = ap.parse_args()
    png = Image.open(a.mame).convert("RGB")
    best = None
    for d in range(-a.window, a.window + 1):
        p = os.path.join(a.outdir, f"frame_{a.frame + d:04d}.ppm")
        if not os.path.exists(p):
            continue
        m = match(p, png)
        # prefer the offset nearest zero among equal scores
        if best is None or m > best[1] or (m == best[1] and abs(d) < abs(best[0] - a.frame)):
            best = (a.frame + d, m)
    if best is None:
        print("no RTL frames found"); return 1
    ok = best[1] >= a.min
    print(f"MAME frame {a.frame}: best RTL frame {best[0]} ({best[0] - a.frame:+d}) matches {best[1]:.2f}% -> {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
