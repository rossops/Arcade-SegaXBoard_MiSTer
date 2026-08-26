//============================================================================
//  MiSTer DDRAM port model for the board simulation: 64-bit words, burst
//  reads (one DOUT_READY beat per word), single writes with byte enables,
//  a few clocks of latency and occasional BUSY.
//============================================================================
`timescale 1ns/1ps
module ddram_model #(parameter [28:0] BASE = 29'h0600_0000, parameter WORDS = 1 << 18) (   // 2 MB: two 1024x512 buffers in the 2x mode
    input             clk,
    output reg        DDRAM_BUSY,
    input       [7:0] DDRAM_BURSTCNT,
    input      [28:0] DDRAM_ADDR,
    output reg [63:0] DDRAM_DOUT,
    output reg        DDRAM_DOUT_READY,
    input             DDRAM_RD,
    input      [63:0] DDRAM_DIN,
    input       [7:0] DDRAM_BE,
    input             DDRAM_WE
);
reg [63:0] mem [0:WORDS-1];
integer i;
initial for (i = 0; i < WORDS; i = i + 1) mem[i] = 64'd0;

reg [7:0] rd_left;
reg [28:0] rd_addr;
reg [3:0] lat;
reg [7:0] rnd;
always @(posedge clk) begin
    rnd <= rnd * 8'd37 + 8'd11;
    DDRAM_DOUT_READY <= 1'b0;
    // write
    if (DDRAM_WE && !DDRAM_BUSY) begin
        for (i = 0; i < 8; i = i + 1)
            if (DDRAM_BE[i] && (DDRAM_ADDR - BASE) < WORDS)
                mem[DDRAM_ADDR - BASE][i*8 +: 8] <= DDRAM_DIN[i*8 +: 8];
    end
    // read burst
    if (DDRAM_RD && !DDRAM_BUSY && rd_left == 0) begin
        rd_left <= DDRAM_BURSTCNT; rd_addr <= DDRAM_ADDR; lat <= 4'd6;
    end
    else if (rd_left != 0) begin
        if (lat != 0) lat <= lat - 1;
        else begin
            DDRAM_DOUT <= ((rd_addr - BASE) < WORDS) ? mem[rd_addr - BASE] : 64'hFFFF_FFFF_FFFF_FFFF;
            DDRAM_DOUT_READY <= 1'b1;
            rd_addr <= rd_addr + 1; rd_left <= rd_left - 1;
        end
    end
    // busy while a burst read is in flight, plus some random stalls
    DDRAM_BUSY <= (rd_left != 0) || (rnd[7:5] == 3'd0);
end
initial begin rd_left = 0; DDRAM_BUSY = 0; rnd = 8'h5a; end
endmodule
