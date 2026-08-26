"""Analog response curves: the OSD option must be bit-exact pass-through at
Linear/100% (the games' MAME-matched ranges depend on it) and must follow
the documented curve/range arithmetic everywhere else, full lock included
(-128 stays -128, so After Burner's rolls and the wheels' full steering
remain reachable). Exhaustive over every input value, curve and range."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly


def model(v, curve, rng):
    mag = -v if v < 0 else v                      # 0..128
    if curve == 1:   mag = (mag * mag) >> 7
    elif curve == 2: mag = (mag * mag * mag) >> 14
    if rng == 1:     mag = (mag * 3) >> 2
    elif rng == 2:   mag = mag >> 1
    out = -mag if v < 0 else mag
    return out & 0xFF


@cocotb.test()
async def exhaustive(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    dut.axis.value = 0; dut.curve.value = 0; dut.range.value = 0
    for _ in range(6): await RisingEdge(dut.clk)
    for curve in range(3):
        for rng in range(3):
            for v in range(-128, 128):
                dut.axis.value = v & 0xFF; dut.curve.value = curve; dut.range.value = rng
                for _ in range(5): await RisingEdge(dut.clk)
                await ReadOnly()
                got = int(dut.out.value)
                exp = model(v, curve, rng)
                assert got == exp, f"curve {curve} range {rng} in {v}: rtl {got:02x} model {exp:02x}"
                await RisingEdge(dut.clk)
    # linear/100% is pass-through: checked above for every v (model returns v)


def test_ana_shape():
    from runner import run
    run("xb_ana_shape", ["rtl/io/xb_ana_shape.sv"], "test_ana_shape")
