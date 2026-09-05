"""After Burner stick options. What matters: with every option off the
module is invisible (the analog axis passes through bit-exact and the
D-pad flags stay low, so the core's original snap path is untouched); the
ramp reaches full lock (-128/127, the games need the extremes) at MAME's
pace and returns at the same pace; hold keeps the position and gives the
snap stick exactly three positions; calibration takes the rest position as
centre and saturates rather than wrapping."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly


def s8(v):
    v = int(v) & 0xFF
    return v - 256 if v & 0x80 else v


async def frame(dut):
    await RisingEdge(dut.clk)            # leave any ReadOnly phase before driving
    dut.frame.value = 1
    await RisingEdge(dut.clk)
    dut.frame.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)            # settle outside ReadOnly so callers may drive next


async def setup(dut, vst_en=0, ramp=0, recenter=1, cal=0):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    for sig in ("frame", "ax_in", "ay_in", "right", "left", "down", "up"):
        getattr(dut, sig).value = 0
    dut.vst_en.value = vst_en; dut.ramp.value = ramp
    dut.recenter.value = recenter; dut.cal.value = cal
    dut.reset.value = 1
    for _ in range(3): await RisingEdge(dut.clk)
    dut.reset.value = 0
    for _ in range(3): await RisingEdge(dut.clk)


@cocotb.test()
async def defaults_pass_through(dut):
    await setup(dut)
    for v in range(-128, 128):
        dut.ax_in.value = v & 0xFF; dut.ay_in.value = (-v) & 0xFF
        dut.right.value = v & 1; dut.up.value = (v >> 1) & 1
        await RisingEdge(dut.clk)
        await ReadOnly()
        assert s8(dut.ax_out.value) == v and s8(dut.ay_out.value) == s8(-v), f"in {v}"
        assert int(dut.x_dpad.value) == 0 and int(dut.y_dpad.value) == 0
        await RisingEdge(dut.clk)


@cocotb.test()
async def ramp_and_recenter(dut):
    await setup(dut, vst_en=1, ramp=1, recenter=1)
    dut.ax_in.value = 40 & 0xFF          # analog shows through when the D-pad is idle
    await RisingEdge(dut.clk); await ReadOnly()
    assert s8(dut.ax_out.value) == 40 and int(dut.x_dpad.value) == 0
    await RisingEdge(dut.clk)
    dut.right.value = 1
    seen = []
    for _ in range(30):
        await frame(dut)
        seen.append(s8(dut.ax_out.value))
        assert int(dut.x_dpad.value) == 1
    assert seen[:3] == [5, 10, 15] and seen.index(127) == 25, seen   # 26 frames to full lock
    assert seen[-1] == 127
    dut.right.value = 0
    back = []
    for _ in range(27):
        await frame(dut)
        back.append(s8(dut.ax_out.value))
    assert back[0] == 122 and back[-1] == 40 and 0 not in back[:25], back  # eases back, then analog again
    assert int(dut.x_dpad.value) == 0
    # the other way, on Y: up is negative and saturates at -128
    dut.up.value = 1
    for _ in range(26): await frame(dut)
    assert s8(dut.ay_out.value) == -128 and int(dut.y_dpad.value) == 1
    dut.up.value = 0
    # crossing centre from below stops at 0 for one frame, then continues
    dut.ax_in.value = 0; dut.right.value = 0; dut.left.value = 1
    for _ in range(30): await frame(dut)      # settle: left held long enough
    dut.left.value = 0; dut.right.value = 1
    vals = []
    for _ in range(28):
        await frame(dut)
        vals.append(s8(dut.ax_out.value))
    assert vals[0] == -123 and 0 in vals and vals[vals.index(0) + 1] == 5, vals


@cocotb.test()
async def snap_hold_three_positions(dut):
    await setup(dut, vst_en=1, ramp=0, recenter=0)
    dut.right.value = 1; await frame(dut)
    assert s8(dut.ax_out.value) == 127
    dut.right.value = 0
    for _ in range(5): await frame(dut)
    assert s8(dut.ax_out.value) == 127 and int(dut.x_dpad.value) == 1   # holds
    dut.left.value = 1; await frame(dut)
    assert s8(dut.ax_out.value) == 0                                     # centre first
    await frame(dut)
    assert s8(dut.ax_out.value) == -128                                  # then full left
    dut.left.value = 0; dut.right.value = 1; await frame(dut)
    assert s8(dut.ax_out.value) == 0
    dut.right.value = 0
    await frame(dut)
    assert int(dut.x_dpad.value) == 0        # at centre with nothing held: analog again


@cocotb.test()
async def ramp_hold(dut):
    await setup(dut, vst_en=1, ramp=1, recenter=0)
    dut.down.value = 1
    for _ in range(4): await frame(dut)
    dut.down.value = 0
    for _ in range(10): await frame(dut)
    assert s8(dut.ay_out.value) == 20 and int(dut.y_dpad.value) == 1
    dut.up.value = 1
    for _ in range(4): await frame(dut)
    assert s8(dut.ay_out.value) == 0 and int(dut.y_dpad.value) == 1     # up still held
    dut.up.value = 0; await frame(dut)
    assert int(dut.y_dpad.value) == 0


@cocotb.test()
async def zero_calibration(dut):
    await setup(dut, cal=0)
    dut.ax_in.value = 7 & 0xFF; dut.ay_in.value = (-9) & 0xFF          # drifting rest position
    for _ in range(2): await RisingEdge(dut.clk)
    await ReadOnly()
    assert s8(dut.ax_out.value) == 7 and s8(dut.ay_out.value) == -9    # off: raw
    await RisingEdge(dut.clk)
    dut.cal.value = 1
    for _ in range(3): await RisingEdge(dut.clk)
    await ReadOnly()
    assert s8(dut.ax_out.value) == 0 and s8(dut.ay_out.value) == 0     # rest is now centre
    await RisingEdge(dut.clk)
    dut.ax_in.value = -128 & 0xFF; dut.ay_in.value = 127
    await RisingEdge(dut.clk); await ReadOnly()
    assert s8(dut.ax_out.value) == -128                                 # 7 - 128 saturates, no wrap
    assert s8(dut.ay_out.value) == 127                                  # 127 + 9 saturates
    await RisingEdge(dut.clk)
    dut.ax_in.value = 127; dut.ay_in.value = -128 & 0xFF
    await RisingEdge(dut.clk); await ReadOnly()
    assert s8(dut.ax_out.value) == 120 and s8(dut.ay_out.value) == -119
    await RisingEdge(dut.clk)
    # reset with the option on resamples at release (boot with it in the config)
    dut.ax_in.value = -3 & 0xFF; dut.ay_in.value = 4
    dut.reset.value = 1
    for _ in range(3): await RisingEdge(dut.clk)
    dut.reset.value = 0
    for _ in range(3): await RisingEdge(dut.clk)
    await ReadOnly()
    assert s8(dut.ax_out.value) == 0 and s8(dut.ay_out.value) == 0


def test_stick():
    from runner import run
    run("xb_stick", ["rtl/io/xb_stick.sv"], "test_stick")
