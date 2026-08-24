"""315-5250 compare/timer, ported from MAME segaic16_m.cpp."""
from .util import s16, combine


class CmpTimer5250:
    def __init__(self):
        self.regs = [0] * 16
        self.counter = 0
        self.bit = 0
        self.exck = False
        self.irq = False      # 68000 interrupt line
        self.zint = False     # Z80 NMI line

    def exck_w(self, state):
        state = bool(state)
        if self.exck == state:
            return
        self.exck = state
        if not self.exck:
            return
        old = self.counter
        if self.regs[10] & 1:
            self.counter = (self.counter + 1) & 0xffff
        if old == 0xfff:
            self.irq = True
            self.counter = self.regs[8] & 0xfff

    def interrupt_ack(self):
        self.irq = False

    def read(self, offset):
        o = offset & 15
        if o in (0, 1, 2, 3, 4): return self.regs[o]
        if o == 5: return self.regs[1]
        if o == 6: return self.regs[2]
        if o == 7: return self.regs[7]
        if o in (9, 0xd):
            self.interrupt_ack()
        return 0xffff

    def write(self, offset, data, mem_mask=0xffff):
        o = offset & 15
        if o == 0:
            self.regs[0] = combine(self.regs[0], data, mem_mask); self.execute()
        elif o == 1:
            self.regs[1] = combine(self.regs[1], data, mem_mask); self.execute()
        elif o == 2:
            self.regs[2] = combine(self.regs[2], data, mem_mask); self.execute(True)
        elif o == 4:
            self.regs[4] = 0; self.bit = 0
        elif o == 6:
            self.regs[2] = combine(self.regs[2], data, mem_mask); self.execute()
        elif o in (8, 0xc):
            self.regs[8] = combine(self.regs[8], data, mem_mask)
        elif o in (9, 0xd):
            self.interrupt_ack()
        elif o in (0xa, 0xe):
            self.regs[10] = combine(self.regs[10], data, mem_mask)
        elif o in (0xb, 0xf):
            self.regs[11] = data & 0xff
            self.zint = True

    def zread(self):
        self.zint = False
        return self.regs[11]

    def execute(self, update_history=False):
        b1, b2, v = s16(self.regs[0]), s16(self.regs[1]), s16(self.regs[2])
        mn, mx = min(b1, b2), max(b1, b2)
        if v < mn:
            self.regs[7] = mn & 0xffff; self.regs[3] = 0x8000
        elif v > mx:
            self.regs[7] = mx & 0xffff; self.regs[3] = 0x4000
        else:
            self.regs[7] = v & 0xffff; self.regs[3] = 0
        if update_history:
            self.regs[4] = (self.regs[4] | (int(self.regs[3] == 0) << self.bit)) & 0xffff
            self.bit += 1
