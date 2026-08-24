//============================================================================
//  X Board video priority mixer (315-5279 PAL + 315-5197 pixel bus), a
//  direct port of MAME segaxbd_state::screen_update:
//    road background -> [road fg if road_priority == 0] -> bg pri0 (mark 1)
//    -> bg pri1 (2) -> fg pri0 (2) -> fg pri1 (4) -> [road fg if
//    road_priority == 1] -> text pri0 (4) -> text pri1 (8); a sprite pixel
//    shows when (1 << sprite_prio) > mark, and a shadow pen (bits 14 and
//    3:0 == 0x400A) selects the effects palette bank of the pixel below.
//  Tile palette base 0x1C00 + colour*8 + pen; sprites use bits 11:0.
//  Output: palette index + effects flag, one clock after the inputs.
//============================================================================
module xb_mixer (
    input             clk,
    input             ce_pix,
    input             road_priority,
    input      [10:0] fg_pix, bg_pix,      // {prio, colour[6:0], pen[2:0]}
    input       [6:0] tx_pix,              // {prio, colour[2:0], pen[2:0]}
    input             road_bg_v,           // solid background line colour
    input      [12:0] road_bg_idx,
    input             road_fg_v,           // road pixel
    input      [12:0] road_fg_idx,
    input             spr_v,               // sprite pixel present (pen 1..14)
    input      [15:0] spr_pix,             // {?, shadow, prio[1:0], colour[7:0], pen[3:0]}
    output reg [12:0] pal_idx,
    output reg        pal_effects
);

function automatic [12:0] tile_idx(input [9:0] cp);   // {colour[6:0], pen[2:0]}
    tile_idx = 13'h1C00 + {3'd0, cp};
endfunction

reg [12:0] idx;
reg  [3:0] mark;
always @* begin
    idx  = 13'd0;          // black when nothing is drawn
    mark = 4'd0;
    if (road_bg_v) idx = road_bg_idx;
    if (road_fg_v && !road_priority) idx = road_fg_idx;
    if (bg_pix[2:0] != 3'd0 && !bg_pix[10]) begin idx = tile_idx(bg_pix[9:0]); mark = mark | 4'h1; end
    if (bg_pix[2:0] != 3'd0 &&  bg_pix[10]) begin idx = tile_idx(bg_pix[9:0]); mark = mark | 4'h2; end
    if (fg_pix[2:0] != 3'd0 && !fg_pix[10]) begin idx = tile_idx(fg_pix[9:0]); mark = mark | 4'h2; end
    if (fg_pix[2:0] != 3'd0 &&  fg_pix[10]) begin idx = tile_idx(fg_pix[9:0]); mark = mark | 4'h4; end
    if (road_fg_v && road_priority) idx = road_fg_idx;
    if (tx_pix[2:0] != 3'd0 && !tx_pix[6]) begin idx = tile_idx({4'd0, tx_pix[5:0]}); mark = mark | 4'h4; end
    if (tx_pix[2:0] != 3'd0 &&  tx_pix[6]) begin idx = tile_idx({4'd0, tx_pix[5:0]}); mark = mark | 4'h8; end
end

wire [3:0] spr_mask = 4'd1 << spr_pix[13:12];
wire       spr_over = spr_v && (spr_mask > mark);
wire       spr_shadow = (spr_pix[14] && spr_pix[3:0] == 4'hA);

always @(posedge clk) begin
    if (ce_pix) begin
        if (spr_over && spr_shadow) begin pal_idx <= idx;                 pal_effects <= 1'b1; end
        else if (spr_over)          begin pal_idx <= {1'b0, spr_pix[11:0]}; pal_effects <= 1'b0; end
        else                        begin pal_idx <= idx;                 pal_effects <= 1'b0; end
    end
end
endmodule
