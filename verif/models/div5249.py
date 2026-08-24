"""315-5249 divider, ported from MAME segaic16_m.cpp."""
from .util import s16, s32, combine, c_div


class Div5249:
    def __init__(self):
        self.regs = [0] * 8

    def read(self, offset):
        o = offset & 7
        if o in (0, 1, 2, 4, 5, 6):
            return self.regs[o]
        return 0xffff

    def write(self, offset, data, mem_mask=0xffff):
        o = offset & 3
        if o < 3:
            self.regs[o] = combine(self.regs[o], data, mem_mask)
        if offset & 8:
            self.execute(offset & 4)

    def execute(self, mode):
        self.regs[6] = 0
        if mode == 0:
            dividend = s32((self.regs[0] << 16) | self.regs[1])
            divisor = s16(self.regs[2])
            if divisor == 0:
                quotient = dividend
                self.regs[6] |= 0x4000
            else:
                quotient = c_div(dividend, divisor)
            if quotient < -32768:
                quotient = -32768
                self.regs[6] |= 0x8000
            elif quotient > 32767:
                quotient = 32767
                self.regs[6] |= 0x8000
            self.regs[4] = quotient & 0xffff
            self.regs[5] = (dividend - quotient * divisor) & 0xffff
        else:
            dividend = ((self.regs[0] << 16) | self.regs[1]) & 0xffffffff
            divisor = self.regs[2] & 0xffff
            if divisor == 0:
                quotient = dividend
                self.regs[6] |= 0x4000
            else:
                quotient = dividend // divisor
            self.regs[4] = (quotient >> 16) & 0xffff
            self.regs[5] = quotient & 0xffff
