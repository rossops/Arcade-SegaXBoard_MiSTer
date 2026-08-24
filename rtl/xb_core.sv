//============================================================================
//  Sega X Board — board top (M0 skeleton)
//  Owns the video timing and the module instances that later milestones fill
//  in. Until the tilemap/sprite/road/mixer land, the output is a fixed test
//  pattern so the full MiSTer flow (loader, SDRAM, video, audio) can be
//  exercised on hardware.
//============================================================================
import xb_pkg::*;

module xb_core (
    input             clk_sys,      // 50 MHz
    input             clk_ram,      // 100 MHz
    input             reset,
    input             pause,
    input board_desc_t board_desc,

    // SDRAM read ports (clk_ram domain)
    output            p0_req, output [24:3] p0_addr, input  [63:0] p0_dout, input p0_ack,
    output            p1_req, output [24:3] p1_addr, input  [63:0] p1_dout, input p1_ack,
    output            p2_req, output [24:4] p2_addr, input [127:0] p2_dout, input p2_ack,
    output            p3_req, output [24:3] p3_addr, input  [63:0] p3_dout, input p3_ack, output p3_urgent,
    output            p4_req, output [24:4] p4_addr, input [127:0] p4_dout, input p4_ack, output p4_urgent,
    output            p5_req, output [24:3] p5_addr, input  [63:0] p5_dout, input p5_ack,
    output            p6_req, output [24:1] p6_addr, input  [15:0] p6_dout, input p6_ack,

    // inputs
    input      [15:0] p1_buttons,   // MRA-mapped digital
    input       [7:0] adc_x, adc_y, adc_throttle,
    input       [7:0] dsw_a, dsw_b,
    input             service, test,
    input             coin1, coin2,

    // video
    output      [7:0] r, g, b,
    output            ce_pix, hs, vs, hb, vb,

    // audio
    output signed [15:0] audio_l, audio_r
);

// ---------------------------------------------------------------- timing
wire [8:0] hcnt, vcnt;
wire       v0, line_start, vbl_irq, latch_pulse;
xb_video_timing timing (
    .clk(clk_sys), .reset(reset),
    .ce_pix(ce_pix), .hcnt(hcnt), .vcnt(vcnt),
    .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs),
    .v0(v0), .line_start(line_start), .vbl_irq(vbl_irq), .latch_pulse(latch_pulse)
);

// ---------------------------------------------------------------- M0 stub
// Colour bars keyed by hcnt so the analog/HDMI path can be checked.
assign r = hb | vb ? 8'd0 : {hcnt[8:6], 5'd0} | {5'd0, vcnt[7:5]};
assign g = hb | vb ? 8'd0 : {hcnt[5:3], 5'd0};
assign b = hb | vb ? 8'd0 : (board_desc.game_id == 8'd0 ? 8'h40 : 8'h00);

assign audio_l = 16'sd0;
assign audio_r = 16'sd0;

assign p0_req = 1'b0; assign p0_addr = '0;
assign p1_req = 1'b0; assign p1_addr = '0;
assign p2_req = 1'b0; assign p2_addr = '0;
assign p3_req = 1'b0; assign p3_addr = '0; assign p3_urgent = 1'b0;
assign p4_req = 1'b0; assign p4_addr = '0; assign p4_urgent = 1'b0;
assign p5_req = 1'b0; assign p5_addr = '0;
assign p6_req = 1'b0; assign p6_addr = '0;

endmodule
