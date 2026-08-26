//============================================================================
//  Analog axis response (OSD option, not board behaviour).
//  A thumbstick reaches full deflection in a few millimetres where the
//  cabinet's stick or wheel has travel, so the games feel twitchy around
//  centre. The curves keep full lock reachable (the games need the extremes):
//    curve 0 linear   out = in
//    curve 1 soft     |out| = |in|^2 / 128       (half deflection -> a quarter)
//    curve 2 softer   |out| = |in|^3 / 16384
//  then the range setting scales the magnitude: 0 100%, 1 75%, 2 50%.
//  Linear with 100% is bit-exact pass-through. Three registered stages; the
//  axes are sampled by a 1.25 MHz ADC, so the latency is invisible.
//============================================================================
module xb_ana_shape (
    input               clk,
    input  signed [7:0] axis,      // MiSTer axis, -128..127
    input         [1:0] curve,
    input         [1:0] range,
    output reg signed [7:0] out
);
reg        neg1, neg2, neg3;
reg  [7:0] mag1;                   // 0..128
reg [15:0] sq2;                    // mag^2, 0..16384
reg  [7:0] mag2;
reg [23:0] cube3;                  // mag^3, 0..2097152
reg [15:0] sq3;
reg  [7:0] mag3;
reg  [1:0] curve1, curve2, curve3, range1, range2, range3;
reg  [7:0] shaped, ranged;
wire [9:0] r75 = ({2'd0, shaped} * 10'd3) >> 2;
always @* begin
    case (curve3)
        2'd1:    shaped = sq3[14:7];          // mag^2 / 128
        2'd2:    shaped = cube3[21:14];       // mag^3 / 16384
        default: shaped = mag3;
    endcase
    case (range3)
        2'd1:    ranged = r75[7:0];           // 75%
        2'd2:    ranged = shaped >> 1;        // 50%
        default: ranged = shaped;
    endcase
end
always @(posedge clk) begin
    // 1: magnitude
    neg1 <= axis[7]; mag1 <= axis[7] ? (8'd0 - axis) : axis;   // -128 -> 128
    curve1 <= curve; range1 <= range;
    // 2: square
    sq2 <= mag1 * mag1; mag2 <= mag1; neg2 <= neg1; curve2 <= curve1; range2 <= range1;
    // 3: cube
    cube3 <= sq2 * mag2; sq3 <= sq2; mag3 <= mag2; neg3 <= neg2; curve3 <= curve2; range3 <= range2;
    // 4: curve and range picked above, restore the sign
    out <= neg3 ? (8'd0 - ranged) : ranged;
end
endmodule
