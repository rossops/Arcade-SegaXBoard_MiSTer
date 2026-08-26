#!/usr/bin/env python3
"""Standalone sprite renderer vs the Python model.
    run_sprite.py <dumpdir>   (uses dumpdir/spritelist.bin)"""
import os, subprocess, sys, zipfile
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "verif"))
from models import sprite5211 as sp
SPRITE_ROMS = ["mpr-10932.90", "mpr-10934.94", "mpr-10936.98", "mpr-10938.102",
               "mpr-10933.91", "mpr-10935.95", "mpr-10937.99", "mpr-10939.103",
               "epr-11103.92", "epr-11104.96", "epr-11105.100", "epr-11106.104",
               "epr-11116.93", "epr-11117.97", "epr-11118.101", "epr-11119.105"]

def words(p):
    b = open(p, "rb").read(); return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]

def main(dumpdir, max_sprites=None, hires=False):
    splist = words(os.path.join(dumpdir, "spritelist.bin"))
    if max_sprites is not None:
        splist = splist[:max_sprites * 8] + [0x8000] * (2048 - max_sprites * 8)
    with open(os.path.join(HERE, "spritelist.hex"), "w") as f:
        f.write("\n".join(f"{w:04x}" for w in splist))
    src = os.path.join(ROOT, "verif", "golden", "aburner2", "sprite.hex")
    dst = os.path.join(HERE, "sprite.hex")
    if not os.path.exists(dst): os.symlink(src, dst)
    srcs = [os.path.join(ROOT, s) for s in ("rtl/xb_pkg.sv", "rtl/mem/xb_fb_if.sv", "rtl/video/xb_sprite_5211.sv",
            "verif/board/ddram_model.sv")]
    subprocess.check_call(["iverilog", "-g2012", "-DSIMULATION", "-o", "tb.vvp", "-s", "tb_sprite"] + srcs + [os.path.join(HERE, "tb_sprite.sv")], cwd=HERE)
    subprocess.check_call(["vvp", "-n", "tb.vvp"] + (["+hires"] if hires else []), cwd=HERE)
    # model renders in screen coords; rebuild the full 512x256 fb view instead
    zf = zipfile.ZipFile("/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/aburner2.zip")
    rom = sp.load_rom_dwords(zf, SPRITE_ROMS)
    W, H, FW, FH, XO = (640, 448, 1024, 512, 380) if hires else (320, 224, 512, 256, 190)
    exp = sp.render(splist, rom, 8, width=W, height=H, scale=2 if hires else 1)
    got = [[0xFFFF] * FW for _ in range(FH)]
    with open(os.path.join(HERE, "fb.txt")) as f:
        vals = f.read().split()
    i = 0
    for y in range(FH):
        for xw in range(FW // 4):
            for k in range(4):
                got[y][xw * 4 + k] = int(vals[i], 16); i += 1
    ok = tot = 0
    first = None
    for y in range(H):
        for x in range(W):
            e = exp[y][x]
            g = got[y][x + XO]
            if e != 0xFFFF or g != 0xFFFF:
                tot += 1
                if e == g: ok += 1
                elif first is None: first = (x, y, hex(e), hex(g))
    print(f"sprite-opaque pixels {tot}: match {ok} ({100.0*ok/max(1,tot):.2f}%) first mismatch {first}")
    return 0 if ok == tot else 1

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--hires"]
    raise SystemExit(main(args[0], int(args[1]) if len(args) > 1 else None, hires="--hires" in sys.argv))
