"""315-5250: compare/clamp/history registers, the 12-bit timer driven by a
V0 stream (fires on the tick after 0xFFF regardless of enable, reloads in
the same tick, level-held until ack), and the Z80 sound latch/NMI. After
Burner II times its raster effects on IRQ2, so an off-by-one tick here shifts
the whole frame."""
import random, sys, os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from models.cmptimer5250 import CmpTimer5250


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
    await RisingEdge(dut.clk)
    return v


async def tick_exck(dut, model, state):
    dut.exck.value = state
    model.exck_w(state)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


async def check_lines(dut, model, where):
    await ReadOnly()
    assert int(dut.timer_irq.value) == int(model.irq), f"{where}: irq {int(dut.timer_irq.value)} model {model.irq}"
    assert int(dut.snd_nmi.value) == int(model.zint), f"{where}: nmi {int(dut.snd_nmi.value)} model {model.zint}"
    await RisingEdge(dut.clk)


@cocotb.test()
async def random_ops(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    for s in ("cs", "we", "addr", "din", "exck", "snd_read"): getattr(dut, s).value = 0
    dut.be.value = 3
    dut.reset.value = 1
    for _ in range(3): await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)
    model = CmpTimer5250()
    rng = random.Random(5250)
    exck = 0
    for i in range(20000):
        r = rng.random()
        if r < 0.35:
            addr = rng.randrange(16)
            data = rng.randrange(0x10000)
            if rng.random() < 0.2: data = rng.choice([0, 0xfff, 0xffe, 0x8000, 0x7fff, 1])
            be = rng.choice([3, 3, 3, 1, 2])
            mask = (0xff00 if be & 2 else 0) | (0x00ff if be & 1 else 0)
            model.write(addr, data, mask)
            await bus_write(dut, addr, data, be)
        elif r < 0.6:
            addr = rng.randrange(16)
            exp = model.read(addr)
            got = await bus_read(dut, addr)
            assert got == exp, f"op {i}: read[{addr:x}] = {got:04x}, model {exp:04x}"
        elif r < 0.95:
            exck ^= 1
            await tick_exck(dut, model, exck)
        else:
            dut.snd_read.value = 1
            model.zread()
            await RisingEdge(dut.clk)
            dut.snd_read.value = 0
            await RisingEdge(dut.clk)
        await check_lines(dut, model, f"op {i}")
    assert int(dut.snd_latch.value) == model.regs[11]


@cocotb.test()
async def timer_parked_at_fff_fires_without_enable(dut):
    """MacDonald: count 0xFFF interrupts at the input clock rate even with the
    enable bit clear."""
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    for s in ("cs", "we", "addr", "din", "exck", "snd_read"): getattr(dut, s).value = 0
    dut.be.value = 3
    dut.reset.value = 1
    for _ in range(3): await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)
    model = CmpTimer5250()
    # reload = 0xfff, enable = 0, then get the counter to 0xfff: enable once
    for addr, data in ((8, 0xfff), (0xa, 1)):
        model.write(addr, data); await bus_write(dut, addr, data, 3)
    fired = 0
    for n in range(0x1000 + 40):
        for st in (1, 0):
            await tick_exck(dut, model, st)
        if int(dut.timer_irq.value):
            fired += 1
            model.read(9); await bus_read(dut, 9)
            if fired == 1:
                model.write(0xa, 0); await bus_write(dut, 0xa, 0, 3)   # disable
    assert fired > 20, f"timer fired only {fired} times; expected free-running at 0xFFF"


def test_cmptimer5250():
    from runner import run
    run("xb_cmptimer_5250", ["rtl/cpu/xb_cmptimer_5250.sv"], "test_cmptimer5250")
