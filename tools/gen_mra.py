#!/usr/bin/env python3
"""Generate MiSTer .mra files for every set in tools/romsets.py.

    gen_mra.py [--outdir releases]

The <rom index="0"> part must produce byte-for-byte the stream pack_roms.py
builds (tests/test_stream.py checks that).
"""
import argparse, os, sys

sys.path.insert(0, os.path.dirname(__file__))
from romsets import ROMSETS, SLOT, ORDER, DESC_SIZE
from pack_roms import descriptor

RBF = "Arcade-SegaXBoard"


def hexbytes(b):
    return " ".join(f"{x:02x}" for x in b)


def region_parts(loader, files, slot, fill="00"):
    lines = []
    total = 0
    if loader == "flat":
        for n, s, _ in files:
            lines.append(f'      <part name="{n}"/>')
            total += s
    elif loader == "w16":
        for i in range(0, len(files), 2):
            (e, s, _), (o, _, _) = files[i], files[i + 1]
            lines.append('      <interleave output="16">')
            # map digits are byte positions, rightmost = byte 0. The stream word
            # is little-endian and must read back as {even, odd} (68000 order),
            # so the even ROM is byte 1 ("10") and the odd ROM byte 0 ("01").
            lines.append(f'        <part name="{e}" map="10"/>')
            lines.append(f'        <part name="{o}" map="01"/>')
            lines.append('      </interleave>')
            total += 2 * s
    elif loader == "x32":
        for i in range(0, len(files), 4):
            grp = files[i:i + 4]
            lines.append('      <interleave output="32">')
            for k, (n, s, _) in enumerate(grp):
                m = ["0"] * 4
                m[3 - k] = "1"
                lines.append(f'        <part name="{n}" map="{"".join(m)}"/>')
            lines.append('      </interleave>')
            total += 4 * grp[0][1]
    pad = slot - total
    if pad < 0:
        raise SystemExit("region exceeds slot")
    if pad:
        lines.append(f'      <part repeat="{pad}">{fill}</part>')
    return lines


def make_mra(key, rs):
    L = []
    L.append('<misterromdescription>')
    L.append(f'  <name>{rs["name"]}</name>')
    L.append(f'  <setname>{key}</setname>')
    L.append(f'  <rbf>{RBF}</rbf>')
    L.append(f'  <mameversion>0289</mameversion>')
    L.append(f'  <year>{rs["year"]}</year>')
    L.append('  <manufacturer>Sega</manufacturer>')
    L.append('  <category>Shooter / Flight</category>')
    L.append('  <rom index="0" zip="%s.zip" md5="None">' % rs["zip"])
    L.append(f'    <part>{hexbytes(descriptor(rs))}</part>')
    for region in ORDER:
        loader, files = rs["regions"][region]
        L.append(f'    <!-- {region} -->')
        L += region_parts(loader, files, SLOT[region], "FF" if region == "pcm" else "00")
    L.append('  </rom>')
    # backup RAM (two 16 KB banks) saved as NVRAM index 3
    L.append('  <nvram index="3" size="32768"/>')
    # DIP switches: raw port values (1 = off). Defaults are MAME's.
    L.append('  <switches default="FF,DD" base="0">')
    coin = ("Free Play (if both) or 1C/1C,1C/1C 2/3,1C/1C 4/5,1C/1C 5/6,2C/1C 4/3,2C/1C 3/2 5/3 6/4,"
            "2C/3C,4C/1C,3C/1C,2C/1C,7C/1C,6C/1C,5C/1C,1C/3C,1C/2C,1C/1C")
    L.append(f'    <dip bits="0,3" name="Coin A" ids="{coin}"/>')
    L.append(f'    <dip bits="4,7" name="Coin B" ids="{coin}"/>')
    L.append('    <dip bits="8,9" name="Cabinet" ids="Upright 2,Upright 1,Moving Standard,Moving Deluxe"/>')
    L.append('    <dip bits="10" name="Throttle Lever" ids="No,Yes"/>')
    L.append('    <dip bits="11,12" name="Lives" ids="4x Credits,3x Credits,4,3"/>')
    L.append('    <dip bits="13" name="Allow Continue" ids="Yes,No"/>')
    L.append('    <dip bits="14,15" name="Difficulty" ids="Hardest,Hard,Easy,Normal"/>')
    L.append('  </switches>')
    L.append('  <buttons names="Vulcan,Missile,Start,Coin,Test,Service,Pause" default="A,B,Start,R,L,Select,X"/>')
    L.append('</misterromdescription>')
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default=os.path.join(os.path.dirname(__file__), "..", "releases"))
    a = ap.parse_args()
    os.makedirs(a.outdir, exist_ok=True)
    for key, rs in ROMSETS.items():
        path = os.path.join(a.outdir, f'{rs["name"]}.mra')
        with open(path, "w") as f:
            f.write(make_mra(key, rs))
        print(path)


if __name__ == "__main__":
    main()
