"""315-5275 road generator (X Board), ported from MAME segaic16_road.cpp
segaic16_road_outrun_decode / segaic16_road_outrun_draw with the X Board
parameters: colorbase1 0x1700, colorbase2 0x1720, colorbase3 0x1780,
xoffs -166, control mask 7 (bit 2 = direct scanline addressing).

render(roadbuf, control, gfx) -> (background, foreground) grids of palette
indices or None per pixel, in MAME's ROAD_BACKGROUND / ROAD_FOREGROUND
passes.
"""
WIDTH, HEIGHT = 320, 224
COLORBASE1, COLORBASE2, COLORBASE3, XOFFS = 0x1700, 0x1720, 0x1780, -166

PRIORITY_MAP = [[0x80, 0x81, 0x81, 0x87, 0, 0, 0, 0x00],
                [0x81, 0x81, 0x81, 0x8f, 0, 0, 0, 0x80]]


def decode(rom):
    """rom: 64 KB bytes -> gfx list of (256*2+1) rows x 512 pixel values."""
    length = len(rom)
    gfx = []
    for y in range(256 * 2):
        base = ((y & 0xff) * 0x40 + (y >> 8) * 0x8000) % length
        row = []
        for x in range(512):
            b0 = (rom[(base + (x >> 3)) % length] >> (~x & 7)) & 1
            b1 = (rom[(base + (x >> 3) + 0x4000) % length] >> (~x & 7)) & 1
            v = b0 | (b1 << 1)
            if 256 - 8 <= x < 256 and v == 3:
                v |= 4
            row.append(v)
        gfx.append(row)
    gfx.append([3] * 512)   # dummy road
    return gfx


def render(roadram, control, gfx):
    bg = [[None] * WIDTH for _ in range(HEIGHT)]
    fgp = [[None] * WIDTH for _ in range(HEIGHT)]
    dummy = 256 * 2
    for y in range(HEIGHT):
        data0 = roadram[0x000 + y]
        data1 = roadram[0x100 + y]
        # background pass
        color = -1
        c = control & 3
        if c == 0:
            if data0 & 0x800: color = data0 & 0x7f
        elif c == 1:
            if data0 & 0x800: color = data0 & 0x7f
            elif data1 & 0x800: color = data1 & 0x7f
        elif c == 2:
            if data1 & 0x800: color = data1 & 0x7f
            elif data0 & 0x800: color = data0 & 0x7f
        else:
            if data1 & 0x800: color = data1 & 0x7f
        if color != -1:
            for x in range(WIDTH):
                bg[y][x] = color | COLORBASE3
        # foreground pass
        if (data0 & 0x800) and (data1 & 0x800):
            continue
        src0 = gfx[dummy] if (data0 & 0x800) else gfx[0x000 + ((data0 >> 1) & 0xff)]
        idx0 = y if (control & 4) else (data0 & 0x1ff)
        hpos0 = roadram[0x200 + idx0] & 0xfff
        color0 = roadram[0x600 + idx0]
        src1 = gfx[dummy] if (data1 & 0x800) else gfx[0x100 + ((data1 >> 1) & 0xff)]
        idx1 = (0x100 + y) if (control & 4) else (data1 & 0x1ff)
        hpos1 = roadram[0x400 + idx1] & 0xfff
        color1 = roadram[0x600 + idx1]
        ct = {}
        ct[0x00] = COLORBASE1 ^ 0x00 ^ ((color0 >> 0) & 1)
        ct[0x01] = COLORBASE1 ^ 0x02 ^ ((color0 >> 1) & 1)
        ct[0x02] = COLORBASE1 ^ 0x04 ^ ((color0 >> 2) & 1)
        bgc = (color0 >> 8) & 0xf
        ct[0x03] = ct[0x00] if (data0 & 0x200) else (COLORBASE2 ^ 0x00 ^ bgc)
        ct[0x07] = COLORBASE1 ^ 0x06 ^ ((color0 >> 3) & 1)
        ct[0x10] = COLORBASE1 ^ 0x08 ^ ((color1 >> 4) & 1)
        ct[0x11] = COLORBASE1 ^ 0x0a ^ ((color1 >> 5) & 1)
        ct[0x12] = COLORBASE1 ^ 0x0c ^ ((color1 >> 6) & 1)
        bgc = (color1 >> 8) & 0xf
        ct[0x13] = ct[0x10] if (data1 & 0x200) else (COLORBASE2 ^ 0x10 ^ bgc)
        ct[0x17] = COLORBASE1 ^ 0x0e ^ ((color1 >> 7) & 1)
        row = fgp[y]
        off = (0x5f8 + XOFFS) & 0xfff
        if c == 0:
            if data0 & 0x800: continue
            h0 = (hpos0 - off) & 0xfff
            for x in range(WIDTH):
                p0 = src0[h0] if h0 < 0x200 else 3
                row[x] = ct[0x00 + p0]
                h0 = (h0 + 1) & 0xfff
        elif c in (1, 2):
            h0 = (hpos0 - off) & 0xfff
            h1 = (hpos1 - off) & 0xfff
            pm = PRIORITY_MAP[c - 1]
            for x in range(WIDTH):
                p0 = src0[h0] if h0 < 0x200 else 3
                p1 = src1[h1] if h1 < 0x200 else 3
                row[x] = ct[0x10 + p1] if (pm[p0] >> p1) & 1 else ct[0x00 + p0]
                h0 = (h0 + 1) & 0xfff
                h1 = (h1 + 1) & 0xfff
        else:
            if data1 & 0x800: continue
            h1 = (hpos1 - off) & 0xfff
            for x in range(WIDTH):
                p1 = src1[h1] if h1 < 0x200 else 3
                row[x] = ct[0x10 + p1]
                h1 = (h1 + 1) & 0xfff
    return bg, fgp
