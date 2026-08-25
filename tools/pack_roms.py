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
    d[1] = ((rs["road_priority"] & 1) | ((rs["thndrbld_hack"] & 1) << 1) | ((rs["has_throttle"] & 1) << 2)
            | ((rs.get("has_snd2", 0) & 1) << 3) | ((rs.get("motor_zero", 0) & 1) << 4)
            | ((rs.get("fd1094", 0) & 1) << 5) | ((rs.get("irq_hack", 0) & 1) << 6)
            | ((rs.get("mux_inputs", 0) & 1) << 7))
    d[2] = rs["sprite_banks"]
    d[3] = rs["adc_reverse"]
    d[4] = rs["pcm_bankmask"]
    d[5] = rs.get("ana_mode", 0) & 7
    d[6] = rs.get("gun_inputs", 0) & 1
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


def last_region(rs):
    """Index in ORDER of the last region the set populates; the stream ends there."""
    return max(i for i, r in enumerate(ORDER) if rs["regions"].get(r, ("flat", []))[1])


def build_stream(setname, zippath):
    rs = ROMSETS[setname]
    regions = {}
    with zipfile.ZipFile(zippath) as zf:
        for region in ORDER:
            loader, files = rs["regions"].get(region, ("flat", []))
            roms = [read_rom(zf, n, s, c) for n, s, c in files]
            data = build_region(loader, roms)
            if len(data) > SLOT[region]:
                raise SystemExit(f"{region}: {len(data):#x} exceeds slot {SLOT[region]:#x}")
            # MAME's PCM region is ROMREGION_ERASEFF: unpopulated ROM reads 0xFF
            fill = b"\xff" if region == "pcm" else b"\x00"
            regions[region] = data + fill * (SLOT[region] - len(data))
    stream = descriptor(rs) + b"".join(regions[r] for r in ORDER[:last_region(rs) + 1])
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

    rs = ROMSETS[a.set]
    with open(a.out, "wb") as f:
        f.write(stream)
    if a.hexdir:
        os.makedirs(a.hexdir, exist_ok=True)
        for r in ORDER[:last_region(rs) + 1]:
            d = regions[r]
            write_hex(os.path.join(a.hexdir, f"{r}.hex"), d)
        # road ROM as a byte file for the BRAM road ROM ($readmemh)
        with open(os.path.join(a.hexdir, "roadrom.hex"), "w") as f:
            for i in range(0x10000):
                f.write(f"{regions['road'][i]:02x}\n")
        # FD1094 key as a byte file for the key RAM ($readmemh, +keyrom)
        if rs["regions"].get("key", ("flat", []))[1]:
            with open(os.path.join(a.hexdir, "keyrom.hex"), "w") as f:
                for i in range(0x2000):
                    f.write(f"{regions['key'][i]:02x}\n")
        # tile ROM planes as byte files for the BRAM tile ROM ($readmemh)
        t = regions["tile"]
        for p in range(3):
            with open(os.path.join(a.hexdir, f"tilerom{p}.hex"), "w") as f:
                for i in range(0x10000):
                    f.write(f"{t[p * 0x10000 + i]:02x}\n")
    print(f"{a.out}: {len(stream)} bytes ({len(stream)/1048576:.2f} MB)")


if __name__ == "__main__":
    main()
