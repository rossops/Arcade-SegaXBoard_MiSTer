//============================================================================
//  Tile ROM (3 x 64 KB, one bitplane per ROM) held in BRAM and filled by the
//  ROM loader. A read returns the three plane bytes of one tile row:
//  address = {code[12:0], row[2:0]} -> plane p byte at p*0x10000 + addr.
//  Plane 2 (third ROM, epr-11113) is pen bit 2 (MAME gfx_8x8x3_planar:
//  RGN_FRAC(2,3) is the MSB plane). Pixel x of a row is bit 7-x of each byte.
//============================================================================
module xb_tilerom (
    input             clk,
    // loader (byte writes)
    input             wr,
    input      [17:0] wr_addr,      // 0..0x2FFFF
    input       [7:0] wr_data,
    // renderer
    input      [15:0] rd_addr,      // {code, row}
    output reg  [7:0] plane0, plane1, plane2
);
reg [7:0] rom0 [0:65535];
reg [7:0] rom1 [0:65535];
reg [7:0] rom2 [0:65535];
`ifdef SIMULATION
initial begin
    if ($test$plusargs("tilerom")) begin
        $readmemh("tilerom0.hex", rom0);
        $readmemh("tilerom1.hex", rom1);
        $readmemh("tilerom2.hex", rom2);
    end
end
`endif
always @(posedge clk) begin
    if (wr) begin
        case (wr_addr[17:16])
            2'd0: rom0[wr_addr[15:0]] <= wr_data;
            2'd1: rom1[wr_addr[15:0]] <= wr_data;
            default: rom2[wr_addr[15:0]] <= wr_data;
        endcase
    end
    plane0 <= rom0[rd_addr];
    plane1 <= rom1[rd_addr];
    plane2 <= rom2[rd_addr];
end
endmodule
