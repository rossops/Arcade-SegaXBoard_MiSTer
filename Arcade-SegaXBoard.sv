//============================================================================
//  Arcade: Sega X Board (After Burner II) for MiSTer  (emu top)
//  Framework integration only; the board lives in rtl/xb_core.sv.
//============================================================================

module emu
(
    input         CLK_50M,
    input         RESET,
    inout  [45:0] HPS_BUS,

    output        CLK_VIDEO,
    output        CE_PIXEL,
    output [12:0] VIDEO_ARX,
    output [12:0] VIDEO_ARY,

    output  [7:0] VGA_R,
    output  [7:0] VGA_G,
    output  [7:0] VGA_B,
    output        VGA_HS,
    output        VGA_VS,
    output        VGA_DE,
    output        VGA_F1,
    output  [1:0] VGA_SL,
    output        VGA_SCALER,
    output        VGA_DISABLE,

    input  [11:0] HDMI_WIDTH,
    input  [11:0] HDMI_HEIGHT,
    output        HDMI_FREEZE,
    output        HDMI_BLACKOUT,
    output        HDMI_BOB_DEINT,

    output        LED_USER,
    output  [1:0] LED_POWER,
    output  [1:0] LED_DISK,

    output  [1:0] BUTTONS,

    output [15:0] AUDIO_L,
    output [15:0] AUDIO_R,
    output        AUDIO_S,
    output  [1:0] AUDIO_MIX,

    // DDR3
    output        DDRAM_CLK,
    input         DDRAM_BUSY,
    output  [7:0] DDRAM_BURSTCNT,
    output [28:0] DDRAM_ADDR,
    input  [63:0] DDRAM_DOUT,
    input         DDRAM_DOUT_READY,
    output        DDRAM_RD,
    output [63:0] DDRAM_DIN,
    output  [7:0] DDRAM_BE,
    output        DDRAM_WE,

    // SDRAM
    output        SDRAM_CLK,
    output        SDRAM_CKE,
    output [12:0] SDRAM_A,
    output  [1:0] SDRAM_BA,
    inout  [15:0] SDRAM_DQ,
    output        SDRAM_DQML,
    output        SDRAM_DQMH,
    output        SDRAM_nCS,
    output        SDRAM_nCAS,
    output        SDRAM_nRAS,
    output        SDRAM_nWE,

    input         CLK_AUDIO,   // 24.576 MHz
    inout   [3:0] ADC_BUS,

    // SD-SPI
    output        SD_SCK,
    output        SD_MOSI,
    input         SD_MISO,
    output        SD_CS,
    input         SD_CD,

    input         UART_CTS,
    output        UART_RTS,
    input         UART_RXD,
    output        UART_TXD,
    output        UART_DTR,
    input         UART_DSR,

    input   [6:0] USER_IN,
    output  [6:0] USER_OUT,

    input         OSD_STATUS
);

import xb_pkg::*;

// unused framework peripherals
assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;
assign AUDIO_S = 1;
assign AUDIO_MIX = 0;
assign LED_POWER = 0;
assign LED_DISK = 0;
assign BUTTONS = 0;

// DDR3: the two sprite framebuffers (xb_fb_if inside the core)
assign DDRAM_CLK = clk_ram;

//////////////////////////////////   CONF   ///////////////////////////////////
`ifndef BUILD_DATE
`define BUILD_DATE "SegaXB"
`endif
`ifndef BUILD_GIT
`define BUILD_GIT "nogit"
`endif

localparam CONF_STR = {
    "SXB;;",
    "-;",
    "O[2:1],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
    "O[5:3],Scandoubler Fx,None,CRT 25%,CRT 50%,CRT 75%;",
    "O[7],Service Mode,Off,On;",
    "O[9:8],Stick,Analog,D-Pad,Analog+D-Pad;",
    "O[10],Pause when OSD open,Off,On;",
    "O[11],Rear speakers (SMGP),On,Off;",
    "-;",
    "DIP;",
    "-;",
    "R[0],Reset;",
    "J1,Vulcan,Missile,Start,Coin,Test,Service,Pause,Gas,Brake;",
    "V,v",`BUILD_DATE,"-",`BUILD_GIT
};

////////////////////////////   CLOCKS/PLL   ///////////////////////////////////
wire clk_sys, clk_ram, clk_snd_unused, pll_locked;
wire sdram_ready;
reg  sdram_ready_meta, sdram_ready_sys;
pll pll (
    .refclk_clk(CLK_50M),
    .reset_reset(1'b0),
    .outclk0_clk(clk_ram),          // 100 MHz
    .outclk1_clk(clk_sys),          // 50 MHz
    .outclk2_clk(SDRAM_CLK),        // 100 MHz, 180 deg
    .outclk3_clk(clk_snd_unused),   // 16 MHz, reserved
    .locked_export(pll_locked)
);

wire        rom_loaded;
wire  [1:0] buttons;
wire [63:0] status;
wire        ioctl_download, ioctl_upload, ioctl_wr, ioctl_rd, ioctl_wait;
wire [15:0] ioctl_index;
wire [26:0] ioctl_addr;
wire [15:0] ioctl_dout, ioctl_din;
wire [31:0] joystick_0, joystick_1;
wire [15:0] joystick_l_analog_0;
wire [15:0] joystick_r_analog_0;
wire [15:0] joystick_l_analog_1, joystick_r_analog_1;
wire  [7:0] paddle_0;

wire video_reset = RESET | status[0] | buttons[1] | ~pll_locked;
wire reset = video_reset | ioctl_download | ~rom_loaded | ~sdram_ready_sys;

always @(posedge clk_sys) begin
    if (!pll_locked) begin
        sdram_ready_meta <= 1'b0;
        sdram_ready_sys  <= 1'b0;
    end
    else begin
        sdram_ready_meta <= sdram_ready;
        sdram_ready_sys  <= sdram_ready_meta;
    end
end

assign LED_USER = ~rom_loaded;

///////////////////////////////   HPS IO   ////////////////////////////////////
hps_io #(.CONF_STR(CONF_STR), .WIDE(1)) hps_io (
    .clk_sys(clk_sys),
    .HPS_BUS(HPS_BUS),

    .buttons(buttons),
    .status(status),
    .status_menumask(16'd0),

    .ioctl_download(ioctl_download),
    .ioctl_upload(ioctl_upload),
    .ioctl_upload_req(nv_modified),
    .ioctl_upload_index(8'd3),
    .ioctl_wr(ioctl_wr),
    .ioctl_rd(ioctl_rd),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .ioctl_din(ioctl_din),
    .ioctl_index(ioctl_index),
    .ioctl_wait(ioctl_wait),

    .joystick_0(joystick_0),
    .joystick_1(joystick_1),
    .joystick_l_analog_0(joystick_l_analog_0),
    .joystick_r_analog_0(joystick_r_analog_0),
    .joystick_l_analog_1(joystick_l_analog_1),
    .joystick_r_analog_1(joystick_r_analog_1),
    .paddle_0(paddle_0)
);
// DIP switches arrive from the MRA <switches> block as ioctl index 254:
// byte 0 = SWA (coinage), byte 1 = SWB (cabinet/lives/difficulty)
reg [7:0] dsw_a = 8'hFF, dsw_b = 8'hDD;
always @(posedge clk_sys) begin
    if (ioctl_download && ioctl_wr && ioctl_index == 16'd254 && ioctl_addr == 27'd0) begin
        dsw_a <= ioctl_dout[7:0];
        dsw_b <= ioctl_dout[15:8];
    end
end

// NVRAM (backup RAM, 32 KB) as ioctl index 3: download at load, upload on
// request; the core asserts nv_modified when the game writes the RAM.
wire        nv_modified;
wire        nv_download = ioctl_download && (ioctl_index[7:0] == 8'd3);
wire        nv_upload   = ioctl_upload   && (ioctl_index[7:0] == 8'd3);

////////////////////////////   ROM LOADING   //////////////////////////////////
wire        sw_req, sw_ack;
wire [24:1] sw_addr;
wire [15:0] sw_din;
wire  [1:0] sw_be;
board_desc_t board_desc;
wire        tile_wr; wire [17:0] tile_waddr; wire [7:0] tile_wdata;
wire        road_wr; wire [15:0] road_waddr; wire [7:0] road_wdata;
wire        key_wr;  wire [12:0] key_waddr;  wire [7:0] key_wdata;

xb_rom_loader loader (
    .clk(clk_sys), .rst(~pll_locked),
    .mem_ready(sdram_ready_sys),
    .ioctl_download(ioctl_download), .ioctl_index(ioctl_index[7:0]),
    .ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
    .ioctl_wait(ioctl_wait),
    .board_desc(board_desc),
    .sdr_wr_req(sw_req), .sdr_wr_addr(sw_addr), .sdr_wr_din(sw_din),
    .sdr_wr_be(sw_be), .sdr_wr_ack(sw_ack),
    .tile_wr(tile_wr), .tile_waddr(tile_waddr), .tile_wdata(tile_wdata),
    .road_wr(road_wr), .road_waddr(road_waddr), .road_wdata(road_wdata),
    .key_wr(key_wr), .key_waddr(key_waddr), .key_wdata(key_wdata),
    .rom_loaded(rom_loaded)
);

/////////////////////////////////   SDRAM   ///////////////////////////////////
wire        p0_req, p0_ack, p1_req, p1_ack, p2_req, p2_ack, p3_req, p3_ack;
wire        p4_req, p4_ack, p5_req, p5_ack, p6_req, p6_ack, p3_urgent, p4_urgent;
wire [24:3] p0_addr, p1_addr, p3_addr, p5_addr;
wire [24:4] p2_addr, p4_addr;
wire [24:1] p6_addr;
wire [63:0] p0_dout, p1_dout, p3_dout, p5_dout;
wire[127:0] p2_dout, p4_dout;
wire [15:0] p6_dout;

sdram sdram (
    .clk(clk_ram), .init(~pll_locked), .ready(sdram_ready),
    .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA),
    .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
    .SDRAM_nCS(SDRAM_nCS), .SDRAM_nCAS(SDRAM_nCAS),
    .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_CKE(SDRAM_CKE),
    .wr_req(sw_req), .wr_addr(sw_addr), .wr_din(sw_din), .wr_be(sw_be), .wr_ack(sw_ack),
    .p0_req(p0_req), .p0_addr(p0_addr), .p0_dout(p0_dout), .p0_ack(p0_ack),
    .p1_req(p1_req), .p1_addr(p1_addr), .p1_dout(p1_dout), .p1_ack(p1_ack),
    .p2_req(p2_req), .p2_addr(p2_addr), .p2_dout(p2_dout), .p2_ack(p2_ack),
    .p3_req(p3_req), .p3_addr(p3_addr), .p3_dout(p3_dout), .p3_ack(p3_ack), .p3_urgent(p3_urgent),
    .p4_req(p4_req), .p4_addr(p4_addr), .p4_dout(p4_dout), .p4_ack(p4_ack), .p4_urgent(p4_urgent),
    .p5_req(p5_req), .p5_addr(p5_addr), .p5_dout(p5_dout), .p5_ack(p5_ack),
    .p6_req(p6_req), .p6_addr(p6_addr), .p6_dout(p6_dout), .p6_ack(p6_ack)
);

//////////////////////////////   INPUTS   /////////////////////////////////////
// joystick bits: 0 right 1 left 2 down 3 up 4 vulcan 5 missile 6 start
//                7 coin 8 test 9 service
// analog: raw MiSTer axes; the core maps them per game (descriptor analog mode)
wire [1:0] stick_mode = status[9:8];

// Pause: the mapped button (joystick bit 10) or the OSD open with the option set
wire pause = joystick_0[10] | (status[10] & OSD_STATUS);

//////////////////////////////   CORE   ///////////////////////////////////////
wire  [7:0] r, g, b;
wire        ce_pix, hs, vs, hb, vb;
wire signed [15:0] aud_l, aud_r;

xb_core core (
    .clk_sys(clk_sys), .clk_ram(clk_ram), .reset(reset), .pause(pause), .rear_en(~status[11]),
    .board_desc(board_desc),
    .tile_wr(tile_wr), .tile_waddr(tile_waddr), .tile_wdata(tile_wdata),
    .road_wr(road_wr), .road_waddr(road_waddr), .road_wdata(road_wdata),
    .key_wr(key_wr), .key_waddr(key_waddr), .key_wdata(key_wdata),
    .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
    .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
    .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
    .p0_req(p0_req), .p0_addr(p0_addr), .p0_dout(p0_dout), .p0_ack(p0_ack),
    .p1_req(p1_req), .p1_addr(p1_addr), .p1_dout(p1_dout), .p1_ack(p1_ack),
    .p2_req(p2_req), .p2_addr(p2_addr), .p2_dout(p2_dout), .p2_ack(p2_ack),
    .p3_req(p3_req), .p3_addr(p3_addr), .p3_dout(p3_dout), .p3_ack(p3_ack), .p3_urgent(p3_urgent),
    .p4_req(p4_req), .p4_addr(p4_addr), .p4_dout(p4_dout), .p4_ack(p4_ack), .p4_urgent(p4_urgent),
    .p5_req(p5_req), .p5_addr(p5_addr), .p5_dout(p5_dout), .p5_ack(p5_ack),
    .p6_req(p6_req), .p6_addr(p6_addr), .p6_dout(p6_dout), .p6_ack(p6_ack),
    .p1_buttons(joystick_0[15:0]), .p2_buttons(joystick_1[15:0]),
    .aim1_x(joystick_r_analog_0[7:0]), .aim1_y(joystick_r_analog_0[15:8]),
    .aim2_x(joystick_r_analog_1[7:0]), .aim2_y(joystick_r_analog_1[15:8]),
    .stick_x(joystick_l_analog_0[7:0]), .stick_y(joystick_l_analog_0[15:8]),
    .throttle(joystick_r_analog_0[15:8] ^ 8'h80), .stick_mode(stick_mode),
    .dsw_a(dsw_a), .dsw_b(dsw_b),
    .service(joystick_0[9]), .test(status[7] | joystick_0[8]),
    .coin1(joystick_0[7]), .coin2(1'b0),
    .nv_download(nv_download), .nv_upload(nv_upload), .nv_wr(ioctl_wr), .nv_rd(ioctl_rd),
    .nv_addr(ioctl_addr[15:1]), .nv_din(ioctl_dout), .nv_dout(ioctl_din), .nv_modified(nv_modified),
    .r(r), .g(g), .b(b),
    .ce_pix(ce_pix), .hs(hs), .vs(vs), .hb(hb), .vb(vb),
    .audio_l(aud_l), .audio_r(aud_r),
    .trace_main_addr(), .trace_main_start(), .trace_main_fc(),
    .trace_sub_addr(), .trace_sub_start(), .trace_sub_fc()
);

assign AUDIO_L = aud_l;
assign AUDIO_R = aud_r;

//////////////////////////////   VIDEO   //////////////////////////////////////
wire [2:0] scandoubler_fx = status[5:3];
wire [1:0] aspect = status[2:1];
wire [11:0] aspect_arx = (aspect == 0) ? 12'd4 : {10'd0, (aspect - 1'd1)};
wire [11:0] aspect_ary = (aspect == 0) ? 12'd3 : 12'd0;

// arcade_video drives CLK_VIDEO, CE_PIXEL, VGA_R/G/B/HS/VS/SL directly; its
// VGA_DE goes through video_freak (which owns the emu VGA_DE output).
// GAMMA=0: this sys_top does not export gamma_bus to emu.
wire vga_de_av;
arcade_video #(.WIDTH(320), .DW(24), .GAMMA(0)) arcade_video (
    .*,
    .VGA_DE(vga_de_av),
    .gamma_bus(),
    .clk_video(clk_sys),
    .ce_pix(ce_pix),
    .RGB_in({r, g, b}),
    .HBlank(hb),
    .VBlank(vb),
    .HSync(hs),
    .VSync(vs),
    .fx(scandoubler_fx),
    .forced_scandoubler(1'b0)
);

video_freak video_freak (
    .CLK_VIDEO (clk_sys),
    .CE_PIXEL  (CE_PIXEL),
    .VGA_VS    (VGA_VS),
    .HDMI_WIDTH(HDMI_WIDTH),
    .HDMI_HEIGHT(HDMI_HEIGHT),
    .VGA_DE    (VGA_DE),
    .VIDEO_ARX (VIDEO_ARX),
    .VIDEO_ARY (VIDEO_ARY),
    .VGA_DE_IN (vga_de_av),
    .ARX       (aspect_arx),
    .ARY       (aspect_ary),
    .CROP_SIZE (12'd0),
    .CROP_OFF  (5'd0),
    .SCALE     (3'd0)
);

endmodule
