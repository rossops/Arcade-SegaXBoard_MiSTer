`timescale 1ns/1ps
// Smoke test: 400x262 raster, vblank irq is a one-line pulse at line 223,
// latch pulse at 261, frame period = 400*262*8 clk_sys = 838400 clocks
// (59.637 Hz at 50 MHz, matching MAME's 59.6368 Hz).
module tb_timing;
reg clk = 0; always #10 clk = ~clk;
reg reset = 1;
wire ce_pix, hb, vb, hs, vs, v0, line_start, vbl_irq, latch_pulse;
wire [8:0] hcnt, vcnt;
xb_video_timing dut(.clk(clk), .reset(reset), .ce_pix(ce_pix), .hcnt(hcnt), .vcnt(vcnt),
    .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs), .v0(v0), .line_start(line_start),
    .vbl_irq(vbl_irq), .latch_pulse(latch_pulse));
integer clocks = 0, lines = 0, irq_lines = 0, latches = 0, errors = 0;
integer t_frame0 = -1, t_frame1 = -1;
reg vbl_d = 0;
initial begin
    repeat (4) @(posedge clk); reset = 0;
    // wait for first frame start
    @(posedge clk); while (!(line_start && vcnt == 0)) @(posedge clk);
    t_frame0 = $time;
    forever begin
        @(posedge clk);
        clocks = clocks + 1;
        if (line_start) begin
            lines = lines + 1;
            if (vcnt == 0 && t_frame1 < 0 && lines > 1) begin
                t_frame1 = $time;
                if (lines != 262) begin $display("FAIL lines/frame=%0d", lines); errors++; end
                if ((t_frame1 - t_frame0) != 400*262*8*20) begin
                    $display("FAIL frame period %0d ns", t_frame1 - t_frame0); errors++; end
                $display("frame: %0d lines, %0d ns, vbl_irq lines=%0d, latches=%0d",
                         lines, t_frame1 - t_frame0, irq_lines, latches);
                if (irq_lines != 1) begin $display("FAIL vbl_irq lines=%0d", irq_lines); errors++; end
                if (latches != 1) begin $display("FAIL latches=%0d", latches); errors++; end
                if (errors == 0) $display("PASS"); else $display("FAILED");
                $finish;
            end
            if (vbl_irq) begin
                irq_lines = irq_lines + 1;
                if (vcnt != 223) begin $display("FAIL vbl_irq at line %0d", vcnt); errors++; end
            end
        end
        if (latch_pulse) begin
            latches = latches + 1;
            if (vcnt != 261) begin $display("FAIL latch at line %0d", vcnt); errors++; end
        end
        if (ce_pix && hcnt < 320 && vcnt < 224 && (hb || vb)) begin
            $display("FAIL blank asserted in active area h=%0d v=%0d", hcnt, vcnt); errors++; end
        if (ce_pix && (hcnt >= 320) && !hb && hcnt != 0) begin
            $display("FAIL hblank missing at h=%0d", hcnt); errors++; end
    end
end
endmodule
