#!/usr/bin/env python3
"""Standalone road renderer vs the Python model.   run_road.py <dumpdir>"""
import os, subprocess, sys, zipfile
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "verif"))
from models import road5275 as rd

def words(p):
    b = open(p, "rb").read(); return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]

def main(dumpdir):
    roadbuf = words(os.path.join(dumpdir, "roadbuf.bin"))
    control = int(open(os.path.join(dumpdir, "roadctl.txt")).read().strip())
    with open(os.path.join(HERE, "roadbuf.hex"), "w") as f: f.write("\n".join(f"{w:04x}" for w in roadbuf))
    dst = os.path.join(HERE, "roadrom.hex")
    if not os.path.exists(dst): os.symlink(os.path.join(ROOT, "verif", "golden", "aburner2", "roadrom.hex"), dst)
    srcs = [os.path.join(ROOT, s) for s in ("rtl/xb_pkg.sv", "rtl/video/xb_video_timing.sv", "rtl/mem/xb_dpram.sv",
            "rtl/video/xb_roadrom.sv", "rtl/video/xb_road_5275.sv")]
    subprocess.check_call(["iverilog", "-g2012", "-DSIMULATION", "-o", "tb.vvp", "-s", "tb_road"] + srcs + [os.path.join(HERE, "tb_road.sv")], cwd=HERE)
    subprocess.check_call(["vvp", "-n", "tb.vvp", f"+ctl={control}"], cwd=HERE, stdout=subprocess.DEVNULL)
    zf = zipfile.ZipFile("/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/aburner2.zip")
    gfx = rd.decode(zf.read("epr-10922.40"))
    bg, fg = rd.render(roadbuf, control, gfx)
    ok = tot = 0; first = None; okb = 0
    for line in open(os.path.join(HERE, "road.txt")):
        y, x, bv, bi, fv, fi = line.split(); y, x = int(y), int(x)
        e_bg = bg[y][x]; g_bg = int(bi, 16) if bv == "1" else None
        e_fg = fg[y][x]; g_fg = int(fi, 16) if fv == "1" else None
        tot += 1
        if e_fg == g_fg: ok += 1
        elif first is None: first = ("fg", x, y, e_fg and hex(e_fg), g_fg and hex(g_fg))
        if e_bg == g_bg: okb += 1
        elif first is None: first = ("bg", x, y, e_bg, g_bg)
    print(f"control={control}: fg {ok}/{tot}, bg {okb}/{tot}; first mismatch {first}")
    return 0 if ok == tot and okb == tot else 1

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1]))
