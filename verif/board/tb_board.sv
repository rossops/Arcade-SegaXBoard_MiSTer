//============================================================================
//  Board simulation top (Verilator). Clocks come from the C++ driver.
//  Writes the program-fetch address streams of both 68000s to trace files
//  and one PPM per frame.
//============================================================================
`timescale 1ns/1ps
import xb_pkg::*;

module tb_board (
    input clk_sys,
    input clk_ram,
    input reset,
    input [31:0] max_frames,
    output reg [31:0] frame
);

board_desc_t desc;
initial begin
    desc = '0;
    desc.game_id = 8'd0; desc.road_priority = 1'b0; desc.sprite_banks = 8'd8;
    desc.pcm_bankmask = 8'h70; desc.has_throttle = 1'b1;
end

wire p0_req, p1_req, p2_req, p3_req, p4_req, p5_req, p6_req, p3_urgent, p4_urgent;
wire p0_ack, p1_ack, p2_ack, p3_ack, p4_ack, p5_ack, p6_ack, wr_ack, sdr_ready;
wire [24:3] p0_addr, p1_addr, p3_addr, p5_addr;
wire [24:4] p2_addr, p4_addr;
wire [24:1] p6_addr;
wire [63:0] p0_dout, p1_dout, p3_dout, p5_dout;
wire [127:0] p2_dout, p4_dout;
wire [15:0] p6_dout;

sdram_model sdram (
    .clk(clk_ram), .init(reset), .ready(sdr_ready),
    .wr_req(1'b0), .wr_addr(24'd0), .wr_din(16'd0), .wr_be(2'd0), .wr_ack(wr_ack),
    .p0_req(p0_req), .p0_addr(p0_addr), .p0_dout(p0_dout), .p0_ack(p0_ack),
    .p1_req(p1_req), .p1_addr(p1_addr), .p1_dout(p1_dout), .p1_ack(p1_ack),
    .p2_req(p2_req), .p2_addr(p2_addr), .p2_dout(p2_dout), .p2_ack(p2_ack),
    .p3_req(p3_req), .p3_addr(p3_addr), .p3_dout(p3_dout), .p3_ack(p3_ack), .p3_urgent(p3_urgent),
    .p4_req(p4_req), .p4_addr(p4_addr), .p4_dout(p4_dout), .p4_ack(p4_ack), .p4_urgent(p4_urgent),
    .p5_req(p5_req), .p5_addr(p5_addr), .p5_dout(p5_dout), .p5_ack(p5_ack),
    .p6_req(p6_req), .p6_addr(p6_addr), .p6_dout(p6_dout), .p6_ack(p6_ack)
);

wire [7:0] r, g, b;
wire ce_pix, hs, vs, hb, vb;
wire signed [15:0] al, ar;
wire [23:1] tm_addr, ts_addr; wire tm_start, ts_start; wire [2:0] tm_fc, ts_fc;

xb_core core (
    .clk_sys(clk_sys), .clk_ram(clk_ram), .reset(reset), .pause(1'b0), .board_desc(desc),
    .p0_req(p0_req), .p0_addr(p0_addr), .p0_dout(p0_dout), .p0_ack(p0_ack),
    .p1_req(p1_req), .p1_addr(p1_addr), .p1_dout(p1_dout), .p1_ack(p1_ack),
    .p2_req(p2_req), .p2_addr(p2_addr), .p2_dout(p2_dout), .p2_ack(p2_ack),
    .p3_req(p3_req), .p3_addr(p3_addr), .p3_dout(p3_dout), .p3_ack(p3_ack), .p3_urgent(p3_urgent),
    .p4_req(p4_req), .p4_addr(p4_addr), .p4_dout(p4_dout), .p4_ack(p4_ack), .p4_urgent(p4_urgent),
    .p5_req(p5_req), .p5_addr(p5_addr), .p5_dout(p5_dout), .p5_ack(p5_ack),
    .p6_req(p6_req), .p6_addr(p6_addr), .p6_dout(p6_dout), .p6_ack(p6_ack),
    .p1_buttons(16'd0), .adc_x(8'h80), .adc_y(8'h80), .adc_throttle(8'h80),
    .dsw_a(8'hFF), .dsw_b(8'hFD), .service(1'b0), .test(1'b0), .coin1(1'b0), .coin2(1'b0),
    .r(r), .g(g), .b(b), .ce_pix(ce_pix), .hs(hs), .vs(vs), .hb(hb), .vb(vb),
    .audio_l(al), .audio_r(ar),
    .trace_main_addr(tm_addr), .trace_main_start(tm_start), .trace_main_fc(tm_fc),
    .trace_sub_addr(ts_addr), .trace_sub_start(ts_start), .trace_sub_fc(ts_fc)
);

// ---- traces
//  trace_*_rtl.txt : program-space word fetches (FC = 2 user / 6 supervisor)
//  trace_*_pc.txt  : executed instructions: the PC when fx68k moves IR to
//                    IRD (instruction start). fx68k's PC register then holds
//                    instruction address + 4 (two prefetched words).
integer fm, fs, fmp, fsp, fppm;
initial begin
    fm  = $fopen("trace_main_rtl.txt", "w");
    fs  = $fopen("trace_sub_rtl.txt", "w");
    fmp = $fopen("trace_main_pc.txt", "w");
    fsp = $fopen("trace_sub_pc.txt", "w");
    frame = 0;
end
// Instruction addresses follow fx68k's prefetch queue: the word captured
// into Irc (xToIrc & enPhi2) comes from address eab; Ir <= Irc and
// Ird <= Ir shift the matching address along, so at Ird load the queued
// address is exactly the executing instruction's address.
`define CPU_TRACE(pfx, cpu, fh) \
reg [23:1] pfx``_a_irc, pfx``_a_ir, pfx``_a_ird; \
reg [23:1] pfx``_last; \
always @(posedge clk_sys) begin \
    if (reset) begin pfx``_a_irc <= 0; pfx``_a_ir <= 0; pfx``_a_ird <= 0; pfx``_last <= 23'h7fffff; end \
    else begin \
        if (cpu.excUnit.dataIo.xToIrc && cpu.enPhi2) pfx``_a_irc <= cpu.eab; \
        if (cpu.enT1) begin \
            if (cpu.Nanod.Ir2Ird) begin \
                pfx``_a_ird <= pfx``_a_ir; \
                if (pfx``_a_ir != pfx``_last) begin $fwrite(fh, "%06x\n", {pfx``_a_ir, 1'b0}); pfx``_last <= pfx``_a_ir; end \
            end \
            else if (cpu.microLatch[0]) pfx``_a_ir <= pfx``_a_irc; \
        end \
    end \
end
`CPU_TRACE(mt, core.main_cpu.cpu, fmp)
`CPU_TRACE(st, core.sub_cpu.cpu, fsp)
always @(posedge clk_sys) begin
    if (!reset) begin
        if (tm_start && tm_fc[1] && core.m_rd) $fwrite(fm, "%06x\n", {tm_addr, 1'b0});
        if (ts_start && ts_fc[1] && core.s_rd) $fwrite(fs, "%06x\n", {ts_addr, 1'b0});
    end
end

// ---- RAM dump at +dumpframe=N (start of that frame's vblank)
integer dumpframe = -1;
initial begin if (!$value$plusargs("dumpframe=%d", dumpframe)) dumpframe = -1; end
task automatic dump_ram(input string name, input integer words, input integer which);
    integer fd, k;
    fd = $fopen(name, "wb");
    for (k = 0; k < words; k = k + 1) begin
        case (which)
            0: $fwrite(fd, "%c%c", core.tileram.mem[k][7:0], core.tileram.mem[k][15:8]);
            1: $fwrite(fd, "%c%c", core.textram.mem[k][7:0], core.textram.mem[k][15:8]);
            default: $fwrite(fd, "%c%c", core.palette.mem[k][7:0], core.palette.mem[k][15:8]);
        endcase
    end
    $fclose(fd);
endtask

// ---- frame dump: one PPM per frame (320x224)
reg vb_d;
reg [8:0] px, py;
reg ppm_open;
string fname;
always @(posedge clk_sys) begin
    vb_d <= vb;
    if (vb && !vb_d) begin
        if (frame == dumpframe) begin
            dump_ram("rtl_tileram.bin", 32768, 0);
            dump_ram("rtl_textram.bin", 2048, 1);
            dump_ram("rtl_paletteram.bin", 8192, 2);
            $display("dumped RAMs at frame %0d", frame);
        end
        if (ppm_open) begin $fclose(fppm); ppm_open <= 0; end
        frame <= frame + 1;
        if (frame + 1 == max_frames) $finish;
    end
    if (!vb && vb_d) begin
        $sformat(fname, "frame_%04d.ppm", frame);
        fppm = $fopen(fname, "wb");
        $fwrite(fppm, "P6\n320 224\n255\n");
        ppm_open <= 1;
    end
    if (ce_pix && !hb && !vb && ppm_open) $fwrite(fppm, "%c%c%c", r, g, b);
end
endmodule
