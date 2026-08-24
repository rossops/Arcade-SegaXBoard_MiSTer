#!/usr/bin/env python3
"""Record MAME's executed-PC trace for the X Board 68000s.

    mame_trace.py aburner2 --seconds 2 --out verif/golden/aburner2

Runs MAME headless with a debugger script that traces both CPUs from reset,
then keeps just the PC column so tools/trace_compare.py can check the RTL's
fetch stream against it.
"""
import argparse, os, subprocess, sys, tempfile

ROMPATH = "/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("set")
    ap.add_argument("--seconds", type=float, default=2.0)
    ap.add_argument("--out", required=True)
    ap.add_argument("--mame", default="mame")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    raw_main = os.path.abspath(os.path.join(a.out, "mame_trace_main.raw"))
    raw_sub = os.path.abspath(os.path.join(a.out, "mame_trace_sub.raw"))
    script = os.path.join(a.out, "trace.dbg")
    with open(script, "w") as f:
        f.write(f"trace {raw_main},mainpcb:maincpu,noloop\n")
        f.write(f"trace {raw_sub},mainpcb:subcpu,noloop\n")
        f.write("go\n")
    cmd = [a.mame, a.set, "-rompath", ROMPATH, "-debug", "-debugscript", script,
           "-window", "-sound", "none", "-nothrottle", "-seconds_to_run", str(int(a.seconds)),
           "-skip_gameinfo", "-nvram_directory", tempfile.mkdtemp(), "-cfg_directory", tempfile.mkdtemp(),
           "-debugger", "osx"]
    print(" ".join(cmd))
    subprocess.run(cmd, check=False)
    for raw, name in ((raw_main, "trace_main_mame.txt"), (raw_sub, "trace_sub_mame.txt")):
        n = 0
        with open(raw, errors="replace") as fi, open(os.path.join(a.out, name), "w") as fo:
            for line in fi:
                if len(line) > 7 and line[6] == ":":
                    fo.write(line[:6].lower() + "\n")
                    n += 1
        print(f"{name}: {n} instructions")
    # keep the first 200k raw lines (with disassembly) for debugging
    for raw, name in ((raw_main, "trace_main_mame_dis.txt"), (raw_sub, "trace_sub_mame_dis.txt")):
        with open(raw, errors="replace") as fi, open(os.path.join(a.out, name), "w") as fo:
            for i, line in enumerate(fi):
                if i >= 200000: break
                fo.write(line)
        os.remove(raw)


if __name__ == "__main__":
    main()
