//============================================================================
//  Sega X Board — video timing (315-5275 scanline counter / 315-5197 sync)
//  400 x 262 at 6.25 MHz pixel clock (clk_sys/8), 320 x 224 visible.
//  MAME: m_screen->set_raw(MASTER_CLOCK/8, 400, 0, 320, 262, 0, 224).
//  V0 (vcnt[0]) clocks the 315-5250 timer; vblank irq is a 1-line pulse
//  starting at line 223; the tilemap chip latches its registers at line 261.
//============================================================================
import xb_pkg::*;

module xb_video_timing (
    input             clk,
    input             reset,
    output reg        ce_pix,        // one clk pulse per pixel (clk/8)
    output reg  [8:0] hcnt,          // 0..399
    output reg  [8:0] vcnt,          // 0..261
    output reg        hblank,        // hcnt >= 320
    output reg        vblank,        // vcnt >= 224
    output reg        hsync,
    output reg        vsync,
    output            v0,            // scanline counter bit 0 -> 315-5250 EXCK
    output reg        line_start,    // one clk pulse at hcnt==0 (with ce_pix)
    output reg        vbl_irq,       // level: vcnt == 223
    output reg        latch_pulse,   // one clk pulse at start of line 261
    // enhanced (2x) output grid: two 800-pixel lines per game line at clk/4.
    // With hires low these mirror the game grid.
    input             hires,
    output reg        ce_out,        // output pixel enable (clk/4 or clk/8)
    output reg  [9:0] ohcnt,         // 0..799 (0..399 when not hires)
    output reg        oline,         // second output line of the game line
    output reg        ohblank,
    output reg        ohsync
);

reg [2:0] div;
assign v0 = vcnt[0];
// 2x grid: 800x524 at 25 MHz (a tick every 2 clocks, ce_pix coincides with
// one), so a 3200-clock game line is exactly two 800-tick output lines
localparam [9:0] OH_LAST = 10'd799, OH_ACT = 10'd640, OHS_START = 10'd672, OHS_END = 10'd736;
wire otick = div[0];
wire [9:0] ohnext = ohcnt + 10'd1;
always @(posedge clk) begin
    ce_out <= 1'b0;
    if (reset) begin ohcnt <= 10'd0; oline <= 1'b0; ohblank <= 1'b0; ohsync <= 1'b0; end
    else if (!hires) begin
        ce_out  <= (div == 3'd7);
        ohcnt   <= {1'b0, (div == 3'd7) ? ((hcnt == H_LAST) ? 9'd0 : hcnt + 9'd1) : hcnt};
        oline   <= 1'b0;
        ohblank <= hblank;
        ohsync  <= hsync;
    end
    else if (otick) begin
        ce_out <= 1'b1;
        if (div == 3'd7 && hcnt == H_LAST) begin ohcnt <= 10'd0; oline <= 1'b0; end   // realign at the game line
        else if (ohcnt == OH_LAST) begin ohcnt <= 10'd0; oline <= ~oline; end
        else ohcnt <= ohnext;
        ohblank <= (ohnext >= OH_ACT) && (ohcnt != OH_LAST);
        ohsync  <= (ohnext >= OHS_START) && (ohnext < OHS_END);
    end
end

// Sync widths follow the System 16-family convention used by MAME's screen
// layout: hsync from 336..367 (32 px), vsync lines 240..243 (4 lines).
localparam [8:0] HS_START = 9'd336, HS_END = 9'd368;
localparam [8:0] VS_START = 9'd240, VS_END = 9'd244;
localparam [8:0] H_LAST = 9'(H_TOTAL-1), V_LAST = 9'(V_TOTAL-1);
localparam [8:0] H_ACT = 9'(H_ACTIVE), V_ACT = 9'(V_ACTIVE);
localparam [8:0] VBL_LINE = 9'(VBLANK_LINE), LAT_LINE = 9'(LATCH_LINE);
wire [8:0] vnext = (vcnt == V_LAST) ? 9'd0 : vcnt + 9'd1;
wire [8:0] hnext = hcnt + 9'd1;

always @(posedge clk) begin
    ce_pix      <= 1'b0;
    line_start  <= 1'b0;
    latch_pulse <= 1'b0;
    if (reset) begin
        div <= 3'd0; hcnt <= 9'd0; vcnt <= 9'd0;
        hblank <= 1'b0; vblank <= 1'b0; hsync <= 1'b0; vsync <= 1'b0;
        vbl_irq <= 1'b0;
    end
    else begin
        div <= div + 3'd1;
        if (div == 3'd7) begin
            ce_pix <= 1'b1;
            if (hcnt == H_LAST) begin
                hcnt <= 9'd0;
                line_start <= 1'b1;
                vcnt <= vnext;
                // registered on the new line number
                vblank      <= (vnext >= V_ACT);
                vsync       <= (vnext >= VS_START) && (vnext < VS_END);
                vbl_irq     <= (vnext == VBL_LINE);
                latch_pulse <= (vnext == LAT_LINE);
            end
            else hcnt <= hnext;
            hblank <= (hnext >= H_ACT) && (hcnt != H_LAST);
            hsync  <= (hnext >= HS_START) && (hnext < HS_END);
        end
    end
end
endmodule
