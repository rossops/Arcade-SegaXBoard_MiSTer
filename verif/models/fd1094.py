"""Hitachi FD1094 decryption, a line-for-line port of MAME's
fd1094_device::decrypt_one (src/mame/sega/fd1094.cpp, Nicola Salmoria,
Andreas Naive, Charles MacDonald). The masked-opcode table is read from the
vendored jtcores decryptor so the model and the RTL share one list.

decrypt_one(address, val, key, state, vector_fetch): `address` is the word
address (byte address / 2), `key` the 8 KB key bytes, `state` the current
8-bit state (key[0] while in IRQ mode), `vector_fetch` true for the initial
SP/PC fetch (MAME passes it for byte addresses < 8)."""
import os, re

_HERE = os.path.dirname(os.path.abspath(__file__))
_VLOG = os.path.join(_HERE, "..", "..", "rtl", "cpu", "fd1094", "jts16_fd1094_dec.v")


def _bit(v, n):
    return (v >> n) & 1


def _bitswap16(v, *bits):
    out = 0
    for i, b in enumerate(bits):          # bits[0] is the source of output bit 15
        out |= _bit(v, b) << (15 - i)
    return out


def _load_masked():
    text = open(_VLOG).read()
    body = text[text.index("case( { val[15:1], 1'b0} )"):text.index("mask_en = 1;")]
    return set(int(m, 16) for m in re.findall(r"16'h([0-9a-f]{4})", body))


MASKED = _load_masked()


def masked(val, key_f):
    """MAME m_masked_opcodes_lookup: the fixed list (both key_F values) plus,
    for key_F, the PC-relative/branch families 4e80/50c8/6xxx."""
    if (val & 0xfffe) in MASKED:
        return True
    if key_f and ((val & 0xff80) == 0x4e80 or (val & 0xf0f8) == 0x50c8 or (val & 0xf000) == 0x6000):
        return True
    return False


def decrypt_one(address, val, key, state, vector_fetch):
    gkey1, gkey2, gkey3 = key[1], key[2], key[3]
    if state & 0x01: gkey1 ^= 0x04; gkey2 ^= 0x80; gkey3 ^= 0x80
    if state & 0x02: gkey1 ^= 0x01; gkey2 ^= 0x10; gkey3 ^= 0x01
    if state & 0x04: gkey1 ^= 0x80; gkey2 ^= 0x40; gkey3 ^= 0x04
    if state & 0x08: gkey1 ^= 0x20; gkey2 ^= 0x02; gkey3 ^= 0x20
    if state & 0x10: gkey1 ^= 0x02; gkey1 ^= 0x40; gkey2 ^= 0x08
    if state & 0x20: gkey1 ^= 0x08; gkey3 ^= 0x08; gkey3 ^= 0x10
    if state & 0x40: gkey1 ^= 0x10; gkey2 ^= 0x20; gkey2 ^= 0x04
    if state & 0x80: gkey2 ^= 0x01; gkey3 ^= 0x02; gkey3 ^= 0x40

    if (address & 0x0ffc) == 0 and address >= 4:
        mainkey = key[(address & 0x1fff) | 0x1000]
    else:
        mainkey = key[address & 0x1fff]
    key_F = _bit(mainkey, 7) if address & 0x1000 else _bit(mainkey, 6)

    if vector_fetch:
        if address <= 3: gkey3 = 0
        if address <= 2: gkey2 = 0
        if address <= 1: gkey1 = 0
        if address <= 1: key_F = 0

    global_xor0   = 1 ^ _bit(gkey1, 5)
    global_xor1   = 1 ^ _bit(gkey1, 2)
    global_swap2  = 1 ^ _bit(gkey1, 0)
    global_swap0a = 1 ^ _bit(gkey2, 5)
    global_swap0b = 1 ^ _bit(gkey2, 2)
    global_swap3  = 1 ^ _bit(gkey3, 6)
    global_swap1  = 1 ^ _bit(gkey3, 4)
    global_swap4  = 1 ^ _bit(gkey3, 2)
    key_0a = _bit(mainkey, 0) ^ _bit(gkey3, 1)
    key_0b = _bit(mainkey, 0) ^ _bit(gkey1, 7)
    key_0c = _bit(mainkey, 0) ^ _bit(gkey1, 1)
    key_1a = _bit(mainkey, 1) ^ _bit(gkey2, 7)
    key_1b = _bit(mainkey, 1) ^ _bit(gkey1, 3)
    key_2a = _bit(mainkey, 2) ^ _bit(gkey3, 7)
    key_2b = _bit(mainkey, 2) ^ _bit(gkey1, 4)
    key_3a = _bit(mainkey, 3) ^ _bit(gkey2, 0)
    key_3b = _bit(mainkey, 3) ^ _bit(gkey3, 3)
    key_4a = _bit(mainkey, 4) ^ _bit(gkey2, 3)
    key_4b = _bit(mainkey, 4) ^ _bit(gkey3, 0)
    key_5a = _bit(mainkey, 5) ^ _bit(gkey3, 5)
    key_5b = _bit(mainkey, 5) ^ _bit(gkey1, 6)
    key_6a = _bit(mainkey, 6) ^ _bit(gkey2, 1)
    key_6b = _bit(mainkey, 6) ^ _bit(gkey2, 6)
    key_7a = _bit(mainkey, 7) ^ _bit(gkey2, 4)

    if val & 0x8000:
        val = _bitswap16(val, 15, 9, 10, 13, 3, 12, 0, 14, 6, 5, 2, 11, 8, 1, 4, 7)
        if not global_xor1 and not val & 0x0800: val ^= 0x3002
        if not val & 0x0020: val ^= 0x0044
        if not key_1b and not val & 0x0400: val ^= 0x0890
        if not global_swap2 and not key_0c: val ^= 0x0308
        val ^= 0x6561
        if not key_2b: val = _bitswap16(val, 15, 10, 13, 12, 11, 14, 9, 8, 7, 6, 0, 4, 3, 2, 1, 5)
    if val & 0x4000:
        val = _bitswap16(val, 13, 14, 7, 0, 8, 6, 4, 2, 1, 15, 3, 11, 12, 10, 5, 9)
        if not global_xor0 and val & 0x0010: val ^= 0x0468
        if not key_3a and val & 0x0100: val ^= 0x0081
        if not key_6a and val & 0x0004: val ^= 0x0100
        if not key_5b and not key_0b: val ^= 0x3012
        val ^= 0x3523
        if not global_swap0b: val = _bitswap16(val, 2, 14, 13, 12, 9, 10, 11, 8, 7, 6, 5, 4, 3, 15, 1, 0)
    if val & 0x2000:
        val = _bitswap16(val, 10, 2, 13, 7, 8, 0, 3, 14, 6, 15, 1, 11, 9, 4, 5, 12)
        if not key_4a and val & 0x0800: val ^= 0x010c
        if not key_1a and val & 0x0080: val ^= 0x1000
        if not key_7a and val & 0x0400: val ^= 0x0a21
        if not key_4b and not key_0a: val ^= 0x0080
        if not global_swap0a and not key_6b: val ^= 0xc000
        val ^= 0x99a5
        if not key_5b: val = _bitswap16(val, 15, 14, 13, 12, 11, 1, 9, 8, 7, 10, 5, 6, 3, 2, 4, 0)
    if val & 0xe000:
        val = _bitswap16(val, 15, 13, 14, 5, 6, 0, 9, 10, 4, 11, 1, 2, 12, 3, 7, 8)
        val ^= 0x17ff
        if not global_swap4: val = _bitswap16(val, 15, 14, 13, 6, 11, 10, 9, 5, 7, 12, 8, 4, 3, 2, 1, 0)
        if not global_swap3: val = _bitswap16(val, 13, 15, 14, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0)
        if not global_swap2: val = _bitswap16(val, 15, 14, 13, 12, 11, 2, 9, 8, 10, 6, 5, 4, 3, 0, 1, 7)
        if not key_3b: val = _bitswap16(val, 15, 14, 13, 12, 11, 10, 4, 8, 7, 6, 5, 9, 1, 2, 3, 0)
        if not key_2a: val = _bitswap16(val, 13, 14, 15, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0)
        if not global_swap1: val = _bitswap16(val, 15, 14, 13, 12, 9, 8, 11, 10, 7, 6, 5, 4, 3, 2, 1, 0)
        if not key_5a: val = _bitswap16(val, 15, 14, 13, 12, 11, 10, 9, 8, 4, 5, 7, 6, 3, 2, 1, 0)
        if not global_swap0a: val = _bitswap16(val, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 0, 3, 2, 1)
    val = _bitswap16(val, 12, 15, 14, 13, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0)
    if (val & 0xb080) == 0x8000: val ^= 0x4000
    if (val & 0xf000) == 0xc000: val ^= 0x0080
    if (val & 0xb100) == 0x0000: val ^= 0x4000
    if masked(val, key_F):
        val = 0xffff
    return val


def decrypt_rom(rom_words, key, state):
    """Decrypt a whole program ROM (list of 16-bit words) for one state, the
    way MAME's decryption cache does (vector_fetch for words 0..3)."""
    return [decrypt_one(a, w, key, state, a < 4) for a, w in enumerate(rom_words)]
