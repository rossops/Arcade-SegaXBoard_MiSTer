//============================================================================
//  Road ROM line prefetch. The 64 KB road ROM lives in SDRAM (SDR_ROAD_BASE);
//  the 315-5275 renderer draws one line at a time and a line needs 256 bytes
//  of it: 64 bytes per plane for each of the two roads (plane 1 at +0x4000,
//  road 1 at +0x8000). On `fetch` the four 64-byte runs are read as sixteen
//  128-bit bursts into a line buffer, `ready` rises, and the renderer's two
//  byte reads are served from the buffer with the same one-clock latency the
//  BRAM copy had (rd_q = buf[{road, plane, byte}] for a ROM address).
//  Two copies of the buffer give the two read ports; both are written alike.
//  Replaces the 64 KB BRAM (64 M10K blocks) at a cost of 4 Kbit of MLAB.
//============================================================================
module xb_roadrom
    import xb_pkg::*;
(
    input             clk,           // clk_sys
    input             reset,
    // renderer
    input             fetch,         // one clock: lines below are valid
    input       [7:0] line0,         // road 0 ROM line (data0[8:1])
    input       [7:0] line1,         // road 1 ROM line (data1[8:1])
    output reg        ready,         // buffer holds line0/line1
    input      [15:0] rd_addr0,      // ROM byte addresses as before
    input      [15:0] rd_addr1,
    output reg  [7:0] rd_q0,
    output reg  [7:0] rd_q1,
    // SDRAM (128-bit burst port)
    output reg        sdr_req,
    output reg [24:4] sdr_addr,
    input     [127:0] sdr_dout,
    input             sdr_ack
);
reg  [7:0] bufa [0:255];
reg  [7:0] bufb [0:255];
reg  [7:0] l0, l1;
reg  [3:0] blk;                      // {road, plane, 16-byte group}
reg  [3:0] wcnt;                     // byte within the burst being stored
reg [127:0] data;
reg        ack_d;
typedef enum logic [1:0] { S_IDLE, S_REQ, S_WAIT, S_STORE } st_t;
st_t st;

// byte address of burst `b` for the lines held: road*0x8000 + plane*0x4000 + line*0x40 + group*16
wire [7:0]  line_sel = blk[3] ? l1 : l0;
wire [24:0] baddr = SDR_ROAD_BASE + {9'd0, blk[3], blk[2], line_sel, blk[1:0], 4'd0};

always @(posedge clk) begin
    rd_q0 <= bufa[{rd_addr0[15], rd_addr0[14], rd_addr0[5:0]}];
    rd_q1 <= bufb[{rd_addr1[15], rd_addr1[14], rd_addr1[5:0]}];
    ack_d <= sdr_ack;
    if (reset) begin
        st <= S_IDLE; ready <= 1'b0; sdr_req <= 1'b0; blk <= 4'd0; wcnt <= 4'd0;
    end
    else case (st)
        S_IDLE: if (fetch) begin
            ready <= 1'b0; l0 <= line0; l1 <= line1; blk <= 4'd0; st <= S_REQ;
        end
        S_REQ: begin
            sdr_addr <= baddr[24:4]; sdr_req <= 1'b1; st <= S_WAIT;
        end
        S_WAIT: if (sdr_ack && !ack_d) begin
            sdr_req <= 1'b0; data <= sdr_dout; wcnt <= 4'd0; st <= S_STORE;
        end
        S_STORE: begin
            bufa[{blk, wcnt}] <= data[7:0];
            bufb[{blk, wcnt}] <= data[7:0];
            data <= data >> 8;
            wcnt <= wcnt + 4'd1;
            if (wcnt == 4'd15) begin
                if (blk == 4'd15) begin ready <= 1'b1; st <= S_IDLE; end
                else begin blk <= blk + 4'd1; st <= S_REQ; end
            end
        end
        default: st <= S_IDLE;
    endcase
end
endmodule
