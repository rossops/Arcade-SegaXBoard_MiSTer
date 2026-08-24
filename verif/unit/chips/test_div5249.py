"""315-5249: quotient/remainder/flags must match MAME for signed and unsigned
modes, including divide-by-zero (flag 0x4000, quotient = dividend) and the
signed clamp (flag 0x8000). After Burner's road and sprite maths run through
this chip; a wrong remainder sign shows up as jittering geometry."""
import random, sys, os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from models.div5249 import Div5249


async def bus_write(dut, addr, data, be):
    dut.cs.value = 1; dut.we.value = 1; dut.addr.value = addr
    dut.din.value = data; dut.be.value = be
    await RisingEdge(dut.clk)
    dut.cs.value = 0; dut.we.value = 0
    await RisingEdge(dut.clk)


async def bus_read(dut, addr):
    dut.cs.value = 1; dut.we.value = 0; dut.addr.value = addr
    # honour the stall: wait until rdy
    for _ in range(64):
        await ReadOnly()
        if int(dut.rdy.value):
            break
        await RisingEdge(dut.clk)
    assert int(dut.rdy.value), "divider never became ready"
    v = int(dut.dout.value)
    await RisingEdge(dut.clk)
    dut.cs.value = 0
    return v


def rand_operand(rng):
    r = rng.random()
    if r < 0.15: return rng.choice([0, 1, 0xffff, 0x8000, 0x7fff, 0xfffe])
    return rng.randrange(0x10000)


@cocotb.test()
async def random_ops(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    dut.cs.value = 0; dut.we.value = 0; dut.addr.value = 0; dut.din.value = 0; dut.be.value = 3
    dut.reset.value = 1
    for _ in range(3): await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)
    model = Div5249()
    rng = random.Random(5249)
    for i in range(6000):
        r = rng.random()
        if r < 0.5:
            # operand write, possibly triggering (bit 3) in either mode (bit 2)
            addr = rng.randrange(3) | (8 if rng.random() < 0.5 else 0) | (4 if rng.random() < 0.5 else 0)
            data = rand_operand(rng)
            be = rng.choice([3, 3, 3, 1, 2])
            mask = (0xff00 if be & 2 else 0) | (0x00ff if be & 1 else 0)
            model.write(addr, data, mask)
            await bus_write(dut, addr, data, be)
        else:
            addr = rng.choice([0, 1, 2, 4, 5, 6, 4, 5, 6])
            exp = model.read(addr)
            got = await bus_read(dut, addr)
            assert got == exp, (f"op {i}: read[{addr}] = {got:04x}, model {exp:04x} "
                                f"regs={[hex(x) for x in model.regs]}")


def test_div5249():
    from runner import run
    run("xb_math_5249", ["rtl/cpu/xb_math_5249.sv"], "test_div5249")
