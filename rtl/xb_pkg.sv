//============================================================================
//  Sega X Board for MiSTer — shared package
//  Board constants, SDRAM/DDR3 map, ioctl stream layout and the per-game
//  descriptor that the MRA prepends to the ROM stream (docs/DESIGN.md).
//============================================================================
package xb_pkg;

    // ---- board clocks (Hz) -------------------------------------------------
    localparam int PCB_MASTER_HZ = 50_000_000;   // 68000 x2 = /4, pixel = /8
    localparam int PCB_SOUND_HZ  = 16_000_000;   // Z80 / YM2151 = /4, 315-5218
    localparam int CLK_SYS_HZ    = 50_000_000;   // == PCB_MASTER_HZ (exact)
    localparam int CLK_RAM_HZ    = 100_000_000;

    // ---- video timing (MAME: MASTER_CLOCK/8, 400, 0, 320, 262, 0, 224) -----
    localparam int H_TOTAL   = 400;
    localparam int H_ACTIVE  = 320;
    localparam int V_TOTAL   = 262;
    localparam int V_ACTIVE  = 224;
    localparam int VBLANK_LINE = 223;   // IRQ4 asserted at start of this line
    localparam int LATCH_LINE  = 261;   // 315-5197 latches its registers here

    // ---- SDRAM byte map (25-bit byte address, 32 MB) -----------------------
    localparam [24:0] SDR_MAIN_BASE    = 25'h000_0000;  // 512 KB slot
    localparam [24:0] SDR_SUB_BASE     = 25'h008_0000;  // 512 KB slot
    localparam [24:0] SDR_Z80_BASE     = 25'h010_0000;  //  64 KB slot
    localparam [24:0] SDR_ROAD_BASE    = 25'h011_0000;  //  64 KB slot
    localparam [24:0] SDR_PCM_BASE     = 25'h012_0000;  // 512 KB slot
    localparam [24:0] SDR_SPRITE_BASE  = 25'h020_0000;  //   4 MB slot
    localparam [24:0] SDR_TILE_BASE    = 25'h060_0000;  // 256 KB slot
    localparam [24:0] SDR_Z80B_BASE    = 25'h064_0000;  //  64 KB slot (SMGP rear-speaker Z80)
    localparam [24:0] SDR_PCM2_BASE    = 25'h065_0000;  // 512 KB slot (SMGP second 315-5218)
    localparam [24:0] SDR_END          = 25'h06D_0000;

    // ---- ioctl index-0 stream layout (byte offsets; every region padded) ---
    localparam [26:0] OFF_DESC   = 27'h000_0000;   // 64-byte descriptor
    localparam [26:0] OFF_MAIN   = 27'h000_0040;
    localparam [26:0] OFF_SUB    = OFF_MAIN   + 27'h08_0000;
    localparam [26:0] OFF_Z80    = OFF_SUB    + 27'h08_0000;
    localparam [26:0] OFF_ROAD   = OFF_Z80    + 27'h01_0000;
    localparam [26:0] OFF_PCM    = OFF_ROAD   + 27'h01_0000;
    localparam [26:0] OFF_SPRITE = OFF_PCM    + 27'h08_0000;
    localparam [26:0] OFF_TILE   = OFF_SPRITE + 27'h40_0000;
    localparam [26:0] OFF_Z80B   = OFF_TILE   + 27'h04_0000;
    localparam [26:0] OFF_PCM2   = OFF_Z80B   + 27'h01_0000;
    localparam [26:0] OFF_END    = OFF_PCM2   + 27'h08_0000;

    // ---- DDR3 framebuffers (sprite generator 315-5211A) --------------------
    // Two 512x256x16-bit buffers, 256 KB each.
    localparam [28:0] DDR_FB0_BASE = 29'h0600_0000;  // 0x3000_0000 >> 3, in 64-bit units
    localparam [28:0] DDR_FB1_BASE = 29'h0600_8000;  // 0x3004_0000 >> 3

    // ---- per-game descriptor (first 64 bytes of the stream) ----------------
    //  byte 0: game id (0 = aburner2, 1 = aburner, 2 = thndrbld, ...)
    //  byte 1: flags: bit0 road_priority (0: road fg under tiles, 1: over)
    //                 bit1 thndrbld sprite-RAM wipe hack
    //                 bit2 has throttle lever analog channel
    //                 bit3 second sound board (Z80 + 315-5218, SMGP deluxe)
    //                 bit4 I/O chip 0 port A bits 5:0 read 0 (SMGP motor) instead of 1
    //  byte 2: sprite ROM bank count (aburner2 = 8 x 256 KB)
    //  byte 3: ADC reverse mask (bit n: channel n = 255 - value)
    //  byte 4: PCM ROM bank mask (315-5218 bankmask, aburner2 = 0x70)
    //  byte 5: bits 1:0 analog mode (0: After Burner ranges, throttle on ADC2;
    //          1: full range, throttle on ADC1 and stick Y on ADC2 - Thunder Blade;
    //          2: driving - steering ADC0, gas ADC1, brake ADC2 - Super Monaco GP)
    //  bytes 6..63: reserved (0)
    typedef struct packed {
        logic [7:0] game_id;
        logic       road_priority;
        logic       thndrbld_hack;
        logic       has_throttle;
        logic [7:0] sprite_banks;
        logic [7:0] adc_reverse;
        logic [7:0] pcm_bankmask;
        logic [1:0] ana_mode;
        logic       has_snd2;
        logic       motor_zero;
    } board_desc_t;

endpackage
