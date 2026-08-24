//============================================================================
//  Sony CXD1095 I/O port expander (two on the X Board, odd byte lanes)
//  Byte offsets 0..3 = ports A..D, 4 = port E (4 bits), 6 = direction
//  register (two bits per port: bit0 = low nibble input, bit1 = high nibble
//  input), 7 = port E direction (bit n = input). Reads return input pins for
//  input bits and the output latch for output bits. Reference MAME
//  cxd1095.cpp. /ODEN (oden_n low) forces every A-D pin to input without
//  touching the registers (MacDonald).
//============================================================================
module xb_cxd1095 (
    input             clk,
    input             reset,
    input             cs,
    input             we,
    input       [2:0] addr,
    input       [7:0] din,
    output reg  [7:0] dout,
    input             oden_n,

    input       [7:0] in_a, in_b, in_c, in_d,
    input       [3:0] in_e,
    output      [7:0] out_a, out_b, out_c, out_d,   // latch & ~dir (as MAME's dataout)
    output      [3:0] out_e,
    output      [7:0] dir_a, dir_b, dir_c, dir_d   // effective input mask
);

reg [7:0] latch [0:4];
reg [7:0] ddir  [0:4];      // 1 = input, per MAME m_data_dir
integer i;

wire [7:0] eff_dir_a = oden_n ? ddir[0] : 8'hFF;
wire [7:0] eff_dir_b = oden_n ? ddir[1] : 8'hFF;
wire [7:0] eff_dir_c = oden_n ? ddir[2] : 8'hFF;
wire [7:0] eff_dir_d = oden_n ? ddir[3] : 8'hFF;
assign dir_a = eff_dir_a; assign dir_b = eff_dir_b;
assign dir_c = eff_dir_c; assign dir_d = eff_dir_d;

assign out_a = latch[0] & ~eff_dir_a;
assign out_b = latch[1] & ~eff_dir_b;
assign out_c = latch[2] & ~eff_dir_c;
assign out_d = latch[3] & ~eff_dir_d;
assign out_e = latch[4][3:0] & ~ddir[4][3:0];

always @(posedge clk) begin
    if (reset) begin
        for (i = 0; i < 5; i = i + 1) begin latch[i] <= 8'd0; ddir[i] <= 8'hFF; end
    end
    else if (cs && we) begin
        case (addr)
            3'd0, 3'd1, 3'd2, 3'd3: latch[addr] <= din;
            3'd4: latch[4] <= {4'd0, din[3:0]};
            3'd6: begin
                ddir[0] <= {{4{din[1]}}, {4{din[0]}}};
                ddir[1] <= {{4{din[3]}}, {4{din[2]}}};
                ddir[2] <= {{4{din[5]}}, {4{din[4]}}};
                ddir[3] <= {{4{din[7]}}, {4{din[6]}}};
            end
            3'd7: ddir[4] <= {4'hF, din[3:0]};
            default: ;
        endcase
    end
end

always @* begin
    case (addr)
        3'd0: dout = (in_a & eff_dir_a) | (latch[0] & ~eff_dir_a);
        3'd1: dout = (in_b & eff_dir_b) | (latch[1] & ~eff_dir_b);
        3'd2: dout = (in_c & eff_dir_c) | (latch[2] & ~eff_dir_c);
        3'd3: dout = (in_d & eff_dir_d) | (latch[3] & ~eff_dir_d);
        3'd4: dout = {4'd0, (in_e & ddir[4][3:0]) | (latch[4][3:0] & ~ddir[4][3:0])};
        default: dout = 8'd0;
    endcase
end
endmodule
