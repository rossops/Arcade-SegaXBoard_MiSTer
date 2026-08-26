//============================================================================
//  Sega X Board for MiSTer — SDRAM controller
//  Forked from the System 32 core's controller (same request contract).
//  16-bit SDR SDRAM @ clk_ram (100 MHz), CL2, strictly serialized
//  transactions. ROM-download writes keep a row open for same-row words.
//
//  Read ports (all aligned bursts unless noted):
//    p0: main 68000 ROM cache   64-bit  (4 words)
//    p1: sub  68000 ROM cache   64-bit  (4 words)
//    p2: sprite ROM            128-bit  (8 words = 4 sprite dwords)
//    p3: tile cache             64-bit  (4 words)
//    p4: road line prefetch    128-bit  (8 words)
//    p5: Z80 ROM cache          64-bit  (4 words)
//    p6: 315-5218 PCM           16-bit  (single word)
//  Write port (ROM download / NVRAM only).
//
//  Arbitration: fixed priority p0 > p1 > p5 > p6 > p3 > p4 > p2, with
//    - deadline escalation: p3/p4 (line prefetch) jump to the top when their
//      `urgent` input is high;
//    - starvation guard: p2 is granted at least once per 8 grants when pending.
//  CPU-side ports are self-limiting (one outstanding request per CPU bus
//  cycle), so CPU-first priority cannot starve the video prefetchers.
//
//  REQUEST CONTRACT (all ports, including wr): one transaction per req
//  RISING EDGE; the address (and write data/be) is sampled on that edge.
//  Requesters are single-outstanding. ack is stretched to 2 clk_ram cycles
//  so clk_sys-domain requesters sample it exactly once.
//============================================================================

module sdram (
    input             clk,          // clk_ram
    input             init,         // reset/init request
    output reg        ready,

    inout      [15:0] SDRAM_DQ,
    output reg [12:0] SDRAM_A,
    output reg  [1:0] SDRAM_BA,
    output            SDRAM_DQML,
    output            SDRAM_DQMH,
    output reg        SDRAM_nCS,
    output reg        SDRAM_nCAS,
    output reg        SDRAM_nRAS,
    output reg        SDRAM_nWE,
    output            SDRAM_CKE,

    input             wr_req,
    input      [24:1] wr_addr,
    input      [15:0] wr_din,
    input       [1:0] wr_be,
    output reg        wr_ack,

    input             p0_req,  input [24:3] p0_addr, output reg  [63:0] p0_dout, output reg p0_ack,
    input             p1_req,  input [24:3] p1_addr, output reg  [63:0] p1_dout, output reg p1_ack,
    input             p2_req,  input [24:4] p2_addr, output reg [127:0] p2_dout, output reg p2_ack,
    input             p3_req,  input [24:3] p3_addr, output reg  [63:0] p3_dout, output reg p3_ack,
    input             p3_urgent,
    input             p4_req,  input [24:4] p4_addr, output reg [127:0] p4_dout, output reg p4_ack,
    input             p4_urgent,
    input             p5_req,  input [24:3] p5_addr, output reg  [63:0] p5_dout, output reg p5_ack,
    input             p6_req,  input [24:1] p6_addr, output reg  [15:0] p6_dout, output reg p6_ack,
    input             p7_req,  input [24:4] p7_addr, output reg [127:0] p7_dout, output reg p7_ack   // road ROM line prefetch
);

reg [15:0] dq_out;
reg        dq_oe;
reg  [1:0] dqm;

assign SDRAM_CKE  = 1'b1;
assign SDRAM_DQML = dqm[0];
assign SDRAM_DQMH = dqm[1];

// commands {nCS,nRAS,nCAS,nWE}
localparam CMD_NOP   = 4'b0111;
localparam CMD_ACT   = 4'b0011;
localparam CMD_READ  = 4'b0101;
localparam CMD_WRITE = 4'b0100;
localparam CMD_PRE   = 4'b0010;
localparam CMD_REF   = 4'b0001;
localparam CMD_MRS   = 4'b0000;

reg  [3:0] cmd = CMD_NOP;
assign {SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} = cmd;
assign SDRAM_DQ = dq_oe ? dq_out : 16'hZZZZ;

reg [15:0] init_cnt = 16'hffff;

// refresh: 8192 rows / 64 ms @ 100 MHz -> every 781 cycles; use 760
reg [9:0]  ref_cnt;
reg        ref_pend;

typedef enum logic [3:0] {
    ST_IDLE, ST_DISPATCH, ST_ACT, ST_RCD1, ST_RCD2, ST_RD, ST_RDW,
    ST_WR, ST_WRRC, ST_PRE_XFER, ST_PRE_REF, ST_REFW
} state_t;
state_t state = ST_IDLE;

reg [3:0]  grant;           // 0..7 read ports, 8 = write
reg [3:0]  rd_total;
reg [3:0]  rd_issued;
reg [3:0]  rd_captured;
reg [24:1] xfer_addr;
reg        is_write;
reg        reuse_open_write_row;
reg [15:0] din_r;
reg [1:0]  be_r;
reg [2:0]  wrrc_cnt;
reg [2:0]  refw_cnt;
reg [1:0]  pre_cnt;
reg        row_open;
reg  [1:0] open_bank;
reg [12:0] open_row;
reg [1:0]  ack_stretch;

// request mailboxes, latched on the rising edge of req
reg p0_pend, p1_pend, p2_pend, p3_pend, p4_pend, p5_pend, p6_pend, p7_pend, wr_pend;
reg [24:3] p0_addr_p, p1_addr_p, p3_addr_p, p5_addr_p;
reg [24:4] p2_addr_p, p4_addr_p, p7_addr_p;
reg [24:1] p6_addr_p, wr_addr_p;
reg [15:0] wr_din_p;
reg  [1:0] wr_be_p;

// starvation guard for the sprite port
reg [2:0]  p2_starve;

reg       read_valid;
reg [3:0] read_grant;
always @* begin
    read_valid = 1'b1;
    if      (p2_pend && p2_starve == 3'd7) read_grant = 4'd2;
    else if (p3_pend && p3_urgent)         read_grant = 4'd3;
    else if (p4_pend && p4_urgent)         read_grant = 4'd4;
    else if (p0_pend) read_grant = 4'd0;
    else if (p1_pend) read_grant = 4'd1;
    else if (p5_pend) read_grant = 4'd5;
    else if (p6_pend) read_grant = 4'd6;
    else if (p7_pend) read_grant = 4'd7;   // road line: 16 bursts per scanline, ahead of the deadline-escalated ports
    else if (p3_pend) read_grant = 4'd3;
    else if (p4_pend) read_grant = 4'd4;
    else if (p2_pend) read_grant = 4'd2;
    else begin read_grant = 4'd0; read_valid = 1'b0; end
end

reg p0_req_d, p1_req_d, p2_req_d, p3_req_d, p4_req_d, p5_req_d, p6_req_d, p7_req_d, wr_req_d;
reg p0_ack_d2, p1_ack_d2, p2_ack_d2, p3_ack_d2, p4_ack_d2, p5_ack_d2, p6_ack_d2, p7_ack_d2, wr_ack_d2;
always @(posedge clk) begin
    p0_ack_d2 <= p0_ack; p1_ack_d2 <= p1_ack; p2_ack_d2 <= p2_ack; p3_ack_d2 <= p3_ack;
    p4_ack_d2 <= p4_ack; p5_ack_d2 <= p5_ack; p6_ack_d2 <= p6_ack; p7_ack_d2 <= p7_ack; wr_ack_d2 <= wr_ack;
    if (p0_ack && !p0_ack_d2) p0_pend <= 1'b0;
    if (p1_ack && !p1_ack_d2) p1_pend <= 1'b0;
    if (p2_ack && !p2_ack_d2) p2_pend <= 1'b0;
    if (p3_ack && !p3_ack_d2) p3_pend <= 1'b0;
    if (p4_ack && !p4_ack_d2) p4_pend <= 1'b0;
    if (p5_ack && !p5_ack_d2) p5_pend <= 1'b0;
    if (p6_ack && !p6_ack_d2) p6_pend <= 1'b0;
    if (p7_ack && !p7_ack_d2) p7_pend <= 1'b0;
    if (wr_ack && !wr_ack_d2) wr_pend <= 1'b0;
    p0_req_d <= p0_req; p1_req_d <= p1_req; p2_req_d <= p2_req; p3_req_d <= p3_req;
    p4_req_d <= p4_req; p5_req_d <= p5_req; p6_req_d <= p6_req; p7_req_d <= p7_req; wr_req_d <= wr_req;
    if (p0_req && !p0_req_d) begin p0_pend <= 1'b1; p0_addr_p <= p0_addr; end
    if (p1_req && !p1_req_d) begin p1_pend <= 1'b1; p1_addr_p <= p1_addr; end
    if (p2_req && !p2_req_d) begin p2_pend <= 1'b1; p2_addr_p <= p2_addr; end
    if (p3_req && !p3_req_d) begin p3_pend <= 1'b1; p3_addr_p <= p3_addr; end
    if (p4_req && !p4_req_d) begin p4_pend <= 1'b1; p4_addr_p <= p4_addr; end
    if (p5_req && !p5_req_d) begin p5_pend <= 1'b1; p5_addr_p <= p5_addr; end
    if (p6_req && !p6_req_d) begin p6_pend <= 1'b1; p6_addr_p <= p6_addr; end
    if (p7_req && !p7_req_d) begin p7_pend <= 1'b1; p7_addr_p <= p7_addr; end
    if (wr_req && !wr_req_d) begin
        wr_pend <= 1'b1; wr_addr_p <= wr_addr; wr_din_p <= wr_din; wr_be_p <= wr_be;
    end
    if (init) begin
        {p0_pend,p1_pend,p2_pend,p3_pend,p4_pend,p5_pend,p6_pend,p7_pend,wr_pend} <= '0;
        {p0_req_d,p1_req_d,p2_req_d,p3_req_d,p4_req_d,p5_req_d,p6_req_d,p7_req_d,wr_req_d} <= '0;
        {p0_ack_d2,p1_ack_d2,p2_ack_d2,p3_ack_d2,p4_ack_d2,p5_ack_d2,p6_ack_d2,p7_ack_d2,wr_ack_d2} <= '0;
        p0_addr_p <= '0; p1_addr_p <= '0; p2_addr_p <= '0; p3_addr_p <= '0;
        p4_addr_p <= '0; p5_addr_p <= '0; p6_addr_p <= '0; p7_addr_p <= '0; wr_addr_p <= '0;
        wr_din_p <= '0; wr_be_p <= '0;
    end
end

`ifdef SIMULATION
generate
    genvar gi;
    for (gi = 0; gi < 9; gi = gi + 1) begin : g_reqwatch
        reg [7:0] held;
        wire req_i  = gi==0 ? p0_req  : gi==1 ? p1_req  : gi==2 ? p2_req  : gi==3 ? p3_req :
                      gi==4 ? p4_req  : gi==5 ? p5_req  : gi==6 ? p6_req  : gi==7 ? p7_req  : wr_req;
        wire pend_i = gi==0 ? p0_pend : gi==1 ? p1_pend : gi==2 ? p2_pend : gi==3 ? p3_pend :
                      gi==4 ? p4_pend : gi==5 ? p5_pend : gi==6 ? p6_pend : gi==7 ? p7_pend : wr_pend;
        always @(posedge clk) begin
            if (init || !req_i || pend_i) held <= 8'd0;
            else if (held != 8'hff) begin
                held <= held + 8'd1;
                if (held == 8'd200)
                    $display("SDRAM CONTRACT WARNING: port %0d req held %0d cycles after service", gi, held);
            end
        end
    end
endgenerate
`endif

reg [15:0] dq_in;
reg [3:0]  cl_pipe;
reg [15:0] cap_buf [0:7];
always @(posedge clk) dq_in <= SDRAM_DQ;

task automatic deliver(input [15:0] w);
    case (grant)
        4'd0: begin p0_dout <= {w, cap_buf[2], cap_buf[1], cap_buf[0]}; p0_ack <= 1'b1; end
        4'd1: begin p1_dout <= {w, cap_buf[2], cap_buf[1], cap_buf[0]}; p1_ack <= 1'b1; end
        4'd2: begin p2_dout <= {w, cap_buf[6], cap_buf[5], cap_buf[4], cap_buf[3], cap_buf[2], cap_buf[1], cap_buf[0]}; p2_ack <= 1'b1; end
        4'd3: begin p3_dout <= {w, cap_buf[2], cap_buf[1], cap_buf[0]}; p3_ack <= 1'b1; end
        4'd4: begin p4_dout <= {w, cap_buf[6], cap_buf[5], cap_buf[4], cap_buf[3], cap_buf[2], cap_buf[1], cap_buf[0]}; p4_ack <= 1'b1; end
        4'd5: begin p5_dout <= {w, cap_buf[2], cap_buf[1], cap_buf[0]}; p5_ack <= 1'b1; end
        4'd6: begin p6_dout <= w; p6_ack <= 1'b1; end
        4'd7: begin p7_dout <= {w, cap_buf[6], cap_buf[5], cap_buf[4], cap_buf[3], cap_buf[2], cap_buf[1], cap_buf[0]}; p7_ack <= 1'b1; end
        default: ;
    endcase
endtask

always @(posedge clk) begin
    cmd   <= CMD_NOP;
    dq_oe <= 1'b0;

    if (ack_stretch != 0) ack_stretch <= ack_stretch - 1'd1;
    else begin
        p0_ack <= 1'b0; p1_ack <= 1'b0; p2_ack <= 1'b0; p3_ack <= 1'b0;
        p4_ack <= 1'b0; p5_ack <= 1'b0; p6_ack <= 1'b0; p7_ack <= 1'b0; wr_ack <= 1'b0;
    end

    if (init) begin
        init_cnt <= 16'hffff;
        ready    <= 1'b0;
        state    <= ST_IDLE;
        ref_pend <= 1'b0;
        ref_cnt  <= 10'd0;
        row_open <= 1'b0;
        open_bank <= 2'b00;
        open_row <= 13'd0;
        reuse_open_write_row <= 1'b0;
        pre_cnt  <= 2'd0;
        dqm      <= 2'b11;
        cl_pipe  <= 4'b0000;
        ack_stretch <= 0;
        p2_starve <= 3'd0;
    end
    else if (!ready) begin
        init_cnt <= init_cnt - 1'd1;
        dqm      <= 2'b11;
        case (init_cnt)
            16'h0400: begin cmd <= CMD_PRE; SDRAM_A[10] <= 1'b1; end
            16'h03c0, 16'h0380, 16'h0340, 16'h0300,
            16'h02c0, 16'h0280, 16'h0240, 16'h0200: cmd <= CMD_REF;
            16'h00a0: begin
                cmd      <= CMD_MRS;
                SDRAM_BA <= 2'b00;
                SDRAM_A  <= 13'b000_0_00_010_0_000; // CL2, sequential, burst 1
            end
            16'h0001: ready <= 1'b1;
            default: ;
        endcase
    end
    else begin
        dqm <= 2'b00;
        ref_cnt <= ref_cnt + 1'd1;
        if (ref_cnt == 10'd760) begin ref_cnt <= 0; ref_pend <= 1'b1; end

        cl_pipe <= {cl_pipe[2:0], 1'b0};
        if (cl_pipe[3]) begin
            cap_buf[rd_captured[2:0]] <= dq_in;
            rd_captured <= rd_captured + 1'd1;
            if (rd_captured + 1'd1 == rd_total) begin
                deliver(dq_in);
                ack_stretch <= 2'd1;
            end
        end

        case (state)
        ST_IDLE: begin
            if (ref_pend && cl_pipe == 0) begin
                cmd <= CMD_PRE; SDRAM_A[10] <= 1'b1;
                row_open <= 1'b0;
                refw_cnt <= 3'd1;
                state <= ST_PRE_REF;
            end
            else if (wr_pend | read_valid) begin
                logic [24:1] a;
                if (wr_pend) begin grant <= 4'd8; a = wr_addr_p; rd_total <= 4'd1; is_write <= 1'b1; end
                else begin
                    grant <= read_grant;
                    is_write <= 1'b0;
                    if (read_grant == 4'd2) p2_starve <= 3'd0;
                    else if (p2_pend && p2_starve != 3'd7) p2_starve <= p2_starve + 3'd1;
                    case (read_grant)
                        4'd0: begin a = {p0_addr_p, 2'b00};  rd_total <= 4'd4; end
                        4'd1: begin a = {p1_addr_p, 2'b00};  rd_total <= 4'd4; end
                        4'd2: begin a = {p2_addr_p, 3'b000}; rd_total <= 4'd8; end
                        4'd3: begin a = {p3_addr_p, 2'b00};  rd_total <= 4'd4; end
                        4'd4: begin a = {p4_addr_p, 3'b000}; rd_total <= 4'd8; end
                        4'd5: begin a = {p5_addr_p, 2'b00};  rd_total <= 4'd4; end
                        4'd7: begin a = {p7_addr_p, 3'b000}; rd_total <= 4'd8; end
                        default: begin a = p6_addr_p;        rd_total <= 4'd1; end
                    endcase
                end
                xfer_addr <= a;
                reuse_open_write_row <= wr_pend && row_open &&
                                        a[24:23] == open_bank && a[22:10] == open_row;
                din_r <= wr_din_p;
                be_r  <= wr_be_p;
                rd_issued   <= 0;
                rd_captured <= 0;
                state <= ST_DISPATCH;
            end
        end

        ST_DISPATCH: begin
            if (reuse_open_write_row) state <= ST_WR;
            else if (row_open) begin
                cmd <= CMD_PRE; SDRAM_A[10] <= 1'b1;
                row_open <= 1'b0;
                pre_cnt <= 2'd1;
                state <= ST_PRE_XFER;
            end
            else state <= ST_ACT;
        end

        ST_PRE_XFER: begin
            if (pre_cnt == 0) state <= ST_ACT;
            else pre_cnt <= pre_cnt - 1'd1;
        end

        ST_ACT: begin
            cmd       <= CMD_ACT;
            SDRAM_BA  <= xfer_addr[24:23];
            SDRAM_A   <= xfer_addr[22:10];
            open_bank <= xfer_addr[24:23];
            open_row  <= xfer_addr[22:10];
            row_open  <= 1'b1;
            state     <= ST_RCD1;
        end
        ST_RCD1: state <= ST_RCD2;
        ST_RCD2: state <= is_write ? ST_WR : ST_RD;

        ST_WR: begin
            cmd      <= CMD_WRITE;
            SDRAM_BA <= xfer_addr[24:23];
            SDRAM_A  <= {2'b00, 1'b0, xfer_addr[10:1]};
            dq_out   <= din_r;
            dq_oe    <= 1'b1;
            dqm      <= ~be_r;
            wrrc_cnt <= 3'd2;
            state    <= ST_WRRC;
        end
        ST_WRRC: begin
            if (wrrc_cnt == 3'd2) begin wr_ack <= 1'b1; ack_stretch <= 2'd1; end
            if (wrrc_cnt == 0) state <= ST_IDLE;
            else wrrc_cnt <= wrrc_cnt - 1'd1;
        end

        ST_RD: begin
            cmd      <= CMD_READ;
            SDRAM_BA <= xfer_addr[24:23];
            SDRAM_A  <= {2'b00, (rd_issued + 1'd1 == rd_total) ? 1'b1 : 1'b0, xfer_addr[10:1]};
            cl_pipe[0] <= 1'b1;
            xfer_addr[10:1] <= xfer_addr[10:1] + 1'd1;
            rd_issued <= rd_issued + 1'd1;
            if (rd_issued + 1'd1 == rd_total) begin
                row_open <= 1'b0;
                state <= ST_RDW;
            end
        end
        ST_RDW: if (cl_pipe == 0) state <= ST_IDLE;

        ST_PRE_REF: begin
            if (refw_cnt == 0) begin
                cmd      <= CMD_REF;
                row_open <= 1'b0;
                ref_pend <= 1'b0;
                refw_cnt <= 3'd6;
                state    <= ST_REFW;
            end
            else refw_cnt <= refw_cnt - 1'd1;
        end
        ST_REFW: begin
            if (refw_cnt == 0) state <= ST_IDLE;
            else refw_cnt <= refw_cnt - 1'd1;
        end
        default: state <= ST_IDLE;
        endcase
    end
end
endmodule
