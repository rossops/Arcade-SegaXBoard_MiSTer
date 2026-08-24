#!/usr/bin/env python3
"""Render one frame from a MAME RAM dump with the RTL tilemap (iverilog) and
compare every layer pixel with the Python model.
    run_tilemap.py <dumpdir>"""
import os, subprocess, sys, zipfile
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..", "..", "..")
sys.path.insert(0, os.path.join(ROOT, "verif"))
from models import tilemap16b as tm

def words(p):
    b = open(p, "rb").read(); return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]

def main(dumpdir):
    tileram, textram = words(os.path.join(dumpdir, "tileram.bin")), words(os.path.join(dumpdir, "textram.bin"))
    with open(os.path.join(HERE, "tileram.hex"), "w") as f: f.write("\n".join(f"{w:04x}" for w in tileram))
    with open(os.path.join(HERE, "textram.hex"), "w") as f: f.write("\n".join(f"{w:04x}" for w in textram))
    for p in range(3):
        src = os.path.join(ROOT, "verif", "golden", "aburner2", f"tilerom{p}.hex")
        dst = os.path.join(HERE, f"tilerom{p}.hex")
        if not os.path.exists(dst): os.symlink(src, dst)
    srcs = [os.path.join(ROOT, s) for s in ("rtl/xb_pkg.sv", "rtl/video/xb_video_timing.sv", "rtl/mem/xb_dpram.sv",
            "rtl/video/xb_tilerom.sv", "rtl/video/xb_tilemap_5197.sv")]
    subprocess.check_call(["iverilog", "-g2012", "-DSIMULATION", "-o", "tb.vvp", "-s", "tb_tilemap"] + srcs + [os.path.join(HERE, "tb_tilemap.sv")], cwd=HERE)
    subprocess.check_call(["vvp", "-n", "tb.vvp"], cwd=HERE, stdout=subprocess.DEVNULL)
    zf = zipfile.ZipFile("/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/aburner2.zip")
    planes = [zf.read("epr-11115.154"), zf.read("epr-11114.153"), zf.read("epr-11113.152")]
    regs = tm.latch_regs(textram)
    layers = {"fg": tm.render_layer(0, tileram, textram, planes, regs),
              "bg": tm.render_layer(1, tileram, textram, planes, regs),
              "tx": tm.render_text(textram, planes)}
    stats = {k: [0, 0, None] for k in layers}
    unwritten = {k: 0 for k in layers}
    n = 0
    for line in open(os.path.join(HERE, "layers.txt")):
        y, x, fg, bg, tx = line.split(); y, x = int(y), int(x)
        vals = {"fg": fg, "bg": bg, "tx": tx}
        n += 1
        for k, grid in layers.items():
            m = grid[y][x]
            if "x" in vals[k]:
                stats[k][1] += 1; unwritten[k] += 1
                if stats[k][2] is None: stats[k][2] = (x, y, m, "unwritten")
                continue
            v = int(vals[k], 16)
            pen = v & 7
            if k == "tx": prio, colour = (v >> 6) & 1, (v >> 3) & 7
            else:         prio, colour = (v >> 10) & 1, (v >> 3) & 0x7f
            exp = None if m is None else m
            got = None if pen == 0 else (prio, tm.COLORBASE + colour * 8 + pen)
            stats[k][1] += 1
            if got == exp: stats[k][0] += 1
            elif stats[k][2] is None: stats[k][2] = (x, y, exp, got, hex(v))
    print("pixels:", n)
    for k, (ok, tot, first) in stats.items():
        print(f"{k}: {ok}/{tot} ({100.0*ok/max(1,tot):.2f}%) unwritten {unwritten[k]} first mismatch {first}")
    return 0 if all(s[0] == s[1] for s in stats.values()) else 1

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1]))
