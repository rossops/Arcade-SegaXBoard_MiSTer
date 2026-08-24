"""Sony CXD1095 port expander, ported from MAME cxd1095.cpp, plus the
X Board /ODEN pin (MacDonald): low forces ports A-D to inputs."""


class Cxd1095:
    def __init__(self):
        self.latch = [0] * 5
        self.ddir = [0xff] * 5       # 1 = input
        self.inputs = [0] * 5
        self.oden_n = 1

    def eff_dir(self, port):
        if port < 4 and not self.oden_n:
            return 0xff
        return self.ddir[port]

    def read(self, offset):
        if offset < 5:
            mask = self.eff_dir(offset)
            if offset == 4:
                mask &= 0x0f
            data = self.inputs[offset] & mask
            return data | (self.latch[offset] & ~self.eff_dir(offset) & 0xff)
        return 0

    def write(self, offset, data):
        data &= 0xff
        if offset < 5:
            if offset == 4:
                data &= 0x0f
            self.latch[offset] = data
        elif offset == 6:
            for port in range(4):
                self.ddir[port] = (0x0f if data & 1 else 0) | (0xf0 if data & 2 else 0)
                data >>= 2
        elif offset == 7:
            self.ddir[4] = (data & 0x0f) | 0xf0

    def output(self, port):
        """Pin state driven by the chip (MAME dataout = latch & ~dir)."""
        return self.latch[port] & ~self.eff_dir(port) & 0xff
