//============================================================================
//  Sega X Board — board top
//  M1: both 68000s (fx68k) with ROM caches, every CPU-visible RAM, the
//  315-5248/5249/5250 chips (one set per CPU), CXD1095 x2, ADC0804, the
//  interrupt logic and the MB3773 watchdog. Main CPU accesses into the sub
//  CPU's address space (0x200000-0x2FFFFF) go through the sub-space arbiter,
//  which stalls the sub CPU for the duration (MacDonald: "the sub CPU is
//  halted while an access occurs").
//  Video chips arrive in M2-M4: for now the display is a test pattern and the
//  video RAMs only exist on the CPU side.
//============================================================================
import xb_pkg::*;

module xb_core (
    input             clk_sys,      // 50 MHz
    input             clk_ram,      // 100 MHz
    input             reset,
    input             pause,
    input board_desc_t board_desc,

    // DDR3 (sprite framebuffers), clk_ram domain
    input             DDRAM_BUSY,
    output      [7:0] DDRAM_BURSTCNT,
    output     [28:0] DDRAM_ADDR,
    input      [63:0] DDRAM_DOUT,
    input             DDRAM_DOUT_READY,
    output            DDRAM_RD,
    output     [63:0] DDRAM_DIN,
    output      [7:0] DDRAM_BE,
    output            DDRAM_WE,

    // SDRAM read ports (clk_ram domain, sdram.sv contract)
    output            p0_req, output [24:3] p0_addr, input  [63:0] p0_dout, input p0_ack,
    output            p1_req, output [24:3] p1_addr, input  [63:0] p1_dout, input p1_ack,
    output            p2_req, output [24:4] p2_addr, input [127:0] p2_dout, input p2_ack,
    output            p3_req, output [24:3] p3_addr, input  [63:0] p3_dout, input p3_ack, output p3_urgent,
    output            p4_req, output [24:4] p4_addr, input [127:0] p4_dout, input p4_ack, output p4_urgent,
    output            p5_req, output [24:3] p5_addr, input  [63:0] p5_dout, input p5_ack,
    output            p6_req, output [24:1] p6_addr, input  [15:0] p6_dout, input p6_ack,

    // tile / road ROM load (from the ioctl loader)
    input             tile_wr,
    input      [17:0] tile_waddr,
    input       [7:0] tile_wdata,
    input             road_wr,
    input      [15:0] road_waddr,
    input       [7:0] road_wdata,

    // inputs (active high)
    input      [15:0] p1_buttons,   // 0 right 1 left 2 down 3 up 4 vulcan 5 missile 6 start 7 coin 8 test 9 service
    input       [7:0] adc_x, adc_y, adc_throttle,
    input       [7:0] dsw_a, dsw_b,
    input             service, test,
    input             coin1, coin2,

    // video
    output      [7:0] r, g, b,
    output            ce_pix, hs, vs, hb, vb,

    // audio
    output signed [15:0] audio_l, audio_r,

    // sim trace
    output     [23:1] trace_main_addr, output trace_main_start, output [2:0] trace_main_fc,
    output     [23:1] trace_sub_addr,  output trace_sub_start,  output [2:0] trace_sub_fc
);

// ---------------------------------------------------------------- clocks
reg [1:0] phase;             // 12.5 MHz = clk_sys/4
reg [5:0] adc_div;
reg       ce_adc;
always @(posedge clk_sys) begin
    if (reset) begin phase <= 2'd0; adc_div <= 6'd0; ce_adc <= 1'b0; end
    else begin
        phase  <= phase + 2'd1;
        ce_adc <= 1'b0;
        if (adc_div == 6'd39) begin adc_div <= 6'd0; ce_adc <= 1'b1; end
        else adc_div <= adc_div + 6'd1;
    end
end
wire ce_cpu = ~pause;

// sound clocks: 4 MHz = 2 pulses per 25 clk_sys (12/13 spacing), 8 MHz = 4
// pulses per 25 (for the simulation Z80 clock), jt51 cen_p1 = 2 MHz,
// PCM tick = 4 MHz / 128
reg [4:0] snd_div;
reg       ce_z80, ce_z80x2, ce_fm_p1, pcm_tick;
reg [6:0] pcm_div;
always @(posedge clk_sys) begin
    if (reset) begin snd_div <= 5'd0; ce_z80 <= 1'b0; ce_z80x2 <= 1'b0; ce_fm_p1 <= 1'b0; pcm_div <= 7'd0; pcm_tick <= 1'b0; end
    else begin
        snd_div  <= (snd_div == 5'd24) ? 5'd0 : snd_div + 5'd1;
        ce_z80   <= (snd_div == 5'd0) || (snd_div == 5'd12);
        ce_z80x2 <= (snd_div == 5'd0) || (snd_div == 5'd6) || (snd_div == 5'd12) || (snd_div == 5'd18);
        ce_fm_p1 <= (snd_div == 5'd0);
        pcm_tick <= 1'b0;
        if (snd_div == 5'd0 || snd_div == 5'd12) begin
            if (pcm_div == 7'd127) begin pcm_div <= 7'd0; pcm_tick <= 1'b1; end
            else pcm_div <= pcm_div + 7'd1;
        end
    end
end

// ---------------------------------------------------------------- timing
wire [8:0] hcnt, vcnt;
wire       v0, line_start, vbl_irq, latch_pulse;
xb_video_timing timing (
    .clk(clk_sys), .reset(reset),
    .ce_pix(ce_pix), .hcnt(hcnt), .vcnt(vcnt),
    .hblank(hb_t), .vblank(vb_t), .hsync(hs_t), .vsync(vs_t),
    .v0(v0), .line_start(line_start), .vbl_irq(vbl_irq), .latch_pulse(latch_pulse)
);

// ---------------------------------------------------------------- watchdog
// MB3773: kicked by I/O chip #1 port C bit 6 and by every vblank (MAME
// update_main_irqs). Fires only if the game stops both; 16 frames.
reg  [4:0] wd_frames;
reg        wd_reset;
reg        vbl_d, pc6_d;
wire [7:0] io0_out_c;
always @(posedge clk_sys) begin
    vbl_d <= vbl_irq; pc6_d <= io0_out_c[6];
    if (reset) begin wd_frames <= 5'd0; wd_reset <= 1'b0; end
    else begin
        wd_reset <= 1'b0;
        if ((vbl_irq && !vbl_d) || (io0_out_c[6] != pc6_d)) wd_frames <= 5'd0;
        else if (line_start && vcnt == 9'd0) begin
            if (wd_frames == 5'd16) begin wd_reset <= 1'b1; wd_frames <= 5'd0; end
            else wd_frames <= wd_frames + 5'd1;
        end
    end
end
wire cpu_reset = reset | wd_reset;

// ================================================================ MAIN CPU
wire [23:1] m_addr;
wire        m_valid, m_start, m_rd, m_wr;
wire  [1:0] m_be;
wire [15:0] m_dout;
reg  [15:0] m_din;
reg         m_ack;
wire        timer_irq;
wire  [2:0] m_ipl = (timer_irq && vbl_irq) ? 3'd6 : vbl_irq ? 3'd4 : timer_irq ? 3'd2 : 3'd0;
wire  [2:0] m_fc;
wire        m_reset_out;     // main 68000 RESET instruction -> sub CPU reset (MAME m68k_reset_callback)

xb_m68k_bus main_cpu (
    .clk(clk_sys), .reset(cpu_reset), .ce_phase(ce_cpu), .phase(phase),
    .ipl(m_ipl), .halt_n(1'b1),
    .bus_addr(m_addr), .bus_valid(m_valid), .bus_start(m_start),
    .bus_rd(m_rd), .bus_wr(m_wr), .bus_be(m_be),
    .bus_dout(m_dout), .bus_din(m_din), .bus_ack(m_ack), .reset_out(m_reset_out), .fc(m_fc)
);
assign trace_main_addr = m_addr; assign trace_main_start = m_start; assign trace_main_fc = m_fc;

// main decode (global mask 0x3FFFFF -> bits 21:1)
wire [21:1] ma = m_addr[21:1];
wire m_sel_rom     = (ma[21:19] == 3'd0);
wire m_sel_bk1     = (ma[21:17] == 5'h04) || (ma[21:14] == 8'hFE);
wire m_sel_bk2     = (ma[21:17] == 5'h05) || (ma[21:14] == 8'hFF);
wire m_sel_tile    = (ma[21:16] == 6'h0C);
wire m_sel_text    = (ma[21:16] == 6'h0D);
wire m_sel_mult    = (ma[21:14] == 8'h38);
wire m_sel_div     = (ma[21:14] == 8'h39);
wire m_sel_cmp     = (ma[21:14] == 8'h3A);
wire m_sel_spr     = (ma[21:16] == 6'h10);
wire m_sel_sprdraw = (ma[21:16] == 6'h11);
wire m_sel_pal     = (ma[21:16] == 6'h12);
wire m_sel_adc     = (ma[21:16] == 6'h13);
wire m_sel_io0     = (ma[21:16] == 6'h14);
wire m_sel_io1     = (ma[21:16] == 6'h15);
wire m_sel_ioctl   = (ma[21:16] == 6'h16);
wire m_sel_sub     = (ma[21:20] == 2'b10);     // 0x200000-0x2FFFFF: sub space
wire m_sel_none    = !(m_sel_rom | m_sel_bk1 | m_sel_bk2 | m_sel_tile | m_sel_text | m_sel_mult |
                       m_sel_div | m_sel_cmp | m_sel_spr | m_sel_sprdraw | m_sel_pal | m_sel_adc |
                       m_sel_io0 | m_sel_io1 | m_sel_ioctl | m_sel_sub);

// one-clock strobes for the chips, and a 1-clk-later ack for BRAM targets
reg m_ram_rdy;
always @(posedge clk_sys) m_ram_rdy <= m_valid && !m_start && !m_ack ? 1'b1 : (m_valid ? m_ram_rdy : 1'b0);
wire m_cs = m_start;   // chips act on the start pulse

// ---- main ROM cache
wire [15:0] m_rom_data; wire m_rom_ack;
wire        m_rom_req; wire [19:3] m_rom_addr;
xb_rom_cache #(.AW(19), .LINES(512)) main_cache (
    .clk(clk_sys), .reset(reset), .invalidate(reset),
    .cpu_req(m_valid && m_rd && m_sel_rom), .cpu_addr(ma[19:1]),
    .cpu_data(m_rom_data), .cpu_ack(m_rom_ack),
    .rom_req(m_rom_req), .rom_addr(m_rom_addr), .rom_data(p0_dout), .rom_ack(p0_ack)
);
assign p0_req  = m_rom_req;
assign p0_addr = SDR_MAIN_BASE[24:3] + {5'd0, m_rom_addr};

// ---- backup RAMs (16K each, main only)
wire [15:0] bk1_q, bk2_q;
xb_dpram #(.AW(13)) backup1 (.clk(clk_sys), .a_addr(ma[13:1]), .a_din(m_dout), .a_be(m_be),
    .a_we(m_valid && m_wr && m_sel_bk1 && m_start), .a_dout(bk1_q), .b_clk(clk_sys), .b_addr(13'd0), .b_dout());
xb_dpram #(.AW(13)) backup2 (.clk(clk_sys), .a_addr(ma[13:1]), .a_din(m_dout), .a_be(m_be),
    .a_we(m_valid && m_wr && m_sel_bk2 && m_start), .a_dout(bk2_q), .b_clk(clk_sys), .b_addr(13'd0), .b_dout());

// ---- video RAMs (CPU side only until M2/M3)
wire [15:0] tile_q, text_q, spr_q, pal_q;
wire [14:0] tm_tile_addr; wire [15:0] tm_tile_q;
wire [10:0] tm_text_addr; wire [15:0] tm_text_q;
xb_dpram #(.AW(15)) tileram (.clk(clk_sys), .a_addr(ma[15:1]), .a_din(m_dout), .a_be(m_be),
    .a_we(m_valid && m_wr && m_sel_tile && m_start), .a_dout(tile_q), .b_clk(clk_sys), .b_addr(tm_tile_addr), .b_dout(tm_tile_q));
xb_dpram #(.AW(11)) textram (.clk(clk_sys), .a_addr(ma[11:1]), .a_din(m_dout), .a_be(m_be),
    .a_we(m_valid && m_wr && m_sel_text && m_start), .a_dout(text_q), .b_clk(clk_sys), .b_addr(tm_text_addr), .b_dout(tm_text_q));
// sprite RAM: two 4K banks, CPU sees spr_bank; a write to 0x110000 swaps
reg spr_bank;
wire [10:0] spr_rd_addr; wire [15:0] spr_rd_q;
reg         spr_draw_tgl;     // toggles on each $110000 write (clk_sys)
xb_dpram #(.AW(12)) spriteram (.clk(clk_sys), .a_addr({spr_bank, ma[11:1]}), .a_din(m_dout), .a_be(m_be),
    .a_we(m_valid && m_wr && m_sel_spr && m_start), .a_dout(spr_q), .b_clk(clk_ram), .b_addr({~spr_bank, spr_rd_addr}), .b_dout(spr_rd_q));
wire [12:0] pal_idx; wire pal_effects;
wire  [7:0] pal_r, pal_g, pal_b;
xb_palette_5242 palette (.clk(clk_sys), .a_addr(ma[13:1]), .a_din(m_dout), .a_be(m_be),
    .a_we(m_valid && m_wr && m_sel_pal && m_start), .a_dout(pal_q),
    .b_addr(pal_idx), .b_effects(pal_effects), .r(pal_r), .g(pal_g), .b(pal_b));
always @(posedge clk_sys) begin
    if (reset) begin spr_bank <= 1'b0; spr_draw_tgl <= 1'b0; end
    else if (m_valid && m_wr && m_sel_sprdraw && m_start) begin spr_bank <= ~spr_bank; spr_draw_tgl <= ~spr_draw_tgl; end
end

// ---- main math / timer chips
wire [15:0] m_mult_q, m_div_q, m_cmp_q;
wire        m_div_rdy;
wire  [7:0] snd_latch; wire snd_nmi;
xb_math_5248 main_mult (.clk(clk_sys), .reset(cpu_reset), .cs(m_cs && m_sel_mult), .we(m_wr),
    .addr(ma[2:1]), .din(m_dout), .be(m_be), .dout(m_mult_q));
xb_math_5249 main_div (.clk(clk_sys), .reset(cpu_reset), .cs(m_cs && m_sel_div), .we(m_wr),
    .addr(ma[4:1]), .din(m_dout), .be(m_be), .dout(m_div_q), .rdy(m_div_rdy));
xb_cmptimer_5250 main_cmp (.clk(clk_sys), .reset(cpu_reset), .cs(m_cs && m_sel_cmp), .we(m_wr),
    .addr(ma[4:1]), .din(m_dout), .be(m_be), .dout(m_cmp_q),
    .exck(v0), .timer_irq(timer_irq),
    .snd_latch(snd_latch), .snd_nmi(snd_nmi), .snd_read(snd_read));
wire snd_read;

// ---- I/O chips (odd byte lane), ADC, /ODEN latch
reg        oden_n;
always @(posedge clk_sys) begin
    if (cpu_reset) oden_n <= 1'b1;
    else if (m_cs && m_wr && m_sel_ioctl && m_be[0]) oden_n <= m_dout[0];
end
wire [7:0] io0_q, io1_q;
wire [7:0] io0_out_d;
wire       adc_intr;
wire [7:0] adc_q;
// IO0 port A: D5-D0 switches (unused, open = 0? MAME: active low unknown -> 1),
// D6 = ADC /INTR (active high), D7 n/c
wire [7:0] io0_in_a = {1'b1, adc_intr, 6'h3F};
wire [7:0] io0_in_b = 8'hFF;    // motor board absent (upright)
// IO1 port A: 0 unused, 1 test, 2 service, 3 start, 4 vulcan, 5 missile, 6 coin1, 7 coin2 (active low)
wire [7:0] io1_in_a = ~{coin2 | p1_buttons[7] & 1'b0, coin1 | p1_buttons[7], p1_buttons[5], p1_buttons[4],
                        p1_buttons[6], service | p1_buttons[9], test | p1_buttons[8], 1'b0};
xb_cxd1095 io0 (.clk(clk_sys), .reset(cpu_reset), .cs(m_cs && m_sel_io0 && m_be[0]), .we(m_wr),
    .addr(ma[3:1]), .din(m_dout[7:0]), .dout(io0_q), .oden_n(oden_n),
    .in_a(io0_in_a), .in_b(io0_in_b), .in_c(8'hFF), .in_d(8'hFF), .in_e(4'hF),
    .out_a(), .out_b(), .out_c(io0_out_c), .out_d(io0_out_d), .out_e(),
    .dir_a(), .dir_b(), .dir_c(), .dir_d());
xb_cxd1095 io1 (.clk(clk_sys), .reset(cpu_reset), .cs(m_cs && m_sel_io1 && m_be[0]), .we(m_wr),
    .addr(ma[3:1]), .din(m_dout[7:0]), .dout(io1_q), .oden_n(oden_n),
    .in_a(io1_in_a), .in_b(8'hFF), .in_c(dsw_a), .in_d(dsw_b), .in_e(4'hF),
    .out_a(), .out_b(), .out_c(), .out_d(), .out_e(),
    .dir_a(), .dir_b(), .dir_c(), .dir_d());
xb_adc0804 adc (.clk(clk_sys), .reset(cpu_reset), .ce_adc(ce_adc),
    .cs(m_cs && m_sel_adc && m_be[0]), .we(m_wr), .dout(adc_q), .intr(adc_intr),
    .channel(io0_out_c[4:2]), .adc_reverse(board_desc.adc_reverse),
    .ch0(adc_x), .ch1(adc_y), .ch2(adc_throttle), .ch3(8'h80), .ch4(8'h80),
    .ch5(8'h10), .ch6(8'h00), .ch7(8'h00));
wire display_enable = io0_out_c[5];   // MAME: set_display_enable(data & 0x20)
wire snd_reset_n    = io0_out_c[0];
wire mute_n         = io0_out_d[7];

// ================================================================ SUB CPU
wire [23:1] s_addr;
wire        s_valid, s_start, s_rd, s_wr;
wire  [1:0] s_be;
wire [15:0] s_dout;
reg  [15:0] s_din;
reg         s_ack;
wire  [2:0] s_ipl = vbl_irq ? 3'd4 : 3'd0;
wire  [2:0] s_fc;

wire sub_reset = cpu_reset | m_reset_out;
xb_m68k_bus sub_cpu (
    .clk(clk_sys), .reset(sub_reset), .ce_phase(ce_cpu), .phase(phase),
    .ipl(s_ipl), .halt_n(1'b1),
    .bus_addr(s_addr), .bus_valid(s_valid), .bus_start(s_start),
    .bus_rd(s_rd), .bus_wr(s_wr), .bus_be(s_be),
    .bus_dout(s_dout), .bus_din(s_din), .bus_ack(s_ack), .reset_out(), .fc(s_fc)
);
assign trace_sub_addr = s_addr; assign trace_sub_start = s_start; assign trace_sub_fc = s_fc;

// ---- sub-space arbiter. Main CPU accesses to 0x200000-0x2FFFFF take the
// sub bus, but only between sub CPU cycles: a sub cycle that has started
// completes first, and a sub cycle that starts while the main holds the bus
// is deferred (its start pulse is replayed after the main releases). The sub
// CPU therefore sees DTACK withheld while the main is on its bus, which is
// the "sub CPU halted" behaviour MacDonald describes.
wire        m_req = m_valid && m_sel_sub;
reg         m_gnt, m_gnt_d, s_gnt, s_pend, s_go;
always @(posedge clk_sys) begin
    if (reset) begin m_gnt <= 1'b0; m_gnt_d <= 1'b0; s_gnt <= 1'b0; s_pend <= 1'b0; s_go <= 1'b0; end
    else begin
        m_gnt_d <= m_gnt;
        s_go    <= 1'b0;
        if (!m_req) m_gnt <= 1'b0;
        else if (!s_gnt && !m_gnt) m_gnt <= 1'b1;
        if (!s_valid) s_gnt <= 1'b0;
        if (s_start) begin
            if (m_gnt || m_req) s_pend <= 1'b1;
            else s_gnt <= 1'b1;
        end
        else if (s_pend && s_valid && !m_gnt && !m_req) begin
            s_pend <= 1'b0; s_gnt <= 1'b1; s_go <= 1'b1;
        end
        else if (!s_valid) s_pend <= 1'b0;
    end
end
// sub cycle is on the bus while granted, or on its uncontested start clock
wire        x_valid = m_gnt ? m_valid
                            : (s_valid && ((s_gnt && !m_gnt) || (!m_req && !m_gnt && !s_pend)));
wire        x_start = m_gnt ? (m_gnt && !m_gnt_d) : ((s_start && !m_req && !m_gnt) || s_go);
wire        x_rd    = m_gnt ? m_rd    : s_rd;
wire        x_wr    = m_gnt ? m_wr    : s_wr;
wire  [1:0] x_be    = m_gnt ? m_be    : s_be;
wire [15:0] x_dout  = m_gnt ? m_dout  : s_dout;
wire [19:1] xa      = m_gnt ? m_addr[19:1] : s_addr[19:1];
wire        x_cs    = x_start;

wire x_sel_rom     = (xa[19] == 1'b0);
wire x_sel_ram0    = (xa[19:17] == 3'd4);
wire x_sel_ram1    = (xa[19:17] == 3'd5);
wire x_sel_mult    = (xa[19:14] == 6'h38);
wire x_sel_div     = (xa[19:14] == 6'h39);
wire x_sel_cmp     = (xa[19:14] == 6'h3A);
wire x_sel_road    = (xa[19:13] == 7'h76);
wire x_sel_roadctl = (xa[19:13] == 7'h77);
wire x_sel_none    = !(x_sel_rom | x_sel_ram0 | x_sel_ram1 | x_sel_mult | x_sel_div | x_sel_cmp |
                       x_sel_road | x_sel_roadctl);

reg x_ram_rdy;
always @(posedge clk_sys) x_ram_rdy <= x_valid && !x_start ? 1'b1 : 1'b0;

// ---- sub ROM cache (also serves main reads of 0x200000-0x27FFFF)
wire [15:0] s_rom_data; wire s_rom_ack;
wire        s_rom_req; wire [19:3] s_rom_addr;
xb_rom_cache #(.AW(19), .LINES(512)) sub_cache (
    .clk(clk_sys), .reset(reset), .invalidate(reset),
    .cpu_req(x_valid && x_rd && x_sel_rom), .cpu_addr(xa[19:1]),
    .cpu_data(s_rom_data), .cpu_ack(s_rom_ack),
    .rom_req(s_rom_req), .rom_addr(s_rom_addr), .rom_data(p1_dout), .rom_ack(p1_ack)
);
assign p1_req  = s_rom_req;
assign p1_addr = SDR_SUB_BASE[24:3] + {5'd0, s_rom_addr};

// ---- shared RAMs, road RAM (two 4K banks, swapped on a control read)
wire [15:0] ram0_q, ram1_q, road_q;
reg         road_bank;
reg   [2:0] road_control;
xb_dpram #(.AW(13)) subram0 (.clk(clk_sys), .a_addr(xa[13:1]), .a_din(x_dout), .a_be(x_be),
    .a_we(x_valid && x_wr && x_sel_ram0 && x_start), .a_dout(ram0_q), .b_clk(clk_sys), .b_addr(13'd0), .b_dout());
xb_dpram #(.AW(13)) subram1 (.clk(clk_sys), .a_addr(xa[13:1]), .a_din(x_dout), .a_be(x_be),
    .a_we(x_valid && x_wr && x_sel_ram1 && x_start), .a_dout(ram1_q), .b_clk(clk_sys), .b_addr(13'd0), .b_dout());
wire [10:0] road_rd_addr; wire [15:0] road_rd_q;
xb_dpram #(.AW(12)) roadram (.clk(clk_sys), .a_addr({road_bank, xa[11:1]}), .a_din(x_dout), .a_be(x_be),
    .a_we(x_valid && x_wr && x_sel_road && x_start), .a_dout(road_q), .b_clk(clk_sys),
    .b_addr({~road_bank, road_rd_addr}), .b_dout(road_rd_q));
always @(posedge clk_sys) begin
    if (reset) begin road_bank <= 1'b0; road_control <= 3'd0; end
    else if (x_cs && x_sel_roadctl) begin
        if (x_rd) road_bank <= ~road_bank;
        else if (x_be[0]) road_control <= x_dout[2:0];
    end
end

// ---- sub math / compare chips (no timer or sound outputs connected)
wire [15:0] x_mult_q, x_div_q, x_cmp_q;
wire        x_div_rdy;
xb_math_5248 sub_mult (.clk(clk_sys), .reset(cpu_reset), .cs(x_cs && x_sel_mult), .we(x_wr),
    .addr(xa[2:1]), .din(x_dout), .be(x_be), .dout(x_mult_q));
xb_math_5249 sub_div (.clk(clk_sys), .reset(cpu_reset), .cs(x_cs && x_sel_div), .we(x_wr),
    .addr(xa[4:1]), .din(x_dout), .be(x_be), .dout(x_div_q), .rdy(x_div_rdy));
xb_cmptimer_5250 sub_cmp (.clk(clk_sys), .reset(cpu_reset), .cs(x_cs && x_sel_cmp), .we(x_wr),
    .addr(xa[4:1]), .din(x_dout), .be(x_be), .dout(x_cmp_q),
    .exck(1'b0), .timer_irq(), .snd_latch(), .snd_nmi(), .snd_read(1'b0));

// ---- sub-space read mux and ack
reg [15:0] x_din;
reg        x_ack;
always @* begin
    x_din = 16'hFFFF;
    x_ack = 1'b0;
    if (x_sel_rom)          begin x_din = s_rom_data; x_ack = s_rom_ack; end
    else if (x_sel_ram0)    begin x_din = ram0_q;     x_ack = x_ram_rdy; end
    else if (x_sel_ram1)    begin x_din = ram1_q;     x_ack = x_ram_rdy; end
    else if (x_sel_road)    begin x_din = road_q;     x_ack = x_ram_rdy; end
    else if (x_sel_mult)    begin x_din = x_mult_q;   x_ack = x_ram_rdy; end
    else if (x_sel_div)     begin x_din = x_div_q;    x_ack = x_ram_rdy && x_div_rdy; end
    else if (x_sel_cmp)     begin x_din = x_cmp_q;    x_ack = x_ram_rdy; end
    else                    begin x_din = 16'hFFFF;   x_ack = x_ram_rdy; end   // road ctl, unmapped
end

always @* begin
    s_din = x_din;
    s_ack = s_gnt && !m_gnt && x_ack;
end

// ---- main read mux and ack
always @* begin
    m_din = 16'hFFFF;
    m_ack = 1'b0;
    if (m_sel_rom)          begin m_din = m_rom_data; m_ack = m_rom_ack; end
    else if (m_sel_sub)     begin m_din = x_din;      m_ack = m_gnt && x_ack; end
    else if (m_sel_bk1)     begin m_din = bk1_q;      m_ack = m_ram_rdy; end
    else if (m_sel_bk2)     begin m_din = bk2_q;      m_ack = m_ram_rdy; end
    else if (m_sel_tile)    begin m_din = tile_q;     m_ack = m_ram_rdy; end
    else if (m_sel_text)    begin m_din = text_q;     m_ack = m_ram_rdy; end
    else if (m_sel_spr)     begin m_din = spr_q;      m_ack = m_ram_rdy; end
    else if (m_sel_pal)     begin m_din = pal_q;      m_ack = m_ram_rdy; end
    else if (m_sel_mult)    begin m_din = m_mult_q;   m_ack = m_ram_rdy; end
    else if (m_sel_div)     begin m_din = m_div_q;    m_ack = m_ram_rdy && m_div_rdy; end
    else if (m_sel_cmp)     begin m_din = m_cmp_q;    m_ack = m_ram_rdy; end
    else if (m_sel_adc)     begin m_din = {8'hFF, adc_q}; m_ack = m_ram_rdy; end
    else if (m_sel_io0)     begin m_din = {8'hFF, io0_q}; m_ack = m_ram_rdy; end
    else if (m_sel_io1)     begin m_din = {8'hFF, io1_q}; m_ack = m_ram_rdy; end
    else                    begin m_din = 16'hFFFF;   m_ack = m_ram_rdy; end   // sprdraw, ioctl, unmapped
end

// ---------------------------------------------------------------- video
wire [15:0] rom_addr_tm; wire [7:0] tp0, tp1, tp2;
xb_tilerom tilerom (.clk(clk_sys), .wr(tile_wr), .wr_addr(tile_waddr), .wr_data(tile_wdata),
    .rd_addr(rom_addr_tm), .plane0(tp0), .plane1(tp1), .plane2(tp2));

wire [10:0] fg_pix, bg_pix; wire [6:0] tx_pix;
xb_tilemap_5197 tilemap (
    .clk(clk_sys), .reset(reset),
    .line_start(line_start), .vcnt(vcnt), .latch_pulse(latch_pulse), .ce_pix(ce_pix), .hcnt(hcnt),
    .tile_addr(tm_tile_addr), .tile_q(tm_tile_q), .text_addr(tm_text_addr), .text_q(tm_text_q),
    .rom_addr(rom_addr_tm), .rom_p0(tp0), .rom_p1(tp1), .rom_p2(tp2),
    .fg_pix(fg_pix), .bg_pix(bg_pix), .tx_pix(tx_pix)
);

// ---------------------------------------------------------------- sprites
// The renderer and the framebuffer interface run in clk_ram; timing pulses
// and the $110000 toggle cross from clk_sys through 2-flop synchronisers.
reg [1:0] r_vbl_s, r_line_s, r_draw_s;
reg [8:0] r_vcnt_a, r_vcnt_b;
reg       r_vbl_d, r_line_d, r_draw_d;
always @(posedge clk_ram) begin
    r_vbl_s  <= {r_vbl_s[0],  vbl_irq};
    r_line_s <= {r_line_s[0], line_start_lvl};
    r_draw_s <= {r_draw_s[0], spr_draw_tgl};
    r_vcnt_a <= vcnt; r_vcnt_b <= r_vcnt_a;
    r_vbl_d <= r_vbl_s[1]; r_line_d <= r_line_s[1]; r_draw_d <= r_draw_s[1];
end
wire r_vbl_start  = r_vbl_s[1] & ~r_vbl_d;
wire r_line_start = r_line_s[1] & ~r_line_d;
wire r_draw_req   = r_draw_s[1] ^ r_draw_d;
// line_start as a level that toggles half a line (clean edge for the CDC)
reg line_start_lvl;
always @(posedge clk_sys) if (line_start) line_start_lvl <= 1'b1; else if (ce_pix && hcnt == 9'd200) line_start_lvl <= 1'b0;

wire        fbw_start, fbw_valid, fbw_end, fbw_busy;
wire        fbe_req, fbe_ack, fbr_req, fbr_ack;
wire  [1:0] fbw_buf, fbe_buf, fbr_buf;
wire  [8:0] fbw_x;
wire  [7:0] fbw_y, fbe_y, fbr_y;
wire [15:0] fbw_pix, fbr_pix;
wire        spr_disp_buf;
xb_sprite_5211 sprites (
    .clk(clk_ram), .reset(reset), .num_banks(board_desc.sprite_banks),
    .start_req(r_draw_req), .vbl_start(r_vbl_start), .vcnt(r_vcnt_b), .line_start(r_line_start),
    .sram_addr(spr_rd_addr), .sram_q(spr_rd_q),
    .rom_req(p2_req), .rom_addr(p2_addr), .rom_dout(p2_dout), .rom_ack(p2_ack),
    .fb_wr_start(fbw_start), .fb_wr_buf(fbw_buf), .fb_wr_x(fbw_x), .fb_wr_y(fbw_y),
    .fb_wr_valid(fbw_valid), .fb_wr_pix(fbw_pix), .fb_wr_end(fbw_end), .fb_wr_busy(fbw_busy),
    .fb_er_req(fbe_req), .fb_er_buf(fbe_buf), .fb_er_y(fbe_y), .fb_er_ack(fbe_ack),
    .fb_rd_req(fbr_req), .fb_rd_buf(fbr_buf), .fb_rd_y(fbr_y), .fb_rd_ack(fbr_ack),
    .disp_buf(spr_disp_buf)
);
// scanout: framebuffer x = screen x + 190; read one pixel ahead of the mixer
wire [8:0] fbr_x = hcnt + 9'd190;
xb_fb_if #(.FB_BASE(32'h3000_0000)) fb (
    .clk(clk_ram), .rst(reset),
    .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
    .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
    .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
    .wr_start(fbw_start), .wr_buf(fbw_buf), .wr_x(fbw_x), .wr_y(fbw_y),
    .wr_valid(fbw_valid), .wr_pix(fbw_pix), .wr_end(fbw_end), .wr_shadow(1'b0), .wr_busy(fbw_busy),
    .er_req(fbe_req), .er_buf(fbe_buf), .er_y(fbe_y), .er_ack(fbe_ack),
    .rd_req(fbr_req), .rd_buf(fbr_buf), .rd_y(fbr_y), .rd_ack(fbr_ack),
    .rd_x(fbr_x), .rd_pix(fbr_pix)
);
// sample the sprite pixel with the tile pixels (one clk after ce_pix)
reg [15:0] spr_pix_r;
always @(posedge clk_sys) if (ce_pix) spr_pix_r <= fbr_pix;
wire spr_v = (spr_pix_r != 16'hFFFF);

// ---------------------------------------------------------------- road
wire [15:0] road_rom_a0, road_rom_a1; wire [7:0] road_rom_q0, road_rom_q1;
xb_roadrom roadrom (.clk(clk_sys), .wr(road_wr), .wr_addr(road_waddr), .wr_data(road_wdata),
    .rd_addr0(road_rom_a0), .rd_addr1(road_rom_a1), .rd_q0(road_rom_q0), .rd_q1(road_rom_q1));
wire        road_bg_v, road_fg_v; wire [12:0] road_bg_idx, road_fg_idx;
xb_road_5275 road (
    .clk(clk_sys), .reset(reset), .line_start(line_start), .vcnt(vcnt), .ce_pix(ce_pix), .hcnt(hcnt),
    .control(road_control),
    .ram_addr(road_rd_addr), .ram_q(road_rd_q),
    .rom_addr0(road_rom_a0), .rom_addr1(road_rom_a1), .rom_q0(road_rom_q0), .rom_q1(road_rom_q1),
    .bg_v(road_bg_v), .bg_idx(road_bg_idx), .fg_v(road_fg_v), .fg_idx(road_fg_idx)
);

// pixel pipeline: line buffer read (1) -> mixer (1, at ce_pix) -> palette (2).
// The blanking/sync signals are delayed one pixel so the framework samples
// the RGB of the same pixel.
reg ce_pix_d1, ce_pix_d2;
always @(posedge clk_sys) begin ce_pix_d1 <= ce_pix; ce_pix_d2 <= ce_pix_d1; end
xb_mixer mixer (
    .clk(clk_sys), .ce_pix(ce_pix_d1), .road_priority(board_desc.road_priority),
    .fg_pix(fg_pix), .bg_pix(bg_pix), .tx_pix(tx_pix),
    .road_bg_v(road_bg_v), .road_bg_idx(road_bg_idx), .road_fg_v(road_fg_v), .road_fg_idx(road_fg_idx),
    .spr_v(spr_v), .spr_pix(spr_pix_r),
    .pal_idx(pal_idx), .pal_effects(pal_effects)
);
reg hb_d, vb_d2, hs_d, vs_d;
wire hb_t, vb_t, hs_t, vs_t;
always @(posedge clk_sys) if (ce_pix) begin hb_d <= hb_t; vb_d2 <= vb_t; hs_d <= hs_t; vs_d <= vs_t; end
assign hb = hb_d; assign vb = vb_d2; assign hs = hs_d; assign vs = vs_d;
assign r = (hb | vb | !display_enable) ? 8'd0 : pal_r;
assign g = (hb | vb | !display_enable) ? 8'd0 : pal_g;
assign b = (hb | vb | !display_enable) ? 8'd0 : pal_b;

// ---------------------------------------------------------------- sound
xb_soundsys sound (
    .clk(clk_sys), .reset(reset), .z80_reset_n(snd_reset_n),
    .ce_z80(ce_z80), .ce_z80x2(ce_z80x2), .ce_fm(ce_z80), .ce_fm_p1(ce_fm_p1), .pcm_tick(pcm_tick),
    .mute_n(mute_n), .pcm_bankmask(board_desc.pcm_bankmask),
    .snd_latch(snd_latch), .snd_nmi(snd_nmi), .snd_read(snd_read),
    .zrom_req(p5_req), .zrom_addr(p5_addr), .zrom_dout(p5_dout), .zrom_ack(p5_ack),
    .pcm_req(p6_req), .pcm_addr(p6_addr), .pcm_dout(p6_dout), .pcm_ack(p6_ack),
    .audio_l(audio_l), .audio_r(audio_r)
);

assign p3_req = 1'b0; assign p3_addr = '0; assign p3_urgent = 1'b0;
assign p4_req = 1'b0; assign p4_addr = '0; assign p4_urgent = 1'b0;

endmodule
