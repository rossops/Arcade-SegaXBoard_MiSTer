"""FD1094 decryptor: every program word the RTL produces must equal MAME's
decrypt_one for random addresses, states and encrypted values with a real key
(317-0056, Thunder Blade). One wrong bit in the swap network turns the CPU's
program into garbage on the first instruction that hits it, and a masking
mistake makes the game crash on a branch."""
import random, sys, os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, Timer
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from models.fd1094 import decrypt_one

KEYFILE = os.path.join(os.path.dirname(__file__), "..", "..", "golden", "thndrbld", "keyrom.hex")


def load_key():
    return [int(l, 16) for l in open(KEYFILE) if l.strip()]


@cocotb.test()
async def random_words(dut):
    key = load_key()
    assert len(key) == 8192
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    dut.rst.value = 1
    dut.fd1094_we.value = 0; dut.prog_addr.value = 0; dut.prog_data.value = 0
    dut.dec_en.value = 1; dut.vrq.value = 1; dut.op_n.value = 0
    dut.st.value = 0; dut.addr.value = 0; dut.enc.value = 0; dut.rom_ok.value = 0; dut.key_data.value = 0
    for _ in range(3): await RisingEdge(dut.clk)
    dut.rst.value = 0
    # global key bytes 0..3 arrive as key RAM writes
    for i in range(4):
        dut.fd1094_we.value = 1; dut.prog_addr.value = i; dut.prog_data.value = key[i]
        await RisingEdge(dut.clk)
    dut.fd1094_we.value = 0
    await RisingEdge(dut.clk)

    rng = random.Random(1094)
    cases = []
    for i in range(30000):
        r = rng.random()
        if r < 0.05:
            addr = rng.randrange(8)                       # vector words and the wrap rule
        elif r < 0.10:
            addr = rng.choice([0x1000, 0x1001, 0x0fff, 0x2000, 0x2003, 0x3000, 0x3ffc])
        else:
            addr = rng.randrange(0x40000)                 # 512 KB of program space, word address
        state = rng.randrange(256)
        val = rng.randrange(0x10000)
        cases.append((addr, state, val))

    for i, (addr, state, val) in enumerate(cases):
        dut.st.value = state; dut.addr.value = addr; dut.enc.value = val
        await Timer(1, unit="ns")
        dut.key_data.value = key[int(dut.key_addr.value)]  # external key RAM, combinational for the test
        await Timer(1, unit="ns")
        dut.rom_ok.value = 1
        await RisingEdge(dut.clk)
        dut.rom_ok.value = 0
        await ReadOnly()
        got = int(dut.dec.value)
        exp = decrypt_one(addr, val, key, state, addr < 4)
        assert got == exp, f"case {i}: addr {addr:06x} state {state:02x} enc {val:04x}: rtl {got:04x} model {exp:04x}"
        await RisingEdge(dut.clk)

    # data-space reads pass through untouched
    dut.op_n.value = 1; dut.enc.value = 0x1234; dut.rom_ok.value = 1
    await RisingEdge(dut.clk); await ReadOnly()
    assert int(dut.dec.value) == 0x1234


def test_fd1094():
    from runner import run
    run("jts16_fd1094_dec", ["rtl/cpu/fd1094/jts16_fd1094_dec.v"], "test_fd1094")
