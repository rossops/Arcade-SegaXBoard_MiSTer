`timescale 1ns/1ps
// Standalone 315-5211A test: render one sprite list (spritelist.hex) with the
// real sprite ROM (sprite.hex, SDRAM 16-bit word image) through xb_fb_if and
// the DDRAM model, then dump the framebuffer as fb.txt (one hex word per
// pixel, 512 x 256, buffer 1 = the render target after reset).
module tb_sprite;
reg clk = 0; always #5 clk = ~clk;
reg reset = 1;

// sprite RAM (renderer bank only)
// xb_dpram port B: one output register after the (already registered) address
reg [15:0] sram [0:2047];
wire [10:0] sram_addr;
reg [15:0] sram_q;
always @(posedge clk) sram_q <= sram[sram_addr];

// sprite ROM: served through the p2 burst port
reg [15:0] rom [0:2097151];   // 4 MB slot / 2
wire        rom_req; wire [24:4] rom_addr; reg [127:0] rom_dout; reg rom_ack;
reg  [3:0] rom_lat;
reg        rom_pend; reg [24:4] rom_a;
reg        req_d;
always @(posedge clk) begin
    req_d <= rom_req; rom_ack <= 0;
    if (rom_req && !req_d) begin rom_pend <= 1; rom_a <= rom_addr; rom_lat <= 4'd9; end
    else if (rom_pend) begin
        if (rom_lat != 0) rom_lat <= rom_lat - 1;
        else begin
            rom_dout <= {rom[{rom_a - 21'h20000, 3'd7}], rom[{rom_a - 21'h20000, 3'd6}], rom[{rom_a - 21'h20000, 3'd5}], rom[{rom_a - 21'h20000, 3'd4}],
                         rom[{rom_a - 21'h20000, 3'd3}], rom[{rom_a - 21'h20000, 3'd2}], rom[{rom_a - 21'h20000, 3'd1}], rom[{rom_a - 21'h20000, 3'd0}]};
            rom_ack <= 1; rom_pend <= 0;
        end
    end
end

wire        DDRAM_BUSY, DDRAM_DOUT_READY, DDRAM_RD, DDRAM_WE;
wire  [7:0] DDRAM_BURSTCNT, DDRAM_BE;
wire [28:0] DDRAM_ADDR;
wire [63:0] DDRAM_DOUT, DDRAM_DIN;
ddram_model ddram (.clk(clk), .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
    .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
    .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE));

wire fbw_start, fbw_valid, fbw_end, fbw_busy, fbe_ack, fbr_ack;
wire fbw_dup; wire [8:0] fbw_dup_y;
wire [1:0] fbw_buf, fbe_buf, fbr_buf;
wire [9:0] fbw_x; wire [3:0] fbw_lanes; wire [8:0] fbw_y, fbe_y, fbr_y;
reg hires; initial hires = $test$plusargs("hires");
wire [15:0] fbw_pix, fbr_pix;
wire fbe_req, fbr_req;
xb_fb_if #(.FB_BASE(32'h3000_0000)) fb (
    .clk(clk), .rst(reset), .hires(hires),
    .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
    .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
    .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
    .wr_start(fbw_start), .wr_buf(fbw_buf), .wr_x(fbw_x), .wr_lanes(fbw_lanes), .wr_y(fbw_y),
    .wr_valid(fbw_valid), .wr_pix(fbw_pix), .wr_end(fbw_end), .wr_dup(fbw_dup), .wr_dup_y(fbw_dup_y), .wr_shadow(1'b0), .wr_busy(fbw_busy),
    .er_req(fbe_req), .er_buf(fbe_buf), .er_y(fbe_y), .er_ack(fbe_ack),
    .rd_req(fbr_req), .rd_buf(fbr_buf), .rd_y(fbr_y), .rd_ack(fbr_ack),
    .rd_x(10'd0), .rd_pix(fbr_pix), .rd_pub_ok(1'b1));

reg start_req = 0, vbl_start = 0, line_start = 0;
wire disp_buf;
xb_sprite_5211 dut (
    .clk(clk), .reset(reset), .num_banks(8'd8),
    .start_req(start_req), .vbl_start(vbl_start), .vcnt(9'd0), .line_start(line_start),
    .hires(hires), .oline(1'b0),
    .sram_addr(sram_addr), .sram_q(sram_q),
    .rom_req(rom_req), .rom_addr(rom_addr), .rom_dout(rom_dout), .rom_ack(rom_ack),
    .fb_wr_start(fbw_start), .fb_wr_buf(fbw_buf), .fb_wr_x(fbw_x), .fb_wr_lanes(fbw_lanes), .fb_wr_y(fbw_y),
    .fb_wr_valid(fbw_valid), .fb_wr_pix(fbw_pix), .fb_wr_end(fbw_end), .fb_wr_dup(fbw_dup), .fb_wr_dup_y(fbw_dup_y), .fb_wr_busy(fbw_busy),
    .fb_er_req(fbe_req), .fb_er_buf(fbe_buf), .fb_er_y(fbe_y), .fb_er_ack(fbe_ack),
    .fb_rd_req(fbr_req), .fb_rd_buf(fbr_buf), .fb_rd_y(fbr_y), .fb_rd_ack(fbr_ack),
    .disp_buf(disp_buf));

integer fd, fr, x, y, w, cyc;
integer hist [0:15]; integer pixv, pix2, busyw;
integer run_pix = 0;
reg [9:0] run_x0r, run_xer;
always @(posedge clk) begin
    if (fbw_start) begin run_pix = 0; run_x0r = 10'd1023; run_xer = 10'd0;
        $fwrite(fr, "start y=%0d rowaddr=%h yacc=%h\n", fbw_y, dut.rowaddr, dut.yacc); end
    if (dut.rs == 6 && dut.burst_hit) $fwrite(fr, "  word %h = %h (hit)\n", dut.want_addr, dut.word_sel);
    if (rom_ack) $fwrite(fr, "  fetch %h -> %h\n", dut.want_addr, rom_dout);
    if (fbw_valid) begin
        run_pix = run_pix + 1;
        if (fbw_x < run_x0r) run_x0r = fbw_x;
        if (fbw_x > run_xer) run_xer = fbw_x;
    end
    if (fbw_end) $fwrite(fr, "y=%0d pix=%0d x0=%0d xe=%0d\n", fbw_y, run_pix, run_x0r, run_xer);
end
initial begin
    fr = $fopen("runs.txt", "w");
    $readmemh("spritelist.hex", sram);
    $readmemh("sprite.hex", rom);
    repeat (8) @(posedge clk); reset = 0;
    // preset the render target (buffer 1 after reset: ~disp_buf = 1) to 0xFFFF
    // 1x: 512x256 at +0x40000; 2x: 1024x512 at +0x100000
    for (w = 0; w < (hires ? 1024*512/4 : 512*256/4); w = w + 1)
        ddram.mem[((hires ? 32'h3010_0000 : 32'h3004_0000) >> 3) - (32'h3000_0000 >> 3) + w] = 64'hFFFF_FFFF_FFFF_FFFF;
    @(posedge clk);
    start_req = 1; @(posedge clk); start_req = 0;
    // let it render; the DUT returns to R_IDLE when the list is done
    cyc = 0;
    for (y = 0; y < 16; y = y + 1) hist[y] = 0;
    pixv = 0; pix2 = 0; busyw = 0;
    forever begin
        @(posedge clk); cyc = cyc + 1;
        hist[dut.rs] = hist[dut.rs] + 1;
        if (dut.fb_wr_valid) begin pixv = pixv + 1; if (dut.fb_wr_lanes[0] + dut.fb_wr_lanes[1] + dut.fb_wr_lanes[2] + dut.fb_wr_lanes[3] > 1) pix2 = pix2 + 1; end
        if (dut.rs == 7 && fbw_busy) busyw = busyw + 1;
        if (cyc > 200 && dut.rs == 0 && !fbw_busy && !dut.rendering && !dut.render_pending) begin
            fd = $fopen("fb.txt", "w");
            for (y = 0; y < (hires ? 512 : 256); y = y + 1)
                for (x = 0; x < (hires ? 1024 : 512); x = x + 4) begin
                    reg [63:0] q;
                    q = hires ? ddram.mem[(32'h3010_0000 >> 3) - (32'h3000_0000 >> 3) + y*256 + x/4]
                              : ddram.mem[(32'h3004_0000 >> 3) - (32'h3000_0000 >> 3) + y*128 + x/4];
                    $fwrite(fd, "%04x %04x %04x %04x\n", q[15:0], q[31:16], q[47:32], q[63:48]);
                end
            $fclose(fd);
            $display("render done in %0d cycles", cyc);
            $display("state clocks: IDLE %0d ERASE %0d ERASEW %0d FETCH %0d FETCHW %0d DECODE %0d ROW %0d ROWWAIT %0d ROMREQ %0d ROMWAIT %0d PIX %0d ROWEND %0d NEXT %0d ROWSKIP %0d",
                hist[0], hist[1], hist[2], hist[3], hist[4], hist[5], hist[6], hist[7], hist[8], hist[9], hist[10], hist[11], hist[12], hist[13]);
            $display("pixel writes %0d (pairs %0d), ROWWAIT clocks with fb busy %0d", pixv, pix2, busyw);
            $finish;
        end
        if (cyc > 3000000) begin
            $display("TIMEOUT rs=%0d busy=%0d idx=%0d rowaddr=%h bank=%0d rom_pend=%0d rom_lat=%0d req_d=%0d rom_req=%0d rom_a=%h want=%h",
                dut.rs, fbw_busy, dut.sprite_idx, dut.rowaddr, dut.bank, rom_pend, rom_lat, req_d, rom_req, rom_a, dut.want_addr);
            $finish; end
    end
end
endmodule
