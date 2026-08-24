"""CXD1095: reads mix input pins and output latch per nibble direction;
/ODEN forces inputs. After Burner's coin, DIP and control reads all go
through this, and the display-enable / sound-reset outputs on port C."""
import random, sys, os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from models.cxd1095 import Cxd1095


@cocotb.test()
async def random_ops(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    for s in ("cs", "we", "addr", "din"): getattr(dut, s).value = 0
    dut.oden_n.value = 1
    for s in ("in_a", "in_b", "in_c", "in_d", "in_e"): getattr(dut, s).value = 0
    dut.reset.value = 1
    for _ in range(3): await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)
    m = Cxd1095()
    rng = random.Random(1095)
    names = ["in_a", "in_b", "in_c", "in_d", "in_e"]
    for i in range(20000):
        r = rng.random()
        if r < 0.3:
            addr = rng.choice([0, 1, 2, 3, 4, 6, 7, 6, 7])
            data = rng.randrange(256)
            m.write(addr, data)
            dut.cs.value = 1; dut.we.value = 1; dut.addr.value = addr; dut.din.value = data
            await RisingEdge(dut.clk)
            dut.cs.value = 0; dut.we.value = 0
            await RisingEdge(dut.clk)
        elif r < 0.5:
            p = rng.randrange(5)
            v = rng.randrange(16 if p == 4 else 256)
            m.inputs[p] = v
            getattr(dut, names[p]).value = v
            await RisingEdge(dut.clk)
        elif r < 0.55:
            m.oden_n = rng.randrange(2)
            dut.oden_n.value = m.oden_n
            await RisingEdge(dut.clk)
        else:
            addr = rng.randrange(8)
            dut.cs.value = 1; dut.we.value = 0; dut.addr.value = addr
            await ReadOnly()
            got = int(dut.dout.value)
            exp = m.read(addr)
            assert got == exp, f"op {i}: read[{addr}] = {got:02x} model {exp:02x} oden={m.oden_n} dir={m.ddir}"
            outs = [int(dut.out_a.value), int(dut.out_b.value), int(dut.out_c.value), int(dut.out_d.value)]
            for p in range(4):
                assert outs[p] == m.output(p), f"op {i}: out {p} = {outs[p]:02x} model {m.output(p):02x}"
            await RisingEdge(dut.clk)
            dut.cs.value = 0


def test_cxd1095():
    from runner import run
    run("xb_cxd1095", ["rtl/io/xb_cxd1095.sv"], "test_cxd1095")
