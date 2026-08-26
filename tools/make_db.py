#!/usr/bin/env python3
"""Build the MiSTer Downloader ("update_all") database for this core.

    make_db.py [--repo user/repo] [--branch main] [--out db.json.zip]

Lists every MRA under releases/ (alternatives included) as _Arcade/<path>.mra and the newest
releases/Arcade-SegaXBoard_<date>.rbf as _Arcade/cores/<file>, with MD5 and
size, each pointing at the raw GitHub URL of the file in the given branch.
Users add to /media/fat/downloader.ini:

    [<user>/<repo>]
    db_url = https://raw.githubusercontent.com/<user>/<repo>/<branch>/db.json.zip

and run Update All. Regenerate and commit db.json.zip whenever an MRA or the
release .rbf changes (the hashes must match the committed files).
"""
import argparse, glob, hashlib, json, os, re, time, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default="rossops/sxboard")
    ap.add_argument("--branch", default="main")
    ap.add_argument("--out", default=os.path.join(ROOT, "db.json.zip"))
    a = ap.parse_args()
    raw = f"https://raw.githubusercontent.com/{a.repo}/{a.branch}/"
    files = {}
    folders = {"_Arcade": {}, "_Arcade/cores": {}}
    rel_dir = os.path.join(ROOT, "releases")
    for mra in sorted(glob.glob(os.path.join(rel_dir, "**", "*.mra"), recursive=True)):
        rel = os.path.relpath(mra, rel_dir)          # e.g. _alternatives/_After Burner/x.mra
        files[f"_Arcade/{rel}"] = {"hash": md5(mra), "size": os.path.getsize(mra),
                                   "url": raw + "releases/" + rel.replace(" ", "%20")}
        d = os.path.dirname(rel)
        while d:
            folders[f"_Arcade/{d}"] = {}
            d = os.path.dirname(d)
    rbfs = sorted(glob.glob(os.path.join(ROOT, "releases", "Arcade-SegaXBoard_*.rbf")),
                  key=lambda p: re.search(r"_(\d{8})\.rbf$", p).group(1))
    if not rbfs:
        raise SystemExit("no releases/Arcade-SegaXBoard_<date>.rbf")
    rbf = rbfs[-1]
    files[f"_Arcade/cores/{os.path.basename(rbf)}"] = {
        "hash": md5(rbf), "size": os.path.getsize(rbf), "url": raw + "releases/" + os.path.basename(rbf)}
    db = {
        "db_id": a.repo.lower(),
        "db_url": raw + "db.json.zip",
        "timestamp": int(time.time()),
        "base_files_url": raw,
        "files": files,
        "folders": folders,
        "default_options": {},
        "zips": {},
    }
    with zipfile.ZipFile(a.out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("db.json", json.dumps(db, indent=1, sort_keys=True))
    print(f"{a.out}: {len(files)} files, core {os.path.basename(rbf)}")


if __name__ == "__main__":
    main()
