//============================================================================
//  Byte-enabled dual-port RAM (port A: CPU read/write, port B: read-only
//  for the video chips). Inferred as M10K on Cyclone V.
//============================================================================
module xb_dpram #(
    parameter AW = 13,           // word address width
    parameter INIT_FF = 0        // fill with 0xFFFF at reset (sim only)
) (
    input             clk,       // port A (CPU)
    input    [AW-1:0] a_addr,
    input      [15:0] a_din,
    input       [1:0] a_be,
    input             a_we,
    output reg [15:0] a_dout,
    input             b_clk,     // port B (renderer) — may differ from clk
    input    [AW-1:0] b_addr,
    output reg [15:0] b_dout
);
reg [15:0] mem [0:(1<<AW)-1];
`ifdef SIMULATION
integer i;
initial for (i = 0; i < (1<<AW); i = i + 1) mem[i] = INIT_FF ? 16'hFFFF : 16'h0000;
`endif
always @(posedge clk) begin
    if (a_we) begin
        if (a_be[1]) mem[a_addr][15:8] <= a_din[15:8];
        if (a_be[0]) mem[a_addr][7:0]  <= a_din[7:0];
    end
    a_dout <= mem[a_addr];
end
always @(posedge b_clk) b_dout <= mem[b_addr];
endmodule
