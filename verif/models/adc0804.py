"""ADC0804 with the X Board channel mux and reverse mask (MAME adc0804.cpp
+ segaxbd.cpp analog_r). Conversion takes 74 ADC clocks; the input is
sampled when the conversion completes; a read clears /INTR."""


class Adc0804:
    CYCLES = 74

    def __init__(self):
        self.channels = [0x80] * 8
        self.reverse = 0
        self.channel = 0
        self.busy = False
        self.count = 0
        self.result = 0
        self.intr = False

    def write(self):
        if not self.busy:
            self.busy = True
            self.count = 0

    def read(self):
        self.intr = False
        return self.result

    def clock(self):
        if not self.busy:
            return
        if self.count == self.CYCLES - 1:
            v = self.channels[self.channel]
            if (self.reverse >> self.channel) & 1:
                v = 255 - v
            self.result = v
            self.busy = False
            self.intr = True
        else:
            self.count += 1
