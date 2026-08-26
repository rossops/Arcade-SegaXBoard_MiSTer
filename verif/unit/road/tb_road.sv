`timescale 1ns/1ps
// Standalone 315-5275 test: road RAM buffer (roadbuf.hex, 2048 words), road
// ROM (roadrom.hex) and control (+ctl=N); renders one frame and dumps every
// displayed pixel's {bg_v, bg_idx, fg_v, fg_idx} to road.txt.
module tb_road;
reg clk = 0; always #10 clk = ~clk;
reg reset = 1;
wire ce_pix, hb, vb, hs, vs, v0, line_start, vbl_irq, latch_pulse;
wire [8:0] hcnt, vcnt;
xb_video_timing timing(.clk(clk), .reset(reset), .ce_pix(ce_pix), .hcnt(hcnt), .vcnt(vcnt),
    .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs), .v0(v0), .line_start(line_start),
    .vbl_irq(vbl_irq), .latch_pulse(latch_pulse));
wire [10:0] ram_addr; wire [15:0] ram_q;
wire [15:0] rom_addr0, rom_addr1; wire [7:0] rom_q0, rom_q1;
xb_dpram #(.AW(11)) roadram(.clk(clk), .a_addr(11'd0), .a_din(16'd0), .a_be(2'd0), .a_we(1'b0), .a_dout(),
    .b_clk(clk), .b_addr(ram_addr), .b_dout(ram_q));
// road ROM in a stub SDRAM (roadrom.hex, 64 KB at SDR_ROAD_BASE): the
// prefetch module reads it as 128-bit bursts, a few clocks of latency each
reg  [7:0] rom [0:65535];
wire        rom_fetch, rom_ready; wire [7:0] rom_line0, rom_line1;
wire        sdr_req, sdr_ack; wire [24:4] sdr_addr; reg [127:0] sdr_dout; reg sdr_ack_r = 0; reg sdr_req_d = 0; reg [2:0] sdr_lat = 0;
assign sdr_ack = sdr_ack_r;
integer bi;
always @(posedge clk) begin
    sdr_req_d <= sdr_req; sdr_ack_r <= 0;
    if (sdr_req && !sdr_req_d) sdr_lat <= 3'd5;
    else if (sdr_lat != 0) begin
        sdr_lat <= sdr_lat - 3'd1;
        if (sdr_lat == 3'd1) begin
            for (bi = 0; bi < 16; bi = bi + 1) sdr_dout[bi*8 +: 8] <= rom[{sdr_addr, 4'd0} - xb_pkg::SDR_ROAD_BASE + bi];
            sdr_ack_r <= 1;
        end
    end
end
xb_roadrom roadrom(.clk(clk), .reset(reset), .fetch(rom_fetch), .line0(rom_line0), .line1(rom_line1), .ready(rom_ready),
    .rd_addr0(rom_addr0), .rd_addr1(rom_addr1), .rd_q0(rom_q0), .rd_q1(rom_q1),
    .sdr_req(sdr_req), .sdr_addr(sdr_addr), .sdr_dout(sdr_dout), .sdr_ack(sdr_ack));
integer ctl_i;
wire bg_v, fg_v; wire [12:0] bg_idx, fg_idx;
xb_road_5275 dut(.clk(clk), .reset(reset), .line_start(line_start), .vcnt(vcnt), .ce_pix(ce_pix), .hcnt(hcnt),
    .control(ctl_i[2:0]), .ram_addr(ram_addr), .ram_q(ram_q), .rom_addr0(rom_addr0), .rom_addr1(rom_addr1),
    .rom_q0(rom_q0), .rom_q1(rom_q1), .rom_fetch(rom_fetch), .rom_line0(rom_line0), .rom_line1(rom_line1), .rom_ready(rom_ready),
    .bg_v(bg_v), .bg_idx(bg_idx), .fg_v(fg_v), .fg_idx(fg_idx));
integer fd, frames = 0;
reg vb_d = 0, ce_d = 0; reg [8:0] h_d;
initial begin
    if (!$value$plusargs("ctl=%d", ctl_i)) ctl_i = 0;
    $readmemh("roadbuf.hex", roadram.mem);
    $readmemh("roadrom.hex", rom);
    fd = $fopen("road.txt", "w");
    repeat (4) @(posedge clk); reset = 0;
end
always @(posedge clk) begin
    ce_d <= ce_pix; h_d <= hcnt; vb_d <= vb;
    if (vb && !vb_d) begin frames = frames + 1; if (frames == 3) begin $fclose(fd); $finish; end end
    if (ce_d && frames == 2 && !vb && !hb && h_d < 320)
        $fwrite(fd, "%0d %0d %0d %04x %0d %04x\n", vcnt, h_d, bg_v, bg_idx, fg_v, fg_idx);
end
endmodule
