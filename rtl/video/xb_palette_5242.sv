//============================================================================
//  Sega 315-5242 colour section: 8192 x 16-bit palette RAM (CPU port A,
//  pixel port B) and the 5-bit resistor ladder outputs.
//  Palette word: bit 15 = effects select (1 hilight / 0 shadow), 14:12 = LSB
//  of B/G/R, 11:8 B, 7:4 G, 3:0 R (MAME paletteram_w). `effects` selects the
//  shadow/hilight bank for the pixel (sprite shadow pen).
//  Output is registered two clocks after the address.
//============================================================================
module xb_palette_5242 (
    input             clk,
    // CPU
    input      [12:0] a_addr,
    input      [15:0] a_din,
    input       [1:0] a_be,
    input             a_we,
    output reg [15:0] a_dout,
    // pixel
    input      [12:0] b_addr,
    input             b_effects,
    output reg  [7:0] r, g, b
);
`include "xb_pal_lut.svh"

reg [15:0] mem [0:8191];
`ifdef SIMULATION
integer i;
initial for (i = 0; i < 8192; i = i + 1) mem[i] = 16'h0000;
`endif
reg [15:0] word;
reg        eff_d;
always @(posedge clk) begin
    if (a_we) begin
        if (a_be[1]) mem[a_addr][15:8] <= a_din[15:8];
        if (a_be[0]) mem[a_addr][7:0]  <= a_din[7:0];
    end
    a_dout <= mem[a_addr];
    word   <= mem[b_addr];
    eff_d  <= b_effects;
end

wire [4:0] r5 = {word[3:0],  word[12]};
wire [4:0] g5 = {word[7:4],  word[13]};
wire [4:0] b5 = {word[11:8], word[14]};
always @(posedge clk) begin
    if (!eff_d)        begin r <= PAL_NORMAL[r5];  g <= PAL_NORMAL[g5];  b <= PAL_NORMAL[b5];  end
    else if (word[15]) begin r <= PAL_HILIGHT[r5]; g <= PAL_HILIGHT[g5]; b <= PAL_HILIGHT[b5]; end
    else               begin r <= PAL_SHADOW[r5];  g <= PAL_SHADOW[g5];  b <= PAL_SHADOW[b5];  end
end
endmodule
