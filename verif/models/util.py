def s16(v):
    v &= 0xffff
    return v - 0x10000 if v & 0x8000 else v


def s32(v):
    v &= 0xffffffff
    return v - 0x100000000 if v & 0x80000000 else v


def combine(old, data, mem_mask):
    """MAME COMBINE_DATA for 16-bit registers."""
    return ((old & ~mem_mask) | (data & mem_mask)) & 0xffff


def c_div(a, b):
    """C-style truncating integer division."""
    q = abs(a) // abs(b)
    return -q if (a < 0) != (b < 0) else q
