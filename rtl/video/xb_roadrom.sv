//============================================================================
//  Road ROM (64 KB) in BRAM, filled by the ROM loader; two read ports so a
//  road's two bitplanes (plane 1 at +0x4000) are fetched in one clock.
//============================================================================
module xb_roadrom (
    input             clk,
    input             wr,
    input      [15:0] wr_addr,
    input       [7:0] wr_data,
    input      [15:0] rd_addr0,
    input      [15:0] rd_addr1,
    output reg  [7:0] rd_q0,
    output reg  [7:0] rd_q1
);
reg [7:0] rom [0:65535];
`ifdef SIMULATION
initial if ($test$plusargs("roadrom")) $readmemh("roadrom.hex", rom);
`endif
always @(posedge clk) begin
    if (wr) rom[wr_addr] <= wr_data;
    rd_q0 <= rom[rd_addr0];
    rd_q1 <= rom[rd_addr1];
end
endmodule
