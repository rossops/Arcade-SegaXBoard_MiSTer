"""315-5218 SegaPCM, ported from MAME segapcm.cpp sound_stream_update with
BANK_512 (bankshift 12, bankmask 0x70). One call to tick() produces one
stereo sample (the chip runs at clock/128)."""


class SegaPCM:
    def __init__(self, rom, bankshift=12, bankmask=0x70):
        self.rom = rom                 # bytes; reads beyond the end return 0xFF
        self.ram = [0xFF] * 0x800
        self.low = [0] * 16
        self.bankshift, self.bankmask = bankshift, bankmask

    def read_byte(self, a):
        return self.rom[a] if a < len(self.rom) else 0xFF

    def write(self, offset, data):
        self.ram[offset & 0x7FF] = data & 0xFF

    def read(self, offset):
        return self.ram[offset & 0x7FF]

    def tick(self):
        outl = outr = 0
        for ch in range(16):
            r = 8 * ch
            regs = self.ram
            if regs[r + 0x86] & 1:
                continue
            offset = (regs[r + 0x86] & self.bankmask) << self.bankshift
            addr = (regs[r + 0x85] << 16) | (regs[r + 0x84] << 8) | self.low[ch]
            loop = (regs[r + 0x05] << 16) | (regs[r + 0x04] << 8)
            end = (regs[r + 6] + 1) & 0xFF
            stopped = False
            if (addr >> 16) == end:
                if regs[r + 0x86] & 2:
                    regs[r + 0x86] |= 1
                    stopped = True
                else:
                    addr = loop
            if not stopped:
                v = self.read_byte(offset + (addr >> 8)) - 0x80
                outl += v * (regs[r + 2] & 0x7F)
                outr += v * (regs[r + 3] & 0x7F)
                addr = (addr + regs[r + 7]) & 0xFFFFFF
            regs[r + 0x84] = (addr >> 8) & 0xFF
            regs[r + 0x85] = (addr >> 16) & 0xFF
            self.low[ch] = 0 if (regs[r + 0x86] & 1) else (addr & 0xFF)
        clamp = lambda x: max(-32768, min(32767, x))
        return clamp(outl), clamp(outr)
