"""315-5248: every read must equal MAME's model for random operands, byte
writes included. A wrong sign or byte-merge here corrupts every game
calculation (positions, zoom) silently."""
import random, sys, os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from models.mult5248 import Mult5248


async def bus_write(dut, addr, data, be):
    dut.cs.value = 1; dut.we.value = 1; dut.addr.value = addr
    dut.din.value = data; dut.be.value = be
    await RisingEdge(dut.clk)
    dut.cs.value = 0; dut.we.value = 0
    await RisingEdge(dut.clk)


async def bus_read(dut, addr):
    dut.cs.value = 1; dut.we.value = 0; dut.addr.value = addr
    await ReadOnly()
    v = int(dut.dout.value)
    await RisingEdge(dut.clk)
    dut.cs.value = 0
    return v


@cocotb.test()
async def random_ops(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    dut.cs.value = 0; dut.we.value = 0; dut.addr.value = 0; dut.din.value = 0; dut.be.value = 3
    dut.reset.value = 1
    for _ in range(3): await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)
    model = Mult5248()
    rng = random.Random(5248)
    for i in range(20000):
        if rng.random() < 0.6:
            addr = rng.randrange(4)
            data = rng.randrange(0x10000)
            be = rng.choice([3, 3, 3, 1, 2])
            mask = (0xff00 if be & 2 else 0) | (0x00ff if be & 1 else 0)
            model.write(addr, data, mask)
            await bus_write(dut, addr, data, be)
        else:
            addr = rng.randrange(4)
            exp = model.read(addr)
            got = await bus_read(dut, addr)
            assert got == exp, f"op {i}: read[{addr}] = {got:04x}, model {exp:04x} regs={model.regs}"


def test_mult5248():
    from runner import run
    run("xb_math_5248", ["rtl/cpu/xb_math_5248.sv"], "test_mult5248")
