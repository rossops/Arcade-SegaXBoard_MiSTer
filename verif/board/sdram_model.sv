//============================================================================
//  Port-level model of rtl/mem/sdram.sv for the board simulation.
//  Same request contract (rising edge of req, 2-clk ack stretch), fixed
//  latency, backed by a 32 MB array preloaded from the packed ROM hex files.
//============================================================================
`timescale 1ns/1ps
module sdram_model #(
    parameter LATENCY = 12,
    parameter string HEXDIR = "verif/golden/aburner2"
) (
    input             clk,
    input             init,
    output reg        ready,
    input             wr_req,  input [24:1] wr_addr, input [15:0] wr_din, input [1:0] wr_be, output reg wr_ack,
    input             p0_req,  input [24:3] p0_addr, output reg  [63:0] p0_dout, output reg p0_ack,
    input             p1_req,  input [24:3] p1_addr, output reg  [63:0] p1_dout, output reg p1_ack,
    input             p2_req,  input [24:4] p2_addr, output reg [127:0] p2_dout, output reg p2_ack,
    input             p3_req,  input [24:3] p3_addr, output reg  [63:0] p3_dout, output reg p3_ack, input p3_urgent,
    input             p4_req,  input [24:4] p4_addr, output reg [127:0] p4_dout, output reg p4_ack, input p4_urgent,
    input             p5_req,  input [24:3] p5_addr, output reg  [63:0] p5_dout, output reg p5_ack,
    input             p6_req,  input [24:1] p6_addr, output reg  [15:0] p6_dout, output reg p6_ack
);
import xb_pkg::*;

reg [15:0] mem [0:(1<<24)-1];   // 16M words

task automatic load(input string f, input [24:0] base);
    $readmemh(f, mem, base >> 1);
endtask

string hexdir;
initial begin
    ready = 1'b0;
    if (!$value$plusargs("hexdir=%s", hexdir)) hexdir = HEXDIR;
    load({hexdir, "/main.hex"},   SDR_MAIN_BASE);
    load({hexdir, "/sub.hex"},    SDR_SUB_BASE);
    load({hexdir, "/z80.hex"},    SDR_Z80_BASE);
    load({hexdir, "/road.hex"},   SDR_ROAD_BASE);
    load({hexdir, "/pcm.hex"},    SDR_PCM_BASE);
    load({hexdir, "/sprite.hex"}, SDR_SPRITE_BASE);
    load({hexdir, "/tile.hex"},   SDR_TILE_BASE);
end

function automatic [63:0] rd4(input [24:3] a);
    rd4 = {mem[{a, 2'd3}], mem[{a, 2'd2}], mem[{a, 2'd1}], mem[{a, 2'd0}]};
endfunction
function automatic [127:0] rd8(input [24:4] a);
    rd8 = {mem[{a, 3'd7}], mem[{a, 3'd6}], mem[{a, 3'd5}], mem[{a, 3'd4}],
           mem[{a, 3'd3}], mem[{a, 3'd2}], mem[{a, 3'd1}], mem[{a, 3'd0}]};
endfunction

// one simple sequencer: serve pending ports round-robin with fixed latency
reg [7:0] pend;
reg [7:0] req_d;
reg [24:3] a0, a1, a3, a5; reg [24:4] a2, a4; reg [24:1] a6, aw; reg [15:0] dw; reg [1:0] bw;
reg [4:0] cnt;
reg [2:0] cur;
reg       busy;
reg [1:0] stretch;
integer k;

always @(posedge clk) begin
    if (init) begin
        ready <= 1'b0; pend <= 0; req_d <= 0; busy <= 0; cnt <= 0; stretch <= 0;
        {p0_ack,p1_ack,p2_ack,p3_ack,p4_ack,p5_ack,p6_ack,wr_ack} <= 0;
    end
    else begin
        ready <= 1'b1;
        req_d <= {wr_req, p6_req, p5_req, p4_req, p3_req, p2_req, p1_req, p0_req};
        if (p0_req && !req_d[0]) begin pend[0] <= 1; a0 <= p0_addr; end
        if (p1_req && !req_d[1]) begin pend[1] <= 1; a1 <= p1_addr; end
        if (p2_req && !req_d[2]) begin pend[2] <= 1; a2 <= p2_addr; end
        if (p3_req && !req_d[3]) begin pend[3] <= 1; a3 <= p3_addr; end
        if (p4_req && !req_d[4]) begin pend[4] <= 1; a4 <= p4_addr; end
        if (p5_req && !req_d[5]) begin pend[5] <= 1; a5 <= p5_addr; end
        if (p6_req && !req_d[6]) begin pend[6] <= 1; a6 <= p6_addr; end
        if (wr_req && !req_d[7]) begin pend[7] <= 1; aw <= wr_addr; dw <= wr_din; bw <= wr_be; end

        if (stretch != 0) stretch <= stretch - 1;
        else {p0_ack,p1_ack,p2_ack,p3_ack,p4_ack,p5_ack,p6_ack,wr_ack} <= 0;

        if (!busy) begin
            if (pend != 0) begin
                busy <= 1; cnt <= LATENCY;
                cur <= pend[7] ? 3'd7 : pend[0] ? 3'd0 : pend[1] ? 3'd1 : pend[5] ? 3'd5 : pend[6] ? 3'd6 :
                       pend[3] ? 3'd3 : pend[4] ? 3'd4 : 3'd2;
            end
        end
        else if (cnt != 0) cnt <= cnt - 1;
        else begin
            busy <= 0; stretch <= 1;
            case (cur)
                3'd0: begin p0_dout <= rd4(a0); p0_ack <= 1; pend[0] <= 0; end
                3'd1: begin p1_dout <= rd4(a1); p1_ack <= 1; pend[1] <= 0; end
                3'd2: begin p2_dout <= rd8(a2); p2_ack <= 1; pend[2] <= 0; end
                3'd3: begin p3_dout <= rd4(a3); p3_ack <= 1; pend[3] <= 0; end
                3'd4: begin p4_dout <= rd8(a4); p4_ack <= 1; pend[4] <= 0; end
                3'd5: begin p5_dout <= rd4(a5); p5_ack <= 1; pend[5] <= 0; end
                3'd6: begin p6_dout <= mem[a6]; p6_ack <= 1; pend[6] <= 0; end
                default: begin
                    if (bw[1]) mem[aw][15:8] <= dw[15:8];
                    if (bw[0]) mem[aw][7:0]  <= dw[7:0];
                    wr_ack <= 1; pend[7] <= 0;
                end
            endcase
        end
    end
end
endmodule
