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
xb_roadrom roadrom(.clk(clk), .wr(1'b0), .wr_addr(16'd0), .wr_data(8'd0),
    .rd_addr0(rom_addr0), .rd_addr1(rom_addr1), .rd_q0(rom_q0), .rd_q1(rom_q1));
integer ctl_i;
wire bg_v, fg_v; wire [12:0] bg_idx, fg_idx;
xb_road_5275 dut(.clk(clk), .reset(reset), .line_start(line_start), .vcnt(vcnt), .ce_pix(ce_pix), .hcnt(hcnt),
    .control(ctl_i[2:0]), .ram_addr(ram_addr), .ram_q(ram_q), .rom_addr0(rom_addr0), .rom_addr1(rom_addr1),
    .rom_q0(rom_q0), .rom_q1(rom_q1), .bg_v(bg_v), .bg_idx(bg_idx), .fg_v(fg_v), .fg_idx(fg_idx));
integer fd, frames = 0;
reg vb_d = 0, ce_d = 0; reg [8:0] h_d;
initial begin
    if (!$value$plusargs("ctl=%d", ctl_i)) ctl_i = 0;
    $readmemh("roadbuf.hex", roadram.mem);
    $readmemh("roadrom.hex", roadrom.rom);
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
