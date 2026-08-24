"""ADC0804 + mux: conversion timing (74 clocks), channel select from port C
bits 4:2, the per-game reverse mask, and /INTR set on completion / cleared by
a read. After Burner reads the stick through this path every frame."""
import random, sys, os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from models.adc0804 import Adc0804


@cocotb.test()
async def random_ops(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    for s in ("ce_adc", "cs", "we", "channel", "adc_reverse"): getattr(dut, s).value = 0
    names = ["ch0", "ch1", "ch2", "ch3", "ch4", "ch5", "ch6", "ch7"]
    for n in names: getattr(dut, n).value = 0x80
    dut.reset.value = 1
    for _ in range(3): await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)
    m = Adc0804()
    rng = random.Random(804)
    for i in range(30000):
        r = rng.random()
        if r < 0.03:
            m.write(); dut.cs.value = 1; dut.we.value = 1
            await RisingEdge(dut.clk); dut.cs.value = 0; dut.we.value = 0
        elif r < 0.06:
            dut.cs.value = 1; dut.we.value = 0
            await ReadOnly()
            got = int(dut.dout.value); exp = m.read()
            assert got == exp, f"op {i}: read {got:02x} model {exp:02x}"
            await RisingEdge(dut.clk); dut.cs.value = 0
        elif r < 0.08:
            c = rng.randrange(8); m.channel = c; dut.channel.value = c
            await RisingEdge(dut.clk)
        elif r < 0.09:
            m.reverse = rng.randrange(256); dut.adc_reverse.value = m.reverse
            await RisingEdge(dut.clk)
        elif r < 0.12:
            c = rng.randrange(8); v = rng.randrange(256)
            m.channels[c] = v; getattr(dut, names[c]).value = v
            await RisingEdge(dut.clk)
        else:
            # one ADC clock enable
            m.clock(); dut.ce_adc.value = 1
            await RisingEdge(dut.clk); dut.ce_adc.value = 0
        await ReadOnly()
        assert int(dut.intr.value) == int(m.intr), f"op {i}: intr {int(dut.intr.value)} model {m.intr}"
        await RisingEdge(dut.clk)


def test_adc0804():
    from runner import run
    run("xb_adc0804", ["rtl/io/xb_adc0804.sv"], "test_adc0804")
