//============================================================================
//  Sega 315-5197 tilemap generator, "16B" register layout (MAME segaic16.cpp
//  tilemap_16b_*). Renders the next scanline of the foreground (register
//  set 0), background (set 1) and text layers into double-buffered line
//  buffers during the current line, one pixel per clock.
//
//  Text RAM (word offsets):
//    0x740..0x743 page select set 0..3     (E80..E87)
//    0x748..0x74B y scroll set 0..3, bit 15 = column scroll on (E90..E97)
//    0x74C..0x74F x scroll set 0..3, bit 15 = row scroll on    (E98..E9F)
//    0x7C0 + 0x20*layer + (y>>3)      row scroll, bit 15 = use alt set (+2)
//    0x78B + 0x20*layer + ((x+8)>>4)  column scroll
//  Sets 0..3 are latched at the start of line 261 (MAME latch timer).
//  Virtual map: 4 pages of 64x32 tiles in 2x2 (page nibbles: 0 upper-left,
//  1 upper-right, 2 lower-left, 3 lower-right); px = (x + (0xC0 - xs)) & 0x3FF,
//  py = (y + ys) & 0x1FF. Tile word: 15 priority, 12:6 colour, 12:0 code (they overlap, as in MAME).
//  Text: 64x28 at screen x = col*8 - 192; word: 15 priority, 11:9 colour,
//  8:0 code.
//============================================================================
module xb_tilemap_5197 (
    input             clk,
    input             reset,

    // timing
    input             line_start,     // one clk at hcnt == 0 (with ce_pix)
    input       [8:0] vcnt,           // line now being displayed
    input             latch_pulse,    // start of line 261
    input             ce_pix,
    input       [8:0] hcnt,

    // tile RAM / text RAM read ports (1-clock latency)
    output reg [14:0] tile_addr,
    input      [15:0] tile_q,
    output reg [10:0] text_addr,
    input      [15:0] text_q,
    // tile ROM (1-clock latency)
    output reg [15:0] rom_addr,
    input       [7:0] rom_p0, rom_p1, rom_p2,

    // per-pixel output, valid the clock after ce_pix for pixel hcnt
    output reg [10:0] fg_pix,         // {prio, colour[6:0], pen[2:0]}
    output reg [10:0] bg_pix,
    output reg  [6:0] tx_pix          // {prio, colour[2:0], pen[2:0]}
);

// ---------------------------------------------------------------- registers
reg [15:0] pages [0:3], ysc [0:3], xsc [0:3];    // latched sets
reg [15:0] colscroll [0:20];
integer i;

// ---------------------------------------------------------------- line buffers
reg [10:0] lb_fg [0:1023];
reg [10:0] lb_bg [0:1023];
reg  [6:0] lb_tx [0:1023];
wire       disp_bank = vcnt[0];
wire       rend_bank = ~vcnt[0];

// ---------------------------------------------------------------- renderer FSM
typedef enum logic [3:0] {
    S_IDLE, S_LATCH, S_LAYER_ROW, S_LAYER_ROW_W, S_COL, S_COL_W, S_PIX, S_DRAIN,
    S_TEXT, S_TEXT_DRAIN, S_DONE
} st_t;
st_t st;

reg  [8:0] ry;              // line being rendered
reg        latch_req;
reg  [4:0] lcnt;            // latch read counter
reg        layer;           // 0 fg (set 0), 1 bg (set 1)
reg        alt;             // rowscroll bit 15: use set +2
reg [15:0] rowscroll;
reg [15:0] xs_eff, ys_base;
reg        colmode;
reg  [4:0] ccnt;
reg  [9:0] x;               // pixel counter 0..319
// pipeline: stage k = k clocks after the tile/text RAM address was registered.
//   k=1 word valid (registered RAM output) -> ROM address registered,
//   k=2 ROM output registers, k=3 plane bytes valid -> line buffer write.
reg  [4:0] pipe;            // valid bits, pipe[k]
reg  [8:0] xq [0:4];
reg  [2:0] bitq [0:4];
reg  [2:0] rowq [0:4];
reg [15:0] word_s3, word_s4;

// effective scroll for the current pixel
wire [15:0] xs_sel   = alt ? xsc[{1'b1, layer}] : xsc[{1'b0, layer}];
wire [15:0] ys_alt   = ysc[{1'b1, layer}];
wire [9:0]  xp8      = x + 10'd8;
wire [4:0]  colidx   = xp8[8:4];
wire [15:0] ys_pix   = alt ? ys_alt : (colmode ? colscroll[colidx] : ys_base);
wire [9:0]  effx     = (10'h0C0 - xs_eff[9:0]) & 10'h3FF;
wire [9:0]  px       = (x + effx) & 10'h3FF;
wire [8:0]  py       = (ry + ys_pix[8:0]) & 9'h1FF;
wire [1:0]  quadrant = {py[8], px[9]};
wire [15:0] pg_sel   = alt ? pages[{1'b1, layer}] : pages[{1'b0, layer}];
wire [3:0]  page     = quadrant == 2'd0 ? pg_sel[3:0]  : quadrant == 2'd1 ? pg_sel[7:4] :
                       quadrant == 2'd2 ? pg_sel[11:8] : pg_sel[15:12];

wire [2:0] pen_s3   = {rom_p2[bitq[3]], rom_p1[bitq[3]], rom_p0[bitq[3]]};

always @(posedge clk) begin
    if (reset) begin
        st <= S_IDLE; latch_req <= 1'b0; ry <= 9'd0; pipe <= 5'd0;
        for (i = 0; i < 4; i = i + 1) begin pages[i] <= 16'd0; ysc[i] <= 16'd0; xsc[i] <= 16'd0; end
    end
    else begin
        if (latch_pulse) latch_req <= 1'b1;

        case (st)
        S_IDLE: begin
            if (line_start) begin
                ry <= (vcnt == 9'd261) ? 9'd0 : vcnt + 9'd1;
                layer <= 1'b0;
                if (latch_req || (vcnt == 9'd261)) begin
                    latch_req <= 1'b0;
                    lcnt <= 5'd0;
                    text_addr <= 11'h740;
                    st <= S_LATCH;
                end
                else st <= S_LAYER_ROW;
            end
        end

        // read E80..E9F (words 0x740..0x74F): 16 reads, data one clock later
        S_LATCH: begin
            lcnt <= lcnt + 5'd1;
            text_addr <= 11'h740 + {6'd0, lcnt + 5'd1};
            if (lcnt != 5'd0) begin
                logic [4:0] li;
                li = lcnt - 5'd1;
                case (li)
                    5'd0, 5'd1, 5'd2, 5'd3:     pages[li[1:0]] <= text_q;
                    5'd8, 5'd9, 5'd10, 5'd11:   ysc[li[1:0]]   <= text_q;
                    5'd12, 5'd13, 5'd14, 5'd15: xsc[li[1:0]]   <= text_q;
                    default: ;
                endcase
            end
            if (lcnt == 5'd16) begin layer <= 1'b0; st <= S_LAYER_ROW; end
        end

        // per layer: fetch this line's row-scroll word
        S_LAYER_ROW: begin
            if (ry < 9'd224) begin
                text_addr <= 11'h7C0 + {5'd0, layer, 5'd0} + {6'd0, ry[7:3]};
                st <= S_LAYER_ROW_W;
            end
            else st <= S_DONE;
        end
        S_LAYER_ROW_W: st <= S_COL;
        S_COL: begin
            // text_q = rowscroll; decide the scroll sources for this layer/line
            rowscroll <= text_q;
            alt       <= text_q[15];
            xs_eff    <= text_q[15] ? xsc[{1'b1, layer}] : (xsc[{1'b0, layer}][15] ? text_q : xsc[{1'b0, layer}]);
            colmode   <= ysc[{1'b0, layer}][15];
            ys_base   <= ysc[{1'b0, layer}];
            ccnt      <= 5'd0;
            text_addr <= 11'h78B + {5'd0, layer, 5'd0};
            st <= S_COL_W;
        end
        // read the 21 column-scroll words
        S_COL_W: begin
            ccnt <= ccnt + 5'd1;
            text_addr <= 11'h78B + {5'd0, layer, 5'd0} + {6'd0, ccnt + 5'd1};
            if (ccnt != 5'd0) colscroll[ccnt - 5'd1] <= text_q;
            if (ccnt == 5'd21) begin x <= 10'd0; pipe <= 5'd0; st <= S_PIX; end
        end
        // pixel pipeline (see the stage comment above)
        S_PIX: begin
            tile_addr <= {page, py[7:3], px[8:3]};
            xq[0] <= x[8:0]; bitq[0] <= ~px[2:0]; rowq[0] <= py[2:0];
            x <= x + 10'd1;
            if (x == 10'd319) st <= S_DRAIN;
        end
        S_DRAIN: begin
            if (pipe == 5'd0) begin
                if (!layer) begin layer <= 1'b1; st <= S_LAYER_ROW; end
                else begin x <= 10'd0; st <= S_TEXT; end
            end
        end
        // text layer: word at row*64 + 24 + x/8
        S_TEXT: begin
            text_addr <= {ry[7:3], 6'd0} + 11'd24 + {5'd0, x[8:3]};
            xq[0] <= x[8:0]; bitq[0] <= ~x[2:0]; rowq[0] <= ry[2:0];
            x <= x + 10'd1;
            if (x == 10'd319) st <= S_TEXT_DRAIN;
        end
        S_TEXT_DRAIN: begin
            if (pipe == 5'd0) st <= S_DONE;
        end
        S_DONE: st <= S_IDLE;
        default: st <= S_IDLE;
        endcase

        // pipeline shift
        pipe <= {pipe[3:0], (st == S_PIX || st == S_TEXT)};
        for (i = 1; i < 5; i = i + 1) begin xq[i] <= xq[i-1]; bitq[i] <= bitq[i-1]; rowq[i] <= rowq[i-1]; end
        // stage 1: tile/text word valid, register the ROM address
        if (pipe[1]) begin
            if (st == S_PIX || st == S_DRAIN) begin
                rom_addr <= {tile_q[12:0], rowq[1]};
                word_s3  <= tile_q;
            end
            else begin
                rom_addr <= {4'd0, text_q[8:0], rowq[1]};
                word_s3  <= text_q;
            end
        end
        word_s4 <= word_s3;
        // stage 3: plane bytes valid, write the line buffer
        if (pipe[3]) begin
            if (st == S_PIX || st == S_DRAIN) begin
                if (!layer) lb_fg[{rend_bank, xq[3]}] <= {word_s4[15], word_s4[12:6], pen_s3};
                else        lb_bg[{rend_bank, xq[3]}] <= {word_s4[15], word_s4[12:6], pen_s3};
            end
            else lb_tx[{rend_bank, xq[3]}] <= {word_s4[15], word_s4[11:9], pen_s3};
        end
    end
end

// ---------------------------------------------------------------- display side
always @(posedge clk) begin
    if (ce_pix) begin
        fg_pix <= lb_fg[{disp_bank, hcnt}];
        bg_pix <= lb_bg[{disp_bank, hcnt}];
        tx_pix <= lb_tx[{disp_bank, hcnt}];
    end
end
endmodule
