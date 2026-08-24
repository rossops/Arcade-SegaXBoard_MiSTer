//============================================================================
//  Sega 315-5248 hardware multiplier (one per 68000 on the X Board)
//  Word offsets (address bits 2:1): 0/1 = operands (r/w), 2 = signed product
//  high word, 3 = product low word. Reference: MAME segaic16_m.cpp.
//  The product is combinational on the operand registers, as on the chip
//  ("the result is updated as soon as either register is written").
//============================================================================
module xb_math_5248 (
    input             clk,
    input             reset,
    input             cs,          // one clk pulse per bus access
    input             we,
    input       [1:0] addr,        // word offset
    input      [15:0] din,
    input       [1:0] be,          // byte enables {upper, lower}
    output reg [15:0] dout
);

reg [15:0] r0, r1;
wire signed [31:0] prod = $signed(r0) * $signed(r1);

always @(posedge clk) begin
    if (reset) begin
        r0 <= 16'd0; r1 <= 16'd0;
    end
    else if (cs && we) begin
        if (addr[0] == 1'b0) begin
            if (be[1]) r0[15:8] <= din[15:8];
            if (be[0]) r0[7:0]  <= din[7:0];
        end
        else begin
            if (be[1]) r1[15:8] <= din[15:8];
            if (be[0]) r1[7:0]  <= din[7:0];
        end
    end
end

always @* begin
    case (addr)
        2'd0: dout = r0;
        2'd1: dout = r1;
        2'd2: dout = prod[31:16];
        default: dout = prod[15:0];
    endcase
end
endmodule
