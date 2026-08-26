#!/usr/bin/env python3
"""Board-level video self-consistency: render the Python tilemap model from
the RTL's own RAM dump (tb +dumpframe=N) and require the RTL frame N to be
pixel-exact everywhere (tile layers and the black background).

    board_check.py verif/board/out 60
"""
import os, sys, zipfile
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "verif"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from models import tilemap16b as tm, palette5242 as pal, sprite5211 as sp, road5275 as rd
from romsets import ROMSETS
ZIPDIR = "/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)"


def zread(zf, name):
    c = [n for n in zf.namelist() if n.split("/")[-1] == name]
    return zf.read(c[0])


def words(p):
    b = open(p, "rb").read(); return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


def main(outdir, frame, setname="aburner2", hires=False):
    """hires: the frame is the 640x448 enhanced mode - tiles and road pixel
    doubled, sprites from the model's 2x render."""
    rs = ROMSETS[setname]
    SC = 2 if hires else 1
    W, H = 320 * SC, 224 * SC
    road_priority = rs["road_priority"]
    tileram = words(os.path.join(outdir, "rtl_tileram.bin"))
    textram = words(os.path.join(outdir, "rtl_textram.bin"))
    palram = words(os.path.join(outdir, "rtl_paletteram.bin"))
    zf = zipfile.ZipFile(os.path.join(ZIPDIR, rs["zipfile"] + ".zip"))
    planes = [zread(zf, n) for n, _, _ in rs["regions"]["tile"][1]]
    SPRITE_ROMS = [n for n, _, _ in rs["regions"]["sprite"][1]]
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
            fbs.append(sp.render(allw[0:2048], rom, 8, width=W, height=H, scale=SC))
            fbs.append(sp.render(allw[2048:4096], rom, 8, width=W, height=H, scale=SC))
    # road: the renderer reads the bank the CPU is not writing (~road_bank)
    road_bg = road_fg = None
    ctlfile = os.path.join(outdir, "rtl_roadctl.txt")
    if os.path.exists(ctlfile) and os.path.exists(os.path.join(outdir, "rtl_roadram.bin")):
        control, road_bank = [int(v) for v in open(ctlfile).read().split()]
        rr = words(os.path.join(outdir, "rtl_roadram.bin"))
        rbuf = rr[2048:4096] if road_bank == 0 else rr[0:2048]
        road_files = rs["regions"]["road"][1]
        gfx = rd.decode(zread(zf, road_files[0][0]) if road_files else bytes(0x10000))   # SMGP has no road ROM
        road_bg, road_fg = rd.render(rbuf, control, gfx)
    best = None
    for bank, fb in enumerate(fbs):
        ok = opaque = 0
        first = None
        mism = []
        for y in range(H):
            for x in range(W):
                gy, gx = y // SC, x // SC     # game pixel behind this output pixel
                i, eff, op = idx[gy][gx], False, bool(mark[gy][gx])
                if road_bg is not None:
                    m = mark[gy][gx]
                    if road_bg[gy][gx] is not None: op = True; i = road_bg[gy][gx] if not m else i
                    # road_priority 0: road fg under every tile layer; 1: over the
                    # bg/fg tilemaps, under the text layer (MAME screen_update)
                    txt = tx[gy][gx] is not None
                    if road_fg[gy][gx] is not None and (not m if road_priority == 0 else not txt): op = True; i = road_fg[gy][gx]
                if fb is not None and fb[y][x] != 0xFFFF:
                    pix = fb[y][x]
                    if (1 << ((pix >> 12) & 3)) > mark[gy][gx]:
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
    print(f"frame {frame}: {ok}/{W*H} pixels exact ({opaque} opaque, sprite bank {bank}); first mismatch {first}")
    if os.environ.get("DIFF"):
        im = Image.new("RGB", (W, H))
        bad = set((m[0], m[1]) for m in mism)
        for y in range(H):
            for x in range(W):
                im.putpixel((x, y), (255, 0, 0) if (x, y) in bad else tuple(c // 3 for c in rtl.getpixel((x, y))))
        im.save(os.environ["DIFF"])
    if os.environ.get("LIST"):
        for m in mism[:60]: print("   ", m)
    return 0 if ok == W * H else 1


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--hires"]
    raise SystemExit(main(args[0], int(args[1]), args[2] if len(args) > 2 else "aburner2", hires="--hires" in sys.argv))
