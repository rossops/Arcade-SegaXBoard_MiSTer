"""315-5211A (X Board) sprite generator, ported from MAME sega16sp.cpp
sega_outrun_sprite_device::draw with m_is_xboard = true.

render(list_words, rom_dwords, banks) -> 224 x 320 grid of framebuffer
pixels (0xFFFF = empty) in screen coordinates (x origin 190, y origin 0),
clipped to the screen like MAME's cliprect.
"""
WIDTH, HEIGHT = 320, 224
XORIGIN, YORIGIN = 190, 0


def s16(v):
    v &= 0xffff
    return v - 0x10000 if v & 0x8000 else v


def render(spriteram, rom, numbanks, width=WIDTH, height=HEIGHT, scale=1):
    """spriteram: 2048 words (the buffer rendered); rom: list of 32-bit
    dwords (REGION32_LE order); numbanks = rom bytes / 0x40000.
    scale=2 renders the enhanced 2x mode: positions and row counts doubled,
    zoom thresholds doubled so the source is sampled at half steps."""
    th = 0x200 * scale
    xorigin = XORIGIN * scale
    fb = [[0xFFFF] * width for _ in range(height)]
    min_x, max_x, min_y, max_y = 0, width - 1, 0, height - 1
    for base in range(0, 2048, 8):
        data = spriteram[base:base + 8]
        if data[0] & 0x8000:
            break
        hide = data[0] & 0x5000
        bank = (data[0] >> 9) & 7
        top = ((data[0] & 0x1ff) - 0x100) * scale
        addr = data[1]
        pitch = s16((data[2] >> 1) | ((data[4] & 0x1000) << 3)) >> 8
        xpos = data[2] & 0x1ff
        vzoom = data[3] & 0x7ff
        ydelta = 1 if (data[4] & 0x8000) else -1
        flip = (~data[4] >> 14) & 1
        xdelta = 1 if (data[4] & 0x2000) else -1
        hzoom = data[4] & 0x7ff
        height_ = (data[5] & 0xfff) + 1
        colpri = ((data[6] & 0xff) << 4) | (((data[3] >> 12) & 7) << 12)
        if xpos < 0x80 and xdelta < 0:
            xpos += 0x200
        xpos *= scale
        height_ *= scale
        if hide:
            continue
        if numbanks:
            bank %= numbanks
        spritebase = 0x10000 * bank
        if vzoom < 0x40: vzoom = 0x40
        if hzoom < 0x40: hzoom = 0x40
        yacc = 0
        y = top
        ytarget = top + ydelta * height_
        while y != ytarget:
            sy = y - YORIGIN * scale
            if min_y <= sy <= max_y:
                row = fb[sy]
                xacc = 0
                a = addr
                x = xpos
                while (xdelta > 0 and x - xorigin <= max_x) or (xdelta < 0 and x - xorigin >= min_x):
                    pixels = rom[spritebase + (a & 0xffff)]
                    if flip:
                        a -= 1
                    else:
                        a += 1
                        pixels = (((pixels << 28) & 0xf0000000) | ((pixels << 20) & 0x0f000000) |
                                  ((pixels << 12) & 0x00f00000) | ((pixels << 4) & 0x000f0000) |
                                  ((pixels >> 4) & 0x0000f000) | ((pixels >> 12) & 0x00000f00) |
                                  ((pixels >> 20) & 0x000000f0) | ((pixels >> 28) & 0x0000000f))
                    last_data = (pixels & 0x0f000000) == 0x0f000000
                    for _ in range(8):
                        pix = pixels & 0xf
                        while xacc < th:
                            sx = x - xorigin
                            if min_x <= sx <= max_x and pix != 0 and pix != 15:
                                row[sx] = colpri | pix
                            x += xdelta
                            xacc += hzoom
                        xacc -= th
                        pixels >>= 4
                    if last_data:
                        break
            yacc += vzoom
            addr = (addr + pitch * (yacc // th)) & 0xffff
            yacc %= th
            y += ydelta
    return fb


def load_rom_dwords(zf, files):
    """files in ROM_LOAD32_BYTE order (4 per 512 KB group)."""
    out = []
    for i in range(0, len(files), 4):
        parts = [zf.read([m for m in zf.namelist() if m.split('/')[-1] == n][0]) for n in files[i:i + 4]]
        for j in range(len(parts[0])):
            out.append(parts[0][j] | (parts[1][j] << 8) | (parts[2][j] << 16) | (parts[3][j] << 24))
    return out
