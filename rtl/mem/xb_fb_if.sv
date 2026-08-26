//============================================================================
//  Sega X Board — 315-5211A sprite framebuffer interface, forked from the
//  System 32 core's s32_fb_if (same DDR3 services). Two 512x256x16 buffers
//  at FB_BASE + buf*512*256*2; the X Board uses buffers 0 and 1 only.
//  Empty framebuffer pixel = 0xFFFF (MAME's transparent value).
//  Services (per DESIGN.md):
//    - erase_line(y):     fill line with 0xFFFF
//    - write_run(...):    pixel run writes from the sprite renderer;
//                         wr_shadow runs RMW dest &= 0x7fff instead
//                         (MAME shadow sprites clear framebuffer bit 15)
//    - read_line(y):      whole-line fetch into mixer line buffer
//  A run's untouched pixels are never written: a per-pixel valid mask
//  drives the DDR byte enables (partial head/tail words stay intact).
//  wr_busy holds the renderer off while the previous run drains.
//============================================================================

module xb_fb_if #(
    parameter [31:0] FB_BASE = 32'h3000_0000
)(
    input             clk,      // clk_ram
    input             rst,
    input             hires,    // 2x mode: 1024x512 buffers (1 MB each)

    // DDRAM (MiSTer)
    input             DDRAM_BUSY,
    output      [7:0] DDRAM_BURSTCNT,
    output     [28:0] DDRAM_ADDR,
    input      [63:0] DDRAM_DOUT,
    input             DDRAM_DOUT_READY,
    output            DDRAM_RD,
    output     [63:0] DDRAM_DIN,
    output      [7:0] DDRAM_BE,
    output            DDRAM_WE,

    // renderer write port: run of pixels, 1/clk while wvalid.
    // wr_x is PER PIXEL (absolute x) — pixels may arrive in any order and
    // with gaps (flipped sprites sweep right-to-left; clip-out punches holes)
    input             wr_start,        // begin run (latches y/buf/shadow)
    input       [1:0] wr_buf,          // buffer select
    input       [9:0] wr_x,            // x of THIS pixel (valid with wr_valid)
    input       [3:0] wr_lanes,        // lanes of word wr_x[9:2] written with wr_pix (2x pairs)
    input       [8:0] wr_y,
    input             wr_valid,        // one write this cycle
    input      [15:0] wr_pix,
    input             wr_end,
    input             wr_shadow,       // run is a shadow RMW (dest &= 0x7fff)
    output            wr_busy,         // previous run still flushing

    // erase port
    input             er_req,
    input       [1:0] er_buf,
    input       [8:0] er_y,
    output reg        er_ack,

    // line read port -> mixer
    input             rd_req,
    input       [1:0] rd_buf,
    input       [8:0] rd_y,
    output reg        rd_ack,          // line available in buffer
    input       [9:0] rd_x,            // synchronous read of fetched line
    input             rd_pub_ok,       // a completed fetch may be published at rd_x == 0
    output     [15:0] rd_pix
);

// line assembly buffer for writes: pixels land at their absolute x, a mask
// tracks which were written; flush covers [run_x0 .. run_xe] with byte
// enables from the mask (order/gap agnostic)
// Store four pixels per entry, matching one 64-bit DDR word.  The explicit
// RAM below has a 16-bit-lane write port for arbitrary-order sprite pixels and
// a synchronous 64-bit flush read port.  Keeping this out of flops removes the
// 8,192-register run buffer and its large read mux from the integrated map.
reg [1023:0] run_msk;              // which pixels this run actually wrote
reg [9:0]   run_x0, run_xe;        // min / max written x
reg [8:0]   run_y;
reg [1:0]   run_bufsel;
reg         run_active;
reg         run_shadow;
reg         run_any;               // at least one pixel written

// Two fetched lines keep producer and consumer ownership separate. DDR fills
// one bank while scanout reads the other; a completed line is published only
// at x=0, so a late or early next-line fetch cannot tear the displayed raster.
reg  [1:0] rd_lane;
reg        display_bank;
reg        fill_bank;
reg        line_ready;
wire       rd_line_publish = (rd_x == 10'd0) && line_ready && rd_pub_ok;
wire       scan_bank = rd_line_publish ? fill_bank : display_bank;

// DDR engine
typedef enum logic [3:0] { D_IDLE, D_WR_PF, D_WR, D_ER, D_RD, D_RD_W,
                           D_SH_R, D_SH_RW, D_SH_W,
                           D_WR_SKIP, D_WR_SKIP_PF, D_SH_SKIP } dstate_t;
dstate_t dst = D_IDLE;

reg [28:0] daddr;
reg [7:0]  dburst;
reg        dwe, drd;
reg [63:0] ddin;
reg [7:0]  dbe;
reg [7:0]  beat, beats;
reg [7:0]  rbeat;
reg        rd_second;               // 2x: second 128-beat half of the line
// Word currently being serviced by the run flusher.  Capturing this at the
// flush boundary keeps the active byte-enable path independent of run_x0 and
// the beat counter's add chain.
reg [7:0]  run_word_q;
wire        line_we = (dst == D_RD_W) && DDRAM_DOUT_READY;
wire [7:0]  line_waddr = rbeat;
wire [63:0] line_wdata = DDRAM_DOUT;
wire        line_we0 = line_we && !fill_bank;
wire        line_we1 = line_we &&  fill_bank;

wire [63:0] line_q0, line_q1;
xb_fb_line_ram line_ram0 (
    .clk(clk), .wr_en(line_we0), .wr_addr(line_waddr),
    .wr_data(line_wdata), .rd_addr(rd_x[9:2]), .rd_q(line_q0)
);
xb_fb_line_ram line_ram1 (
    .clk(clk), .wr_en(line_we1), .wr_addr(line_waddr),
    .wr_data(line_wdata), .rd_addr(rd_x[9:2]), .rd_q(line_q1)
);

`ifdef SIMULATION
always @(posedge clk) begin
    if (!rst && line_we && (fill_bank == display_bank))
        $fatal(1, "sprite line fill attempted to overwrite display bank");
    if (!rst && line_ready && line_we)
        $fatal(1, "sprite line fill continued after completion");
end
`endif

wire [63:0] rd_word = scan_bank ? line_q1 : line_q0;
assign rd_pix = (rd_lane == 2'd0) ? rd_word[15:0]  :
                (rd_lane == 2'd1) ? rd_word[31:16] :
                (rd_lane == 2'd2) ? rd_word[47:32] : rd_word[63:48];

always @(posedge clk) begin
    rd_lane <= rd_x[1:0];
end

function automatic [28:0] pix_addr(input [1:0] buf_i, input [8:0] y,
                                   input [7:0] x_word);
    // 64-bit word address for DDRAM: byte addr / 8. 1x: 128 words per line,
    // 256 lines per buffer; 2x: 256 words per line, 512 lines per buffer.
    if (hires)
        pix_addr = FB_BASE[31:3] + {{10{1'b0}}, buf_i, 17'b0}
                                    + {{12{1'b0}}, y, 8'b0}
                                    + {21'b0, x_word};
    else
        pix_addr = FB_BASE[31:3] + {{12{1'b0}}, buf_i, 15'b0}
                                    + {{14{1'b0}}, y[7:0], 7'b0}
                                    + {21'b0, x_word};
endfunction

// Synchronous run-buffer read pipeline.  D_WR_PF consumes the base word
// fetched while D_IDLE accepted the flush.  Thereafter the RAM looks one word
// ahead while DDR is stalled, or two words ahead on an accepted write; at the
// accepting edge q still contains the immediately following word.  Thus the
// registered RAM sustains one DDR word per accepted clock without allowing a
// stalled request's data to change.
wire [7:0] run_word_base = run_word_q;
wire [7:0] run_cur_word  = run_word_q;
wire [7:0] run_next_word = run_word_q + 8'd1;
wire [7:0] run_ram_raddr = (dst == D_IDLE)       ? run_x0[9:2] :
                            (dst == D_WR_PF)      ? run_next_word :
                            (dst == D_WR_SKIP)    ? run_cur_word :
                            (dst == D_WR_SKIP_PF) ? run_next_word :
                            (dst == D_WR)         ? run_cur_word
                                                     + (DDRAM_BUSY ? 8'd1 : 8'd2) :
                                                    run_cur_word;

wire [3:0] run_base_mask = run_msk[{run_word_base, 2'b00} +: 4];
wire [3:0] run_cur_mask  = run_msk[{run_cur_word,  2'b00} +: 4];
wire [3:0] run_next_mask = run_msk[{run_next_word, 2'b00} +: 4];
wire [7:0] run_base_be = {{2{run_base_mask[3]}}, {2{run_base_mask[2]}},
                           {2{run_base_mask[1]}}, {2{run_base_mask[0]}}};
wire [7:0] run_cur_be = {{2{run_cur_mask[3]}}, {2{run_cur_mask[2]}},
                          {2{run_cur_mask[1]}}, {2{run_cur_mask[0]}}};
wire [7:0] run_next_be = {{2{run_next_mask[3]}}, {2{run_next_mask[2]}},
                           {2{run_next_mask[1]}}, {2{run_next_mask[0]}}};
// Shadow writes only the high byte of each valid lane (bit 15 lives there).
wire [7:0] run_cur_shadow_be = {run_cur_mask[3], 1'b0,
                                 run_cur_mask[2], 1'b0,
                                 run_cur_mask[1], 1'b0,
                                 run_cur_mask[0], 1'b0};

wire [63:0] run_ram_q;
xb_fb_run_ram run_ram (
    .clk(clk),
    .wr_en(wr_valid && run_active),
    .wr_addr(wr_x[9:2]),
    .wr_lanes(wr_lanes),
    .wr_data(wr_pix),
    .rd_addr(run_ram_raddr),
    .rd_q(run_ram_q)
);

assign DDRAM_ADDR     = daddr;
assign DDRAM_BURSTCNT = dburst;
assign DDRAM_WE       = dwe;
assign DDRAM_RD       = drd;
assign DDRAM_DIN      = ddin;
assign DDRAM_BE       = dbe;

reg flush_req;

// Scanout has a fixed deadline; a completed sprite run may remain queued until
// a pending display-line fetch has been launched.  Keep acceptance explicit so
// deferring the flush cannot discard it.
wire erase_pending = er_req && !er_ack;
// Do not reuse a completed fill bank until the raster boundary publishes it.
wire read_pending  = rd_req && !rd_ack && !line_ready;
wire flush_accept  = (dst == D_IDLE) && !erase_pending &&
                     !read_pending && flush_req;

// capture pixel runs (indexed by the pixel's own x)
always @(posedge clk) begin
    if (wr_start) begin
        run_x0     <= 10'd1023;
        run_xe     <= 10'd0;
        run_y      <= wr_y;
        run_bufsel <= wr_buf;
        run_shadow <= wr_shadow;
        run_active <= 1'b1;
        run_any    <= 1'b0;
        run_msk    <= 1024'b0;
    end
    if (wr_valid && run_active) begin
        // up to two lanes of one 64-bit word per write (2x pairs)
        logic [9:0] lo, hi;
        run_msk[{wr_x[9:2], 2'b00} +: 4] <= run_msk[{wr_x[9:2], 2'b00} +: 4] | wr_lanes;
        run_any <= 1'b1;
        lo = {wr_x[9:2], wr_lanes[0] ? 2'd0 : wr_lanes[1] ? 2'd1 : wr_lanes[2] ? 2'd2 : 2'd3};
        hi = {wr_x[9:2], wr_lanes[3] ? 2'd3 : wr_lanes[2] ? 2'd2 : wr_lanes[1] ? 2'd1 : 2'd0};
        if (lo < run_x0) run_x0 <= lo;
        if (hi > run_xe) run_xe <= hi;
    end
    if (flush_accept) run_active <= 1'b0;
    if (rst) run_active <= 1'b0;
end

always @(posedge clk) begin
    if (rst) flush_req <= 0;
    else if (wr_end && run_active) flush_req <= 1'b1;
    else if (flush_accept) flush_req <= 1'b0;
end

// hold the renderer off from wr_end (combinational — closes the one-cycle
// window before flush_req registers) until the flush completes
assign wr_busy = wr_end | flush_req |
                 (dst == D_WR_PF) | (dst == D_WR) |
                 (dst == D_WR_SKIP) | (dst == D_WR_SKIP_PF) |
                 (dst == D_SH_R) | (dst == D_SH_RW) | (dst == D_SH_W) |
                 (dst == D_SH_SKIP);

always @(posedge clk) begin
    if (rst) begin
        dst <= D_IDLE; dwe <= 0; drd <= 0; er_ack <= 0; rd_ack <= 0;
        run_word_q <= 8'd0;
        display_bank <= 1'b0;
        fill_bank <= 1'b1;
        line_ready <= 1'b0;
    end
    else begin
        if (rd_line_publish) begin
            display_bank <= fill_bank;
            line_ready <= 1'b0;
        end
        case (dst)
        D_IDLE: begin
            dwe <= 0; drd <= 0;
            // A line fetch is one 256-beat read and has a raster deadline; an
            // erase is up to 512 lines (2x) and can wait a line between them.
            if (read_pending) begin
                daddr  <= pix_addr(rd_buf, rd_y, 8'd0);
                dburst <= 8'd128;               // 2x: two 128-beat bursts (burstcnt is 8 bits)
                rbeat  <= 0;
                rd_second <= 1'b0;
                fill_bank <= ~display_bank;
                drd    <= 1'b1;
                dbe    <= 8'hFF;  // audit R20 PF-4: reads drive all byte lanes
                dst    <= D_RD;
            end
            else if (erase_pending) begin
                daddr  <= pix_addr(er_buf, er_y, 8'd0);
                // MiSTer recommends pipelined single writes. With burstcnt=1
                // each accepted beat may advance DDRAM_ADDR legally.
                dburst <= 8'd1;
                ddin   <= 64'hFFFF_FFFF_FFFF_FFFF;
                dbe    <= 8'hFF;
                beat   <= 0; beats <= hires ? 8'd255 : 8'd127;
                dwe    <= 1'b1;
                dst    <= D_ER;
            end
            else if (flush_req) begin
                beat  <= 0;
                beats <= (run_xe[9:2] - run_x0[9:2]);
                run_word_q <= run_x0[9:2];
                daddr <= pix_addr(run_bufsel, run_y, run_x0[9:2]);
                if (!run_any) begin
                    // fully-transparent row: nothing to flush
                end
                else if (run_shadow) begin
                    // RMW span: read word, clear bit15 of valid lanes, write
                    dburst <= 8'd1;
                    drd    <= 1'b1;
                    dbe    <= 8'hFF;  // audit R20 PF-4: reads drive all byte lanes
                    dst    <= D_SH_R;
                end
                else begin
                    dburst <= 8'd1;
                    dst    <= D_WR_PF;
                end
            end

        end
        // One synchronous-RAM prefetch cycle.  q is the base word requested
        // while the preceding D_IDLE edge accepted this flush.
        D_WR_PF: begin
            ddin <= run_ram_q;
            dbe  <= run_base_be;
            dwe  <= 1'b1;
            dst  <= D_WR;
        end
        D_ER: if (!DDRAM_BUSY) begin
            dwe <= 1'b1;
            // Erase spans the line loaded in D_IDLE (128 or 256 words).
            if (beat == beats) begin dwe <= 0; er_ack <= 1'b1; dst <= D_IDLE; end
            else begin beat <= beat + 1'd1; daddr <= daddr + 1'd1; end
        end
        D_WR: if (!DDRAM_BUSY) begin
            // The current word is no longer consumed once DWE is cleared or
            // a zero-mask word is skipped.  Keep the data register update
            // independent of the beat/mask decision so that the active
            // DDRAM write-data path does not inherit that control cone.
            ddin <= run_ram_q;
            if (beat == beats) begin dwe <= 0; dst <= D_IDLE; end
            else if (run_next_mask == 4'b0000) begin
                // Transparent/clipped holes can leave complete 64-bit words
                // empty between the run's first and last written pixels.
                // A zero-BE DDR write has no framebuffer effect, so walk the
                // mask locally instead of consuming external acceptance slots.
                beat  <= beat + 1'd1;
                run_word_q <= run_word_q + 1'd1;
                daddr <= daddr + 1'd1;
                dwe   <= 1'b0;
                dst   <= D_WR_SKIP;
            end
            else begin
                beat  <= beat + 1'd1;
                run_word_q <= run_word_q + 1'd1;
                daddr <= daddr + 1'd1;
                dbe   <= run_next_be;
                dwe   <= 1'b1;
            end
        end
        D_WR_SKIP: begin
            // No DDR request is active in this state, so mask scanning is not
            // coupled to DDRAM_BUSY. Valid words retain ascending write order.
            dwe <= 1'b0;
            if (run_cur_mask != 4'b0000) begin
                dst <= D_WR_SKIP_PF;
            end
            else if (beat == beats) begin
                dst <= D_IDLE;
            end
            else begin
                beat  <= beat + 1'd1;
                run_word_q <= run_word_q + 1'd1;
                daddr <= daddr + 1'd1;
            end
        end
        // Restore the same synchronous-RAM lookahead used by D_WR_PF. During
        // this cycle q is the selected word and the RAM prefetches its successor.
        D_WR_SKIP_PF: begin
            ddin <= run_ram_q;
            dbe  <= run_cur_be;
            dwe  <= 1'b1;
            dst  <= D_WR;
        end
        // shadow RMW loop: one 64-bit word per iteration
        D_SH_R: if (!DDRAM_BUSY) begin
            drd <= 1'b0;
            dst <= D_SH_RW;
        end
        D_SH_RW: if (DDRAM_DOUT_READY) begin
            ddin <= DDRAM_DOUT & 64'h7FFF_7FFF_7FFF_7FFF;
            dbe  <= run_cur_shadow_be;
            dwe  <= 1'b1;
            dst  <= D_SH_W;
        end
        D_SH_W: if (!DDRAM_BUSY) begin
            dwe <= 1'b0;
            if (beat == beats) dst <= D_IDLE;
            else begin
                beat   <= beat + 1'd1;
                run_word_q <= run_word_q + 1'd1;
                daddr  <= daddr + 1'd1;
                dburst <= 8'd1;
                if (run_next_mask != 4'b0000) begin
                    drd <= 1'b1;
                    dbe <= 8'hFF;  // audit R20 PF-4: reads drive all byte lanes
                    dst <= D_SH_R;
                end
                else begin
                    // Empty shadow words would read DDR and then issue a
                    // zero-BE write. Both are semantic no-ops; skip them while
                    // retaining the RMW ordering of every populated word.
                    drd <= 1'b0;
                    dst <= D_SH_SKIP;
                end
            end
        end
        D_SH_SKIP: begin
            dwe <= 1'b0;
            drd <= 1'b0;
            if (run_cur_mask != 4'b0000) begin
                dburst <= 8'd1;
                drd    <= 1'b1;
                dbe    <= 8'hFF;
                dst    <= D_SH_R;
            end
            else if (beat == beats) begin
                dst <= D_IDLE;
            end
            else begin
                beat  <= beat + 1'd1;
                run_word_q <= run_word_q + 1'd1;
                daddr <= daddr + 1'd1;
            end
        end
        D_RD: if (!DDRAM_BUSY) begin
            drd <= 1'b0;
            dst <= D_RD_W;
        end
        D_RD_W: begin
            if (DDRAM_DOUT_READY) begin
                rbeat <= rbeat + 1'd1;
                if (rbeat[6:0] == 7'd127) begin
                    if (hires && !rd_second) begin
                        // second half of the 256-word line
                        rd_second <= 1'b1;
                        daddr <= daddr + 29'd128;
                        drd   <= 1'b1;
                        dst   <= D_RD;
                    end
                    else begin
                        line_ready <= 1'b1;
                        rd_ack <= 1'b1;
                        dst <= D_IDLE;
                    end
                end
            end
        end
        default: dst <= D_IDLE;
        endcase
        // Four-phase request/acknowledge: a held request is accepted once,
        // and the acknowledge drops as soon as its producer drops request.
        if (!rd_req) rd_ack <= 1'b0;
        if (!er_req) er_ack <= 1'b0;
    end
end

endmodule

// ---------------------------------------------------------------------------
// 128 x 64 fetched-line RAM. Port A writes the complete DDR words for the
// fill bank while port B serves scanout from the independently selected bank.
// ---------------------------------------------------------------------------
module xb_fb_line_ram (
    input              clk,
    input              wr_en,
    input       [7:0]  wr_addr,
    input      [63:0]  wr_data,
    input       [7:0]  rd_addr,
    output     [63:0]  rd_q
);

`ifdef ALTERA_RESERVED_QIS
altsyncram ram (
    .clock0(clk),
    .address_a(wr_addr),
    .data_a(wr_data),
    .wren_a(wr_en),

    .clock1(clk),
    .address_b(rd_addr),
    .q_b(rd_q),

    .aclr0(1'b0),
    .aclr1(1'b0),
    .addressstall_a(1'b0),
    .addressstall_b(1'b0),
    .byteena_a(1'b1),
    .clocken0(1'b1),
    .clocken1(1'b1),
    .clocken2(1'b1),
    .clocken3(1'b1),
    .eccstatus(),
    .rden_a(1'b1),
    .rden_b(1'b1)
);
defparam
    ram.numwords_a = 256,
    ram.widthad_a = 8,
    ram.width_a = 64,
    ram.numwords_b = 256,
    ram.widthad_b = 8,
    ram.width_b = 64,
    ram.address_reg_b = "CLOCK1",
    ram.clock_enable_input_a = "BYPASS",
    ram.clock_enable_input_b = "BYPASS",
    ram.clock_enable_output_b = "BYPASS",
    ram.intended_device_family = "Cyclone V",
    ram.lpm_type = "altsyncram",
    ram.operation_mode = "DUAL_PORT",
    ram.outdata_aclr_b = "NONE",
    ram.outdata_reg_b = "UNREGISTERED",
    ram.power_up_uninitialized = "TRUE",
    ram.read_during_write_mode_mixed_ports = "DONT_CARE",
    ram.width_byteena_a = 1,
    ram.ram_block_type = "M10K";
`else
reg [63:0] mem [0:255];
reg [63:0] rd_q_r;
assign rd_q = rd_q_r;

integer __line_init;
initial begin
    rd_q_r = 64'd0;
    for (__line_init = 0; __line_init < 128; __line_init = __line_init + 1)
        mem[__line_init] = 64'd0;
end

always @(posedge clk) begin
    rd_q_r <= mem[rd_addr];
    if (wr_en)
        mem[wr_addr] <= wr_data;
end
`endif

endmodule

// ---------------------------------------------------------------------------
// 128 x 64 captured-run RAM.  Port A writes one 16-bit pixel lane per clock;
// port B returns a complete DDR word one clock after rd_addr is presented.
// Quartus' integrated-synthesis macro selects the Cyclone V primitive, while
// normal simulators use the cycle-equivalent behavioural array.
// ---------------------------------------------------------------------------
module xb_fb_run_ram (
    input              clk,
    input              wr_en,
    input       [7:0]  wr_addr,
    input       [3:0]  wr_lanes,
    input      [15:0]  wr_data,
    input       [7:0]  rd_addr,
    output     [63:0]  rd_q
);

wire [63:0] wr_word = {4{wr_data}};
wire  [7:0] wr_be = {{2{wr_lanes[3]}}, {2{wr_lanes[2]}}, {2{wr_lanes[1]}}, {2{wr_lanes[0]}}};

`ifdef ALTERA_RESERVED_QIS
altsyncram ram (
    .clock0(clk),
    .address_a(wr_addr),
    .data_a(wr_word),
    .byteena_a(wr_be),
    .wren_a(wr_en),

    .clock1(clk),
    .address_b(rd_addr),
    .q_b(rd_q),

    .aclr0(1'b0),
    .aclr1(1'b0),
    .addressstall_a(1'b0),
    .addressstall_b(1'b0),
    .clocken0(1'b1),
    .clocken1(1'b1),
    .clocken2(1'b1),
    .clocken3(1'b1),
    .eccstatus(),
    .rden_a(1'b1),
    .rden_b(1'b1)
);
defparam
    ram.numwords_a = 256,
    ram.widthad_a = 8,
    ram.width_a = 64,
    ram.numwords_b = 256,
    ram.widthad_b = 8,
    ram.width_b = 64,
    ram.address_reg_b = "CLOCK1",
    ram.clock_enable_input_a = "BYPASS",
    ram.clock_enable_input_b = "BYPASS",
    ram.clock_enable_output_b = "BYPASS",
    ram.intended_device_family = "Cyclone V",
    ram.lpm_type = "altsyncram",
    ram.operation_mode = "DUAL_PORT",
    ram.outdata_aclr_b = "NONE",
    ram.outdata_reg_b = "UNREGISTERED",
    ram.power_up_uninitialized = "FALSE",
    ram.read_during_write_mode_mixed_ports = "DONT_CARE",
    ram.width_byteena_a = 8;
`else
reg [63:0] mem [0:255];
reg [63:0] rd_q_r;
assign rd_q = rd_q_r;

integer __run_init;
initial begin
    for (__run_init = 0; __run_init < 256; __run_init = __run_init + 1)
        mem[__run_init] = 64'd0;
end

always @(posedge clk) begin
    rd_q_r <= mem[rd_addr];
    if (wr_en) begin
        if (wr_lanes[0]) mem[wr_addr][15:0]  <= wr_data;
        if (wr_lanes[1]) mem[wr_addr][31:16] <= wr_data;
        if (wr_lanes[2]) mem[wr_addr][47:32] <= wr_data;
        if (wr_lanes[3]) mem[wr_addr][63:48] <= wr_data;
    end
end
`endif

endmodule
