"""ROM set table for the Sega X Board core.

One entry per supported MAME set, copied from the ROM_START blocks in
src/mame/sega/segaxbd.cpp. `regions` lists (region, loader, [(file, size, crc)])
in stream order; the loader tells pack_roms/gen_mra how the files interleave:

  'w16'  : pairs of ROMs, LOAD16_BYTE even/odd -> one 16-bit big-endian word
  'x32'  : groups of four ROMs, LOAD32_BYTE -> one 32-bit little-endian dword
  'flat' : ROMs concatenated

Stream/SDRAM slot sizes must match rtl/xb_pkg.sv.
"""

SLOT = {
    "main":   0x080000,
    "sub":    0x080000,
    "z80":    0x010000,
    "road":   0x010000,
    "pcm":    0x080000,
    "sprite": 0x400000,
    "tile":   0x040000,
}
ORDER = ["main", "sub", "z80", "road", "pcm", "sprite", "tile"]
DESC_SIZE = 64

ROMSETS = {
    "aburner2": {
        "name": "After Burner II",
        "year": "1987",
        "zip": "aburner2",
        "game_id": 0,
        "road_priority": 0,
        "thndrbld_hack": 0,
        "has_throttle": 1,
        "sprite_banks": 8,
        "adc_reverse": 0x00,
        "pcm_bankmask": 0x70,
        "regions": {
            "main": ("w16", [
                ("epr-11107.58", 0x20000, "6d87bab7"),
                ("epr-11108.63", 0x20000, "202a3e1d"),
            ]),
            "sub": ("w16", [
                ("epr-11109.20", 0x20000, "85a0fe07"),
                ("epr-11110.29", 0x20000, "f3d6797c"),
            ]),
            "tile": ("flat", [
                ("epr-11115.154", 0x10000, "e8e32921"),
                ("epr-11114.153", 0x10000, "2e97f633"),
                ("epr-11113.152", 0x10000, "36058c8c"),
            ]),
            "sprite": ("x32", [
                ("mpr-10932.90",  0x20000, "cc0821d6"),
                ("mpr-10934.94",  0x20000, "4a51b1fa"),
                ("mpr-10936.98",  0x20000, "ada70d64"),
                ("mpr-10938.102", 0x20000, "e7675baf"),
                ("mpr-10933.91",  0x20000, "c8efb2c3"),
                ("mpr-10935.95",  0x20000, "c1e23521"),
                ("mpr-10937.99",  0x20000, "f0199658"),
                ("mpr-10939.103", 0x20000, "a0d49480"),
                ("epr-11103.92",  0x20000, "bdd60da2"),
                ("epr-11104.96",  0x20000, "06a35fce"),
                ("epr-11105.100", 0x20000, "027b0689"),
                ("epr-11106.104", 0x20000, "9e1fec09"),
                ("epr-11116.93",  0x20000, "49b4c1ba"),
                ("epr-11117.97",  0x20000, "821fbb71"),
                ("epr-11118.101", 0x20000, "8f38540b"),
                ("epr-11119.105", 0x20000, "d0343a8e"),
            ]),
            "road": ("flat", [
                ("epr-10922.40", 0x10000, "b49183d4"),
            ]),
            "z80": ("flat", [
                ("epr-11112.17", 0x10000, "d777fc6d"),
            ]),
            "pcm": ("flat", [
                ("mpr-10931.11", 0x20000, "9209068f"),
                ("mpr-10930.12", 0x20000, "6493368b"),
                ("epr-11102.13", 0x20000, "6c07c78d"),
            ]),
        },
    },
}
