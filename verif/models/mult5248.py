"""315-5248 multiplier, ported from MAME segaic16_m.cpp."""
from .util import s16, combine


class Mult5248:
    def __init__(self):
        self.regs = [0, 0]

    def read(self, offset):
        o = offset & 3
        if o == 0: return self.regs[0]
        if o == 1: return self.regs[1]
        p = s16(self.regs[0]) * s16(self.regs[1])
        if o == 2: return (p >> 16) & 0xffff
        return p & 0xffff

    def write(self, offset, data, mem_mask=0xffff):
        self.regs[offset & 1] = combine(self.regs[offset & 1], data, mem_mask)
