//============================================================================
//  Sega 315-5211A sprite generator (X Board), rendering into one of two
//  512x256x16 framebuffers held in DDR3 through xb_fb_if.
//  Algorithm: MAME sega16sp.cpp sega_outrun_sprite_device::draw (xboard):
//    w0: e------- -------- end of list;  -h-h---- hide;  ----bbb- bank;
//        -------t tttttttt top + 256
//    w1: ROM offset (16-bit words of 32-bit pixels)
//    w2: ppppppp- pitch (signed, bit 12 of w4 extends), -------x xxxxxxxx x
//    w3: -s------ shadow, --pp---- priority, ------vv vvvvvvvv vzoom
//    w4: y------- top-to-bottom, -f------ flip, --x----- left-to-right,
//        ------hh hhhhhhhh hzoom
//    w5: ----hhhh hhhhhhhh height - 1
//    w6: -------- cccccccc colour
//  Framebuffer pixel: {?, shadow, prio[1:0], colour[7:0], pen[3:0]};
//  0xFFFF = empty. Framebuffer x = sprite x (origin 190 = screen 0), y = top.
//
//  Sequence (MacDonald): a write to $110000 swaps the CPU/renderer sprite RAM
//  banks and starts the render into the back buffer; rendering is aborted at
//  the start of vblank. The render first erases the back buffer (256 lines),
//  then walks the list. At vblank the buffers swap only if a render ran since
//  the previous swap, so a frame without a $110000 write keeps displaying the
//  old image exactly like the real chip (MAME's every-frame redraw of the
//  buffered list is an emulator artefact with the same visible result for
//  games that write every frame).
//
//  Sprite ROM: SDRAM port p2, 128-bit bursts = 4 consecutive 32-bit words.
//============================================================================
import xb_pkg::*;

module xb_sprite_5211 (
    input             clk,            // clk_ram (100 MHz)
    input             reset,
    input       [7:0] num_banks,      // 256 KB banks in the ROM set (aburner2: 8)

    // control (clk_ram synchronous copies made outside)
    input             start_req,      // one-clk pulse: $110000 written (banks already swapped)
    input             vbl_start,      // one-clk pulse at start of line 223
    input       [8:0] vcnt,
    input             line_start,     // one-clk pulse at hcnt == 0

    // sprite RAM read port (renderer bank), 1-clk registered output
    output reg [10:0] sram_addr,      // word within the 4 KB bank
    input      [15:0] sram_q,

    // SDRAM sprite ROM
    output reg        rom_req,
    output reg [24:4] rom_addr,
    input     [127:0] rom_dout,
    input             rom_ack,

    // framebuffer interface
    input             hires,          // 2x mode: 1024x512 framebuffer, half-step sampling
    input             oline,          // second output line of the game line (2x mode)
    output reg        fb_wr_start,
    output reg  [1:0] fb_wr_buf,
    output reg  [9:0] fb_wr_x,        // first pixel of the write
    output reg  [3:0] fb_wr_lanes,    // lanes of the 64-bit word fb_wr_x[9:2] written (2x: pairs)
    output reg  [8:0] fb_wr_y,
    output reg        fb_wr_valid,
    output reg [15:0] fb_wr_pix,
    output reg        fb_wr_end,
    input             fb_wr_busy,
    output reg        fb_er_req,
    output reg  [1:0] fb_er_buf,
    output reg  [8:0] fb_er_y,
    input             fb_er_ack,
    output reg        fb_rd_req,
    output reg  [1:0] fb_rd_buf,
    output reg  [8:0] fb_rd_y,
    input             fb_rd_ack,

    output reg        disp_buf        // buffer currently displayed
);

// ---------------------------------------------------------------- buffers
// disp_buf is displayed / being erased; ~disp_buf is the render target.
reg        render_pending;    // a list is waiting to be rendered
reg        rendering;

reg [8:0] er_line;
reg       did_render;
// ---------------------------------------------------------------- list walker
typedef enum logic [3:0] {
    R_IDLE, R_ERASE, R_ERASEW, R_FETCH, R_FETCHW, R_DECODE, R_ROW, R_ROWWAIT,
    R_ROMREQ, R_ROMWAIT, R_PIX, R_ROWEND, R_NEXT, R_ROWSKIP
} rs_t;
rs_t rs;

reg  [7:0] sprite_idx;
reg  [3:0] wcnt;
reg [15:0] w [0:6];

// decoded
reg        hide;
reg  [2:0] bank;
reg signed [10:0] top;
reg [15:0] addr;
reg signed [7:0] pitch;
reg [10:0] xpos;
reg [10:0] vzoom, hzoom;
reg        ydown, flip, xright;
reg [12:0] height;
reg [15:0] colpri;

// row state
reg signed [10:0] y;
reg [12:0] rows_left;
reg  [9:0] yacc;
reg [15:0] rowaddr;          // data[7] in MAME: the row's working pointer
// `addr` above is the row base, advanced by pitch at each row end (MAME's addr)
reg [10:0] x;
reg [11:0] xacc;            // xacc < threshold + hzoom
wire [11:0] xth = hires ? 12'h400 : 12'h200;   // half-step sampling in the 2x mode
reg  [2:0] nib;              // nibble 0..7 within the word
reg [31:0] pixels;
reg        last_data;

// ROM word fetch: 4 words per burst; keep the burst and index into it
reg [127:0] burst;
reg  [13:0] burst_tag;       // addr[15:2] of the held burst (plus bank)
reg   [2:0] burst_bank;
reg         burst_valid;
wire [15:0] want_addr = rowaddr;
wire        burst_hit = burst_valid && burst_tag == want_addr[15:2] && burst_bank == bank;
wire [31:0] word_sel  = want_addr[1:0] == 2'd0 ? burst[31:0]  : want_addr[1:0] == 2'd1 ? burst[63:32] :
                        want_addr[1:0] == 2'd2 ? burst[95:64] : burst[127:96];

// pixel reordering for non-flipped sprites (MAME): reverse the nibble order
function automatic [31:0] swiz(input [31:0] p);
    swiz = {p[3:0], p[7:4], p[11:8], p[15:12], p[19:16], p[23:20], p[27:24], p[31:28]};
endfunction

wire [3:0] pix = pixels[3:0];
wire       on_screen_y = (y >= 0) && (y < (hires ? 11'sd448 : 11'sd224));   // MAME clips to the screen
// framebuffer x window: MAME clips to screen x 0..319 = fb x 190..509 (2x: 380..1019)
wire signed [11:0] xorg = hires ? 12'sd380 : 12'sd190;
wire signed [11:0] sx  = $signed({1'b0, x}) - xorg;
wire signed [11:0] sx2 = xright ? sx + 12'sd1 : sx - 12'sd1;      // the pair's second pixel
wire signed [11:0] xmax = hires ? 12'sd640 : 12'sd320;
wire       on_screen_x  = (sx >= 0) && (sx < xmax);
wire       on_screen_x2 = (sx2 >= 0) && (sx2 < xmax);
// 2x: write the pair when both pixels sit in the same 64-bit word
wire       pair_ok = hires && (xright ? (x[1:0] != 2'd3) : (x[1:0] != 2'd0));
wire [1:0] x2lane  = xright ? x[1:0] + 2'd1 : x[1:0] - 2'd1;

// ---------------------------------------------------------------- line read
// Scanout: request line vcnt+1 of disp_buf at each line start (lines 0..222
// and line 0 during 261). Erasing is done by the renderer before it draws.
always @(posedge clk) begin
    if (reset) fb_rd_req <= 1'b0;
    else begin
        if (fb_rd_req) begin if (fb_rd_ack) fb_rd_req <= 1'b0; end
        else if (line_start && (vcnt < 9'd223 || vcnt == 9'd261)) begin
            // 1x: the next game line. 2x: line_start comes once per output
            // line; the first fetches 2n+1 for the second output line, the
            // second fetches 2(n+1) for the next game line's first one.
            fb_rd_req <= 1'b1;
            fb_rd_buf <= {1'b0, disp_buf};
            fb_rd_y   <= !hires ? ((vcnt == 9'd261) ? 9'd0 : {1'b0, vcnt[7:0]} + 9'd1) :
                         !oline ? ((vcnt == 9'd261) ? 9'd1 : {vcnt[7:0], 1'b1}) :
                                  ((vcnt == 9'd261) ? 9'd0 : {vcnt[7:0] + 8'd1, 1'b0});
        end
    end
end

// ---------------------------------------------------------------- renderer
always @(posedge clk) begin
    fb_wr_start <= 1'b0;
    fb_wr_valid <= 1'b0;
    fb_wr_end   <= 1'b0;
    rom_req     <= 1'b0;
    if (reset) begin
        rs <= R_IDLE; disp_buf <= 1'b0; render_pending <= 1'b0; rendering <= 1'b0;
        burst_valid <= 1'b0; sprite_idx <= 8'd0; wcnt <= 4'd0;
        fb_er_req <= 1'b0; did_render <= 1'b0;
    end
    else begin
        if (start_req) render_pending <= 1'b1;

        // vblank: abort the render; swap only if one ran since the last swap
        if (vbl_start) begin
            if (rendering || did_render) disp_buf <= ~disp_buf;
            did_render <= 1'b0;
            rendering <= 1'b0;
            if (rs != R_IDLE && rs != R_ROWWAIT && rs != R_ERASE && rs != R_ERASEW)
                fb_wr_end <= 1'b1;   // close an open run
            fb_er_req <= 1'b0;
            rs <= R_IDLE;
        end
        else case (rs)
        R_IDLE: begin
            if (render_pending && !fb_wr_busy) begin
                render_pending <= 1'b0;
                rendering <= 1'b1;
                did_render <= 1'b1;
                sprite_idx <= 8'd0;
                burst_valid <= 1'b0;
                er_line <= 9'd0;
                rs <= R_ERASE;
            end
        end
        // erase the whole back buffer before drawing into it
        R_ERASE: begin
            fb_er_req <= 1'b1;
            fb_er_buf <= {1'b0, ~disp_buf};
            fb_er_y   <= er_line;
            rs <= R_ERASEW;
        end
        R_ERASEW: begin
            if (fb_er_ack) begin
                fb_er_req <= 1'b0;
                if (er_line == (hires ? 9'd511 : 9'd255)) rs <= R_FETCH;
                else begin er_line <= er_line + 9'd1; rs <= R_ERASE; end
            end
        end
        // read 7 words of the entry (sram is 1-clk registered)
        R_FETCH: begin sram_addr <= {sprite_idx, 3'd0}; wcnt <= 4'd0; rs <= R_FETCHW; end
        R_FETCHW: begin
            sram_addr <= {sprite_idx, 3'd0} + {7'd0, wcnt + 4'd1};
            if (wcnt != 4'd0) begin logic [3:0] wi; wi = wcnt - 4'd1; w[wi[2:0]] <= sram_q; end
            wcnt <= wcnt + 4'd1;
            if (wcnt == 4'd7) rs <= R_DECODE;
        end
        R_DECODE: begin
            if (w[0][15]) begin rs <= R_IDLE; rendering <= 1'b0; end   // end of list
            else begin
                hide   <= |(w[0] & 16'h5000);
                bank   <= (num_banks != 8'd0 && {5'd0, w[0][11:9]} >= num_banks) ? (w[0][11:9] % num_banks[2:0]) : w[0][11:9];
                top    <= hires ? ($signed({2'b0, w[0][8:0]}) - 11'sd256) * 11'sd2 : $signed({2'b0, w[0][8:0]}) - 11'sd256;
                addr   <= w[1];
                pitch  <= $signed({w[4][12], w[2][15:9]});
                xpos   <= ((w[2][8:0] < 9'h80 && !w[4][13]) ? ({2'b0, w[2][8:0]} + 11'h200) : {2'b0, w[2][8:0]}) << (hires ? 1 : 0);
                vzoom  <= (w[3][10:0] < 11'h40) ? 11'h40 : w[3][10:0];
                hzoom  <= (w[4][10:0] < 11'h40) ? 11'h40 : w[4][10:0];
                ydown  <= w[4][15];
                flip   <= ~w[4][14];
                xright <= w[4][13];
                height <= ({1'b0, w[5][11:0]} + 13'd1) << (hires ? 1 : 0);
                colpri <= {1'b0, w[3][14], w[3][13:12], w[6][7:0], 4'd0};
                rs <= R_ROW;
            end
        end
        // set up the first row
        R_ROW: begin
            if (hide) rs <= R_NEXT;
            else begin
                y <= top; rows_left <= height; yacc <= 10'd0;
                rs <= R_ROWWAIT;
            end
        end
        // start a row: wait for the previous run's flush, then open a run
        R_ROWWAIT: begin
            if (rows_left == 13'd0) rs <= R_NEXT;
            else if (!on_screen_y) rs <= R_ROWSKIP;
            else if (!fb_wr_busy) begin
                fb_wr_start <= 1'b1;
                fb_wr_buf   <= {1'b0, ~disp_buf};
                fb_wr_y     <= y[8:0];
                rowaddr <= addr;         // MAME: data[7] = addr at row start
                x <= xpos; xacc <= 12'd0; nib <= 3'd0;
                rs <= R_ROMREQ;
            end
        end
        // fetch the word at rowaddr (from the held burst if possible)
        R_ROMREQ: begin
            if (!on_screen_x && ((xright && sx >= xmax) || (!xright && sx < 0))) begin
                // ran off the screen edge: end of row
                fb_wr_end <= 1'b1; rs <= R_ROWEND;
            end
            else if (burst_hit) begin
                logic [31:0] pe;
                pe = flip ? word_sel : swiz(word_sel);
                pixels    <= pe;
                last_data <= (pe[27:24] == 4'hF);   // MAME: second-to-last pixel of the group
                rowaddr   <= flip ? rowaddr - 16'd1 : rowaddr + 16'd1;
                nib <= 3'd0;
                rs <= R_PIX;
            end
            else begin
                rom_req  <= 1'b1;
                rom_addr <= SDR_SPRITE_BASE[24:4] + {3'd0, bank, want_addr[15:2]};
                rs <= R_ROMWAIT;
            end
        end
        R_ROMWAIT: begin
            if (rom_ack) begin
                burst <= rom_dout; burst_tag <= want_addr[15:2]; burst_bank <= bank; burst_valid <= 1'b1;
                rs <= R_ROMREQ;
            end
        end
        // emit framebuffer pixels while xacc < threshold: one per clock, or in
        // the 2x mode two (same source nibble) when they share a 64-bit word.
        // The step to the next source nibble happens in the same clock as the
        // emission that exhausts the accumulator (at 1:1 every source pixel
        // is one clock, not two).
        R_PIX: begin
            logic [11:0] xacc1, xacc2; logic two, adv;
            xacc1 = xacc + {1'b0, hzoom};
            two   = pair_ok && (xacc1 < xth);
            xacc2 = two ? xacc1 + {1'b0, hzoom} : xacc1;
            if (xacc < xth) begin
                fb_wr_valid <= (on_screen_x || (two && on_screen_x2)) && (pix != 4'd0) && (pix != 4'hF);
                fb_wr_lanes <= (on_screen_x ? (4'b0001 << x[1:0]) : 4'b0000) |
                               ((two && on_screen_x2) ? (4'b0001 << x2lane) : 4'b0000);
                fb_wr_pix   <= colpri | {12'd0, pix};
                fb_wr_x     <= x[9:0];
                x    <= two ? (xright ? x + 11'd2 : x - 11'd2) : (xright ? x + 11'd1 : x - 11'd1);
                adv  = (xacc2 >= xth);
                xacc <= adv ? xacc2 - xth : xacc2;
            end
            else begin
                adv  = 1'b1;
                xacc <= xacc - xth;
            end
            if (adv) begin
                pixels <= pixels >> 4;
                if (nib == 3'd7) begin
                    if (last_data) begin fb_wr_end <= 1'b1; rs <= R_ROWEND; end
                    else rs <= R_ROMREQ;
                end
                nib <= nib + 3'd1;
            end
        end
        R_ROWEND: begin
            {yacc, addr} <= next_row(addr);
            y <= ydown ? y + 11'sd1 : y - 11'sd1;
            rows_left <= rows_left - 13'd1;
            rs <= R_ROWWAIT;
        end
        // skip an off-screen row but advance the base address exactly like
        // MAME (its own state so row_sum has settled since the last yacc write)
        R_ROWSKIP: begin
            {yacc, addr} <= next_row(addr);
            y <= ydown ? y + 11'sd1 : y - 11'sd1;
            rows_left <= rows_left - 13'd1;
            rs <= R_ROWWAIT;
        end
        R_NEXT: begin
            if (sprite_idx == 8'd255) begin rs <= R_IDLE; rendering <= 1'b0; end
            else begin sprite_idx <= sprite_idx + 8'd1; rs <= R_FETCH; end
        end
        default: rs <= R_IDLE;
        endcase
    end
end

// yacc += vzoom; addr += pitch * (yacc >> 9); yacc &= 0x1ff
// (2x: threshold 0x400, i.e. >> 10 and & 0x3ff: each output row is half a step)
// The sum is registered a clock ahead (timing: add + multiply + add did not
// close at 100 MHz); every use of next_row is at least two clocks after the
// last write to yacc (R_ROW/R_ROWEND/R_ROWSKIP -> R_ROWWAIT -> R_ROWSKIP).
reg [11:0] row_sum;
always @(posedge clk) row_sum <= {2'd0, yacc} + {1'b0, vzoom};
function automatic [25:0] next_row(input [15:0] ra);
    logic signed [15:0] step;
    logic [9:0] nya;
    step = hires ? $signed(pitch) * $signed({2'b0, row_sum[11:10]}) : $signed(pitch) * $signed({1'b0, row_sum[11:9]});
    nya  = hires ? row_sum[9:0] : {1'b0, row_sum[8:0]};
    next_row = {nya, ra + step[15:0]};
endfunction
endmodule
