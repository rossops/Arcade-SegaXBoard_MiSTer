"""315-5197 'TILEMAP_16B' renderer, ported from MAME segaic16.cpp
(tilemap_16b_draw_layer, draw_virtual_tilemap, tilemap_16b_tile_info,
tilemap_16b_text_info) reduced to per-pixel form. Produces, per layer, the
(priority, palette index) of each opaque pixel, and a MAME-style mix.

Inputs: tileram (32768 words), textram (2048 words), tile ROM planes
(three 64 KB byte strings, plane 2 = MSB), latched register sets.
"""
WIDTH, HEIGHT = 320, 224
COLORBASE = 0x1C00


def latch_regs(textram):
    """Register sets as MAME latches them at line 261."""
    pages = [textram[0xE80 // 2 + i] for i in range(4)]
    ysc = [textram[0xE90 // 2 + i] for i in range(4)]
    xsc = [textram[0xE98 // 2 + i] for i in range(4)]
    return pages, ysc, xsc


def tile_pen(planes, code, row, col):
    a = (code << 3) | row
    b = 7 - col
    return (((planes[2][a] >> b) & 1) << 2) | (((planes[1][a] >> b) & 1) << 1) | ((planes[0][a] >> b) & 1)


def render_layer(which, tileram, textram, planes, regs):
    """Return a HEIGHT x WIDTH list of (prio, pal_index) or None (pen 0)."""
    pages, ysc, xsc = regs
    out = [[None] * WIDTH for _ in range(HEIGHT)]
    xscroll, yscroll, pg = xsc[which], ysc[which], pages[which]
    colmode = bool(yscroll & 0x8000)
    for y in range(HEIGHT):
        rowscroll = textram[0xF80 // 2 + 0x20 * which + (y >> 3)]
        effx = rowscroll if (xscroll & 0x8000) else xscroll
        alt = bool(rowscroll & 0x8000)
        effpages = pages[which + 2] if alt else pg
        effx_alt = xsc[which + 2]
        for x in range(WIDTH):
            if colmode:
                effy = textram[0xF16 // 2 + 0x20 * which + ((x + 8) >> 4)]
            else:
                effy = yscroll
            ex = effx
            if alt:
                ex = effx_alt
                effy = ysc[which + 2]
            ex = (0xC0 - ex) & 0x3FF
            effy &= 0x1FF
            px = (x + ex) & 0x3FF
            py = (y + effy) & 0x1FF
            quadrant = ((py >> 8) << 1) | (px >> 9)
            page = (effpages >> (4 * quadrant)) & 0xF
            word = tileram[page * 0x800 + ((py & 0xFF) >> 3) * 64 + ((px & 0x1FF) >> 3)]
            pen = tile_pen(planes, word & 0x1FFF, py & 7, px & 7)
            if pen:
                out[y][x] = ((word >> 15) & 1, COLORBASE + ((word >> 6) & 0x7F) * 8 + pen)
    return out


def render_text(textram, planes):
    out = [[None] * WIDTH for _ in range(HEIGHT)]
    for y in range(HEIGHT):
        for x in range(WIDTH):
            col = 24 + (x >> 3)
            word = textram[(y >> 3) * 64 + col]
            pen = tile_pen(planes, word & 0x1FF, y & 7, x & 7)
            if pen:
                out[y][x] = ((word >> 15) & 1, COLORBASE + ((word >> 9) & 7) * 8 + pen)
    return out


def mix(fg, bg, tx):
    """MAME screen_update order without road/sprites: returns (idx, mark) grids."""
    idx = [[0] * WIDTH for _ in range(HEIGHT)]
    mark = [[0] * WIDTH for _ in range(HEIGHT)]
    passes = [(bg, 0, 1), (bg, 1, 2), (fg, 0, 2), (fg, 1, 4), (tx, 0, 4), (tx, 1, 8)]
    for layer, prio, m in passes:
        for y in range(HEIGHT):
            row = layer[y]
            for x in range(WIDTH):
                p = row[x]
                if p is not None and p[0] == prio:
                    idx[y][x] = p[1]
                    mark[y][x] |= m
    return idx, mark
