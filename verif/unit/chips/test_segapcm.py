"""315-5218: per-tick output must equal MAME's model (Python port) with a
random ROM and random channel programming including loop/end/stop
semantics and bank bits. After Burner's engine/voice samples live here."""
import random, sys, os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, ClockCycles

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from models.segapcm import SegaPCM

ROM = bytes(random.Random(5218).randrange(256) for _ in range(0x10000)) + bytes()  # 64 KB test ROM


async def serve_rom(dut):
    """SDRAM p6 stand-in: word reads from ROM (0xFF beyond), 6-cycle latency."""
    dut.rom_ack.value = 0
    prev = 0
    while True:
        await RisingEdge(dut.clk)
        req = int(dut.rom_req.value)
        if req and not prev:
            a = int(dut.rom_addr.value) * 2 - 0x120000     # SDR_PCM_BASE
            lo = ROM[a] if 0 <= a < len(ROM) else 0xFF
            hi = ROM[a + 1] if 0 <= a + 1 < len(ROM) else 0xFF
            await ClockCycles(dut.clk, 6)
            dut.rom_dout.value = lo | (hi << 8)
            dut.rom_ack.value = 1
            await RisingEdge(dut.clk)
            dut.rom_ack.value = 0
        prev = req


async def z80_write(dut, addr, data):
    dut.cs.value = 1; dut.we.value = 1; dut.addr.value = addr; dut.din.value = data
    await RisingEdge(dut.clk)
    dut.cs.value = 0; dut.we.value = 0
    await RisingEdge(dut.clk)


@cocotb.test()
async def random_channels(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    for s in ("tick", "cs", "we", "addr", "din", "rom_ack", "rom_dout"): getattr(dut, s).value = 0
    dut.bankmask.value = 0x70
    dut.reset.value = 1
    for _ in range(3): await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)
    cocotb.start_soon(serve_rom(dut))
    m = SegaPCM(ROM)
    rng = random.Random(1)
    for t in range(600):
        # reprogram a few channels between ticks (only when the engine idles)
        for _ in range(rng.randrange(3)):
            ch = rng.randrange(16)
            prog = {
                0x02: rng.randrange(128), 0x03: rng.randrange(128),
                0x04: rng.randrange(256), 0x05: rng.randrange(1),          # loop within the 64 KB ROM
                0x06: rng.randrange(1, 4), 0x07: rng.choice([0x40, 0x80, 0x100 - 1, rng.randrange(256)]),
                0x84: rng.randrange(256), 0x85: rng.randrange(1),
                0x86: rng.choice([0x00, 0x02, 0x00, 0x10, 0x01]),
            }
            for off, val in prog.items():
                m.write(8 * ch + off, val)
                await z80_write(dut, 8 * ch + off, val)
        exp = m.tick()
        dut.tick.value = 1
        await RisingEdge(dut.clk)
        dut.tick.value = 0
        # engine: up to 16 channels x ~12 cycles
        for _ in range(400):
            await RisingEdge(dut.clk)
            if int(dut.es.value) == 0: break
        await ReadOnly()
        got = (int(dut.out_l.value.to_signed()), int(dut.out_r.value.to_signed()))
        assert got == exp, f"tick {t}: got {got} expected {exp}"
        await RisingEdge(dut.clk)
        # register state must match too (address write-back, stop flags)
        for ch in range(16):
            for off in (0x84, 0x85, 0x86):
                dut.cs.value = 1; dut.we.value = 0; dut.addr.value = 8 * ch + off
                await RisingEdge(dut.clk); await ReadOnly()
                await RisingEdge(dut.clk); await ReadOnly()
                v = int(dut.dout.value)
                assert v == m.read(8 * ch + off), f"tick {t}: ch{ch} reg {off:02x} = {v:02x} model {m.read(8*ch+off):02x}"
                await RisingEdge(dut.clk)
        dut.cs.value = 0


def test_segapcm():
    from runner import run
    run("xb_segapcm_5218", ["rtl/xb_pkg.sv", "rtl/audio/xb_segapcm_5218.sv"], "test_segapcm")
