#!/usr/bin/env python3
"""Build the ioctl index-0 byte stream for a ROM set from a MAME zip.

    pack_roms.py aburner2 --zip path/to/aburner2.zip --out stream.bin [--hexdir DIR]

The stream is exactly what the MRA makes the MiSTer host send (little-endian
16-bit words, WIDE=1): 64-byte descriptor, then each region in xb_pkg order,
zero-padded to its slot. --hexdir also writes one $readmemh file per region
(16-bit words, SDRAM word order) for the simulators.
"""
import argparse, os, struct, sys, zipfile, zlib

sys.path.insert(0, os.path.dirname(__file__))
from romsets import ROMSETS, SLOT, ORDER, DESC_SIZE


def descriptor(rs):
    d = bytearray(DESC_SIZE)
    d[0] = rs["game_id"]
    d[1] = (rs["road_priority"] & 1) | ((rs["thndrbld_hack"] & 1) << 1) | ((rs["has_throttle"] & 1) << 2)
    d[2] = rs["sprite_banks"]
    d[3] = rs["adc_reverse"]
    d[4] = rs["pcm_bankmask"]
    return bytes(d)


def read_rom(zf, name, size, crc):
    try:
        data = zf.read(name)
    except KeyError:
        # merged sets may keep the parent files at top level and clones in dirs
        cands = [n for n in zf.namelist() if n.split("/")[-1] == name]
        if not cands:
            raise SystemExit(f"missing ROM {name}")
        data = zf.read(cands[0])
    if len(data) != size:
        raise SystemExit(f"{name}: size {len(data):#x} != {size:#x}")
    got = f"{zlib.crc32(data) & 0xffffffff:08x}"
    if got != crc:
        raise SystemExit(f"{name}: crc {got} != {crc}")
    return data


def build_region(loader, roms):
    """Return the region bytes in the order the 16-bit SDRAM words are read."""
    if loader == "flat":
        return b"".join(roms)
    if loader == "w16":
        out = bytearray()
        for i in range(0, len(roms), 2):
            even, odd = roms[i], roms[i + 1]
            assert len(even) == len(odd)
            # 68000 big-endian word = (even byte << 8) | odd byte. The stream is
            # little-endian words, so emit (odd, even) byte pairs: the word the
            # loader writes to SDRAM then reads back as {even, odd}.
            for j in range(len(even)):
                out += bytes((odd[j], even[j]))
        return bytes(out)
    if loader == "x32":
        out = bytearray()
        for i in range(0, len(roms), 4):
            b0, b1, b2, b3 = roms[i:i + 4]
            assert len(b0) == len(b1) == len(b2) == len(b3)
            # MAME REGION32_LE: dword = b0 | b1<<8 | b2<<16 | b3<<24.
            # Stream as LE words: (b0,b1) then (b2,b3).
            for j in range(len(b0)):
                out += bytes((b0[j], b1[j], b2[j], b3[j]))
        return bytes(out)
    raise ValueError(loader)


def build_stream(setname, zippath):
    rs = ROMSETS[setname]
    regions = {}
    with zipfile.ZipFile(zippath) as zf:
        for region, (loader, files) in rs["regions"].items():
            roms = [read_rom(zf, n, s, c) for n, s, c in files]
            data = build_region(loader, roms)
            if len(data) > SLOT[region]:
                raise SystemExit(f"{region}: {len(data):#x} exceeds slot {SLOT[region]:#x}")
            regions[region] = data + bytes(SLOT[region] - len(data))
    stream = descriptor(rs) + b"".join(regions[r] for r in ORDER)
    return stream, regions


def write_hex(path, data):
    with open(path, "w") as f:
        for i in range(0, len(data), 2):
            f.write(f"{data[i] | (data[i+1] << 8):04x}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("set")
    ap.add_argument("--zip", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--hexdir")
    a = ap.parse_args()
    stream, regions = build_stream(a.set, a.zip)
    with open(a.out, "wb") as f:
        f.write(stream)
    if a.hexdir:
        os.makedirs(a.hexdir, exist_ok=True)
        for r, d in regions.items():
            write_hex(os.path.join(a.hexdir, f"{r}.hex"), d)
        # tile ROM planes as byte files for the BRAM tile ROM ($readmemh)
        t = regions["tile"]
        for p in range(3):
            with open(os.path.join(a.hexdir, f"tilerom{p}.hex"), "w") as f:
                for i in range(0x10000):
                    f.write(f"{t[p * 0x10000 + i]:02x}\n")
    print(f"{a.out}: {len(stream)} bytes ({len(stream)/1048576:.2f} MB)")


if __name__ == "__main__":
    main()
