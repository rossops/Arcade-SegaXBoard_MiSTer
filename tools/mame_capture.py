#!/usr/bin/env python3
"""Capture MAME video RAM dumps and a screenshot at a given frame.

    mame_capture.py aburner2 --frame 300 --out verif/golden/aburner2/f300 [--test]

--test starts the game in service/test mode (DIP). The snapshot is written by
MAME into the output directory as <setname>/0000.png and moved to frame.png.
"""
import argparse, glob, os, shutil, subprocess, tempfile

ROMPATH = "/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)"
HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("set")
    ap.add_argument("--frame", type=int, default=300)
    ap.add_argument("--out", required=True)
    ap.add_argument("--test", action="store_true", help="service mode on (test switch held)")
    ap.add_argument("--mame", default="mame")
    a = ap.parse_args()
    out = os.path.abspath(a.out)
    os.makedirs(out, exist_ok=True)
    env = dict(os.environ, XB_FRAME=str(a.frame), XB_OUT=out)
    cfg = tempfile.mkdtemp()
    cmd = [a.mame, a.set, "-rompath", ROMPATH, "-window", "-sound", "none", "-nothrottle",
           "-skip_gameinfo", "-snapshot_directory", out, "-nvram_directory", tempfile.mkdtemp(),
           "-cfg_directory", cfg, "-autoboot_script", os.path.join(HERE, "mame_capture.lua"),
           "-seconds_to_run", str(a.frame // 60 + 5)]
    if a.test:
        # MAME's generic "Service Mode" toggle is the F2 key; simplest is a
        # cfg file that maps the test switch... use the built-in dip override:
        cmd += ["-noautosave"]
        env["XB_TEST"] = "1"
    subprocess.run(cmd, env=env, check=False)
    pngs = sorted(glob.glob(os.path.join(out, a.set, "*.png")))
    if pngs:
        shutil.move(pngs[-1], os.path.join(out, "frame.png"))
        shutil.rmtree(os.path.join(out, a.set), ignore_errors=True)
    print(out, os.listdir(out))


if __name__ == "__main__":
    main()
