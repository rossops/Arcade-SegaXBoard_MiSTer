//============================================================================
//  X Board sound section: Z80 (T80s) at 4 MHz, YM2151 (jt51), 315-5218 PCM.
//  Memory: 0000-EFFF ROM (SDRAM p5 through a 1 KB cache), F000-F0FF PCM
//  registers (mirror 0x700), F800-FFFF RAM. Ports: 00-3F YM2151 (A0 = a0),
//  40-7F sound latch from the 315-5250 (read clears the NMI).
//  NMI = latch write, INT = YM2151, reset from I/O chip #1 port C bit 0.
//  Mix: MAME routes PCM at 0.35 and the YM2151 at 0.15 of full scale.
//  Simulation builds (no VHDL) use the tv80 core behind XB_Z80_TV80.
//============================================================================
import xb_pkg::*;

module xb_soundsys #(
    parameter HAS_YM   = 1,                  // 0: rear-speaker board (no YM2151)
    parameter [24:0] ROM_BASE = SDR_Z80_BASE,
    parameter [24:0] PCM_BASE = SDR_PCM_BASE
) (
    input             clk,          // clk_sys
    input             reset,
    input             z80_reset_n,  // I/O chip port C bit 0
    input             ce_z80,       // 4 MHz
    input             ce_z80x2,     // 8 MHz (simulation only: tv80 clock toggle)
    input             ce_fm,        // 4 MHz (jt51 cen)
    input             ce_fm_p1,     // 2 MHz (jt51 cen_p1)
    input             pcm_tick,     // 31.25 kHz
    input             mute_n,
    input       [7:0] pcm_bankmask,

    input       [7:0] snd_latch,
    input             snd_nmi,
    output            snd_read,     // pulse: Z80 read of port 0x40 (clears NMI)

    // SDRAM
    output            zrom_req,  output [24:3] zrom_addr, input [63:0] zrom_dout, input zrom_ack,
    output            pcm_req,   output [24:1] pcm_addr,  input [15:0] pcm_dout,  input pcm_ack,

    output signed [15:0] audio_l,
    output signed [15:0] audio_r
);

wire [15:0] z_addr;
wire  [7:0] z_dout;
reg   [7:0] z_din;
wire        z_mreq_n, z_iorq_n, z_rd_n, z_wr_n, z_m1_n;
wire        ym_irq_n;
wire        z_wait_n;
wire        z_rst_n = ~reset & z80_reset_n;

`ifdef XB_Z80_TV80
// tv80 has no clock enable: derive a 4 MHz clock from the 8 MHz enable
reg zclk;
always @(posedge clk) if (reset) zclk <= 1'b0; else if (ce_z80x2) zclk <= ~zclk;
tv80s z80 (
    .reset_n(z_rst_n), .clk(zclk),
    .wait_n(z_wait_n), .int_n(ym_irq_n), .nmi_n(~snd_nmi), .busrq_n(1'b1),
    .m1_n(z_m1_n), .mreq_n(z_mreq_n), .iorq_n(z_iorq_n), .rd_n(z_rd_n), .wr_n(z_wr_n),
    .rfsh_n(), .halt_n(), .busak_n(),
    .A(z_addr), .di(z_din), .dout(z_dout)
);
`else
T80s z80 (
    .RESET_n (z_rst_n),
    .CLK     (clk),
    .CEN     (ce_z80),
    .WAIT_n  (z_wait_n),
    .INT_n   (ym_irq_n),
    .NMI_n   (~snd_nmi),
    .BUSRQ_n (1'b1),
    .M1_n    (z_m1_n), .MREQ_n(z_mreq_n), .IORQ_n(z_iorq_n), .RD_n(z_rd_n), .WR_n(z_wr_n),
    .RFSH_n  (), .HALT_n(), .BUSAK_n(),
    .OUT0    (1'b0),
    .A       (z_addr), .DI(z_din), .DO(z_dout)
);
`endif

wire mem_rd = ~z_mreq_n & ~z_rd_n;
wire mem_wr = ~z_mreq_n & ~z_wr_n;
wire io_rd  = ~z_iorq_n & ~z_rd_n & z_m1_n;
wire io_wr  = ~z_iorq_n & ~z_wr_n;
wire sel_rom = (z_addr < 16'hF000);
wire sel_pcm = (z_addr[15:11] == 5'b11110);          // F000-F7FF (mirror 0x700)
wire sel_ram = (z_addr[15:11] == 5'b11111);          // F800-FFFF

// ---- ROM: 1 KB cache over SDRAM p5 (4-word bursts); the Z80 waits on a miss
wire [15:0] rom_word;
wire        rom_hit;
wire [15:3] zc_addr;
xb_rom_cache #(.AW(15), .LINES(128)) zcache (
    .clk(clk), .reset(reset), .invalidate(reset),
    .cpu_req(mem_rd && sel_rom), .cpu_addr(z_addr[15:1]),
    .cpu_data(rom_word), .cpu_ack(rom_hit),
    .rom_req(zrom_req), .rom_addr(zc_addr), .rom_data(zrom_dout), .rom_ack(zrom_ack)
);
assign zrom_addr = ROM_BASE[24:3] + {9'd0, zc_addr};
assign z_wait_n  = !(mem_rd && sel_rom && !rom_hit);

// ---- work RAM 2 KB
reg [7:0] ram [0:2047];
reg [7:0] ram_q;
always @(posedge clk) begin
    if (mem_wr && sel_ram) ram[z_addr[10:0]] <= z_dout;
    ram_q <= ram[z_addr[10:0]];
end

// ---- PCM
wire [7:0] pcm_q;
wire signed [15:0] pcm_l, pcm_r;
reg pcm_cs_d;
wire pcm_access = (mem_rd | mem_wr) && sel_pcm;
always @(posedge clk) pcm_cs_d <= pcm_access;
xb_segapcm_5218 #(.PCM_BASE(PCM_BASE)) pcm (
    .clk(clk), .reset(reset), .tick(pcm_tick), .bankmask(pcm_bankmask),
    .cs(pcm_access && !pcm_cs_d), .we(mem_wr), .addr(z_addr[7:0]), .din(z_dout), .dout(pcm_q),
    .rom_req(pcm_req), .rom_addr(pcm_addr), .rom_dout(pcm_dout), .rom_ack(pcm_ack),
    .out_l(pcm_l), .out_r(pcm_r)
);

// ---- YM2151 (ports 00-3F), latch (40-7F)
wire ym_cs = (~z_iorq_n) && z_m1_n && (z_addr[7:6] == 2'b00);
wire [7:0] ym_dout;
wire signed [15:0] ym_l, ym_r;
generate if (HAS_YM) begin : g_ym
jt51 ym (
    .rst(~z_rst_n), .clk(clk), .cen(ce_fm), .cen_p1(ce_fm_p1),
    .cs_n(~ym_cs), .wr_n(z_wr_n), .a0(z_addr[0]), .din(z_dout), .dout(ym_dout),
    .ct1(), .ct2(), .irq_n(ym_irq_n), .sample(),
    .left(), .right(), .xleft(ym_l), .xright(ym_r)
);
end else begin : g_noym
assign ym_dout = 8'hFF; assign ym_irq_n = 1'b1; assign ym_l = 16'sd0; assign ym_r = 16'sd0;
end endgenerate
wire latch_cs = io_rd && (z_addr[7:6] == 2'b01);
reg latch_cs_d;
always @(posedge clk) latch_cs_d <= latch_cs;
assign snd_read = latch_cs && !latch_cs_d;

// ---- read mux
always @* begin
    z_din = 8'hFF;
    if (~z_iorq_n) begin
        if (z_addr[7:6] == 2'b00) z_din = ym_dout;
        else if (z_addr[7:6] == 2'b01) z_din = snd_latch;
    end
    else if (sel_rom) z_din = z_addr[0] ? rom_word[15:8] : rom_word[7:0];
    else if (sel_pcm) z_din = pcm_q;
    else if (sel_ram) z_din = ram_q;
end

// ---- mix: 0.35 * PCM + 0.15 * YM (90/256 and 38/256)
wire signed [23:0] mix_l = pcm_l * 24'sd90 + ym_l * 24'sd38;
wire signed [23:0] mix_r = pcm_r * 24'sd90 + ym_r * 24'sd38;
assign audio_l = mute_n ? mix_l[23:8] : 16'sd0;
assign audio_r = mute_n ? mix_r[23:8] : 16'sd0;
endmodule
