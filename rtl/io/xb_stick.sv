//============================================================================
//  After Burner stick options (OSD, not board behaviour). The cabinet's
//  stick is spring-centred, so the defaults keep what the core did before:
//  the D-pad snaps to full lock and lets go to centre (the combinational
//  path in xb_core), the analog axis passes straight through. Three opt-ins:
//    ramp      the D-pad drives a virtual stick 5 counts a frame (full lock
//              in 26 frames, near MAME's PORT_KEYDELTA(4) over 0x20..0xE0)
//              instead of snapping
//    ~recenter releasing the D-pad leaves the virtual stick where it is; the
//              opposite direction brings it back, stopping at centre on the
//              way through (snap plus hold gives left, centre, right)
//    cal       zero calibration for a drifting thumbstick: the axis value
//              when the option is turned on (or at reset with it on) is
//              taken as centre and subtracted, saturating at the ends
//  xb_core enables the virtual stick (vst_en) only when ramp or hold is on
//  and a D-pad mode is selected, so with both off nothing here is in the
//  signal path. With the virtual stick in use it replaces the analog axis
//  while it is off centre or a direction is held (x_dpad / y_dpad), then the
//  analog axis shows through again. Up is negative, as on the MiSTer axis.
//============================================================================
module xb_stick (
    input                   clk,
    input                   reset,
    input                   frame,          // one clock per frame
    input  signed [7:0]     ax_in, ay_in,   // MiSTer left stick, -128..127
    input                   right, left, down, up,
    input                   vst_en,         // virtual stick in use
    input                   ramp,           // 0 snap, 1 ramp
    input                   recenter,       // 1 return to centre on release
    input                   cal,            // analog zero calibration
    output signed [7:0]     ax_out, ay_out, // to the response shaper
    output                  x_dpad, y_dpad  // the virtual stick is the source
);

// ---- virtual stick. One move per frame toward the held direction, clamped
// to -128..127 and stopping at 0 when it crosses centre (with the snap step
// that is what makes hold three-position); with nothing held, back to 0 by
// the same step if recenter, else stay.
function automatic signed [7:0] stick_step(input signed [7:0] v, input pos, input neg,
                                           input rc, input [7:0] step);
    logic signed [9:0] n, s, st;
    begin
        s  = {{2{v[7]}}, v};
        st = {2'b00, step};
        if (pos) begin
            n = s + st;
            if (v[7] && n > 10'sd0) n = 10'sd0;
            if (n > 10'sd127) n = 10'sd127;
        end else if (neg) begin
            n = s - st;
            if (v > 8'sd0 && n < 10'sd0) n = 10'sd0;
            if (n < -10'sd128) n = -10'sd128;
        end else if (rc) begin
            if (v[7]) begin n = s + st; if (n > 10'sd0) n = 10'sd0; end
            else      begin n = s - st; if (n < 10'sd0) n = 10'sd0; end
        end else n = s;
        stick_step = n[7:0];
    end
endfunction

wire [7:0] step = ramp ? 8'd5 : 8'd128;
reg signed [7:0] vs_x, vs_y;
always @(posedge clk) begin
    if (reset || !vst_en) begin vs_x <= 8'sd0; vs_y <= 8'sd0; end
    else if (frame) begin
        vs_x <= stick_step(vs_x, right, left, recenter, step);
        vs_y <= stick_step(vs_y, down,  up,   recenter, step);
    end
end
assign x_dpad = vst_en && (right || left || vs_x != 8'sd0);
assign y_dpad = vst_en && (down  || up   || vs_y != 8'sd0);

// ---- zero calibration: sample the rest position when the option comes on
// and when reset lets go with it on (the config may already have it set at
// boot; the game is not running during reset, so the stick is at rest)
reg signed [7:0] off_x, off_y;
reg cal_d, reset_d;
always @(posedge clk) begin
    cal_d <= cal; reset_d <= reset;
    if (reset) begin off_x <= 8'sd0; off_y <= 8'sd0; end
    else if (cal && (!cal_d || reset_d)) begin off_x <= ax_in; off_y <= ay_in; end
end
function automatic signed [7:0] sat_sub(input signed [7:0] a, input signed [7:0] b);
    logic signed [8:0] d;
    begin
        d = {a[7], a} - {b[7], b};
        sat_sub = (d > 9'sd127) ? 8'sd127 : (d < -9'sd128) ? -8'sd128 : d[7:0];
    end
endfunction
wire signed [7:0] ax_cal = cal ? sat_sub(ax_in, off_x) : ax_in;
wire signed [7:0] ay_cal = cal ? sat_sub(ay_in, off_y) : ay_in;

assign ax_out = x_dpad ? vs_x : ax_cal;
assign ay_out = y_dpad ? vs_y : ay_cal;
endmodule
