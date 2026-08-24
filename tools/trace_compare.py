#!/usr/bin/env python3
"""Compare MAME's executed-PC list with the RTL program-fetch stream.

The RTL stream contains every program-space word fetch (instruction words,
extension words and the two-word prefetch), so each MAME PC must appear, in
order, within a few fetches of the previous match. Two things legitimately
differ between MAME and a cycle-exact board and are tolerated:

  * polling loops: the number of iterations of a short backward loop depends
    on cross-CPU timing, which MAME only approximates (100 us quanta), so
    consecutive repeats of a loop body are collapsed on both sides;
  * interrupt placement: an IRQ lands at a different instruction, so after a
    miss the comparer searches ahead (within --resync fetches / instructions)
    and reports the excursion instead of stopping.

Exit status 0 when >= --min-match percent of MAME instructions were found in
order and the number of resyncs is <= --max-resync.

    trace_compare.py mame.txt rtl.txt [--max N] [--slack 6] [--resync 4000]
"""
import argparse


def collapse_loops(seq, maxlen=12):
    """Remove consecutive repeats of any body of length 1..maxlen."""
    out = []
    i = 0
    n = len(seq)
    while i < n:
        out.append(seq[i])
        i += 1
        # after appending, check whether the tail of `out` repeats in seq
        for L in range(1, maxlen + 1):
            if len(out) < L:
                break
            body = out[-L:]
            j = i
            while j + L <= n and seq[j:j + L] == body:
                j += L
            if j > i:
                i = j
                break
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mame"); ap.add_argument("rtl")
    ap.add_argument("--max", type=int, default=500000)
    ap.add_argument("--slack", type=int, default=6)
    ap.add_argument("--resync", type=int, default=4000)
    ap.add_argument("--min-match", type=float, default=99.0)
    ap.add_argument("--max-resync", type=int, default=50)
    ap.add_argument("--no-collapse", action="store_true")
    ap.add_argument("--list-all", action="store_true")
    a = ap.parse_args()
    pcs = [int(x, 16) for x in open(a.mame).read().split()][: a.max]
    fetch = [int(x, 16) for x in open(a.rtl).read().split()]
    if not a.no_collapse:
        pcs_c = collapse_loops(pcs)
        fetch_c = collapse_loops(fetch)
    else:
        pcs_c, fetch_c = pcs, fetch
    i = 0
    matched = 0
    resyncs = []
    n = 0
    while n < len(pcs_c) and i < len(fetch_c):
        pc = pcs_c[n]
        j = i
        while j < len(fetch_c) and fetch_c[j] != pc and j - i <= a.slack:
            j += 1
        if j < len(fetch_c) and fetch_c[j] == pc:
            matched += 1
            i = j + 1
            n += 1
            continue
        # resync: look further ahead in the RTL stream, and also allow MAME to
        # be the one that took an excursion (skip MAME instructions)
        found = None
        for dn in range(0, min(a.resync, len(pcs_c) - n)):
            target = pcs_c[n + dn]
            for dj in range(0, min(a.resync, len(fetch_c) - i)):
                if fetch_c[i + dj] == target and (dn > 0 or dj > a.slack):
                    if found is None or dn + dj < found[0] + found[1]:
                        found = (dn, dj)
                    break
            if found is not None and found[0] + found[1] < dn:
                break
        if found is None:
            if len(fetch_c) - i < a.resync:
                i = len(fetch_c)      # RTL stream exhausted, not a divergence
            else:
                print(f"lost sync at MAME instruction {n} pc {pc:06x} (rtl index {i}); matched {matched}")
            break
        dn, dj = found
        resyncs.append((n, pc, dn, dj, fetch_c[i:i + 3]))
        n += dn
        i += dj
    total = len(pcs_c)
    ended_early = n < total
    # the RTL run is usually shorter than the MAME trace: score only the part
    # of the MAME trace the RTL run covered
    covered = n if ended_early else total
    pct = 100.0 * matched / max(1, covered)
    print(f"MAME instructions (after loop collapse): {total} of {len(pcs)}; RTL fetches: {len(fetch_c)} of {len(fetch)}")
    print(f"RTL run covered {covered} collapsed MAME instructions" + (" (RTL trace ended first)" if ended_early else ""))
    print(f"matched {matched} of {covered} ({pct:.2f}%), resyncs {len(resyncs)}")
    for (nn, pc, dn, dj, ctx) in (resyncs if a.list_all else resyncs[:20]):
        print(f"  resync at MAME #{nn} pc {pc:06x}: skipped {dn} MAME instr / {dj} RTL fetches; rtl here {' '.join(f'{x:06x}' for x in ctx)}")
    ok = pct >= a.min_match and len(resyncs) <= a.max_resync
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
