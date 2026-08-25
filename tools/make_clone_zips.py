#!/usr/bin/env python3
"""Build split clone zips from MAME merged sets for MiSTer.

    make_clone_zips.py --zipdir "/path/to/merged sets" --out DIR [set ...]

MiSTer's MRA loader opens games/mame/<zip>/<file> literally and does not
look inside a merged zip's clone folders (aburner131/, thndrbld1/, ...).
The MRAs name "clone.zip|parent.zip", so a clone zip only needs the files
that live in the clone's folder of the merged zip; everything shared comes
from the parent zip. Without arguments every clone set in romsets.py is
built.
"""
import argparse, os, sys, zipfile

sys.path.insert(0, os.path.dirname(__file__))
from romsets import ROMSETS


def build(key, zipdir, out):
    rs = ROMSETS[key]
    parent = rs["zipfile"]
    if parent == key:
        return None
    src = zipfile.ZipFile(os.path.join(zipdir, parent + ".zip"))
    needed = {n for _, files in rs["regions"].values() for n, _, _ in files}
    folder = rs.get("zip_folder", key)
    dst_path = os.path.join(out, key + ".zip")
    count = 0
    with zipfile.ZipFile(dst_path, "w", zipfile.ZIP_DEFLATED) as dst:
        for entry in src.namelist():
            entry_folder, _, base = entry.rpartition("/")
            if entry_folder == folder and base in needed:
                dst.writestr(base, src.read(entry))
                count += 1
    missing = needed - {e.rpartition("/")[2] for e in src.namelist()}
    if missing:
        raise SystemExit(f"{key}: files not in {parent}.zip: {sorted(missing)}")
    return dst_path, count


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zipdir", default="/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)")
    ap.add_argument("--out", required=True)
    ap.add_argument("sets", nargs="*")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for key in a.sets or list(ROMSETS):
        r = build(key, a.zipdir, a.out)
        if r:
            print(f"{r[0]}: {r[1]} clone files")


if __name__ == "__main__":
    main()
