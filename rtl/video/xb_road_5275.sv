//============================================================================
//  Sega 315-5275 road generator (X Board), MAME segaic16_road.cpp
//  segaic16_road_outrun_draw with the X Board parameters (colorbase 0x1700 /
//  0x1720 / 0x1780, xoffs -166, control mask 7).
//  Road RAM (renderer bank, 2048 words): 0x000/0x100 per-line words for road
//  0/1 (bit 11 solid, bit 9 stripe-as-road, 8:1 ROM line), 0x200/0x400 h
//  positions, 0x600/0x700 colours (indexed by the line word's 8:0, or by y
//  when control bit 2 is set). Road ROM: 2 roads x 256 lines x 512 px, two
//  bitplanes (plane 1 at +0x4000), 64 bytes per line per plane; road 1's
//  lines start at byte 0x8000.
//  Renders the next line into a double-buffered line buffer at 2 clocks per
//  pixel (road 0's two plane bytes, then road 1's).
//============================================================================
module xb_road_5275 (
    input             clk,
    input             reset,
    input             line_start,
    input       [8:0] vcnt,
    input             ce_pix,
    input       [8:0] hcnt,
    input       [2:0] control,

    output reg [10:0] ram_addr,       // renderer-bank road RAM (registered output RAM)
    input      [15:0] ram_q,
    output reg [15:0] rom_addr0,      // road ROM byte addresses (plane 0 / plane 1)
    output reg [15:0] rom_addr1,
    input       [7:0] rom_q0,
    input       [7:0] rom_q1,

    // per-pixel outputs, valid the clock after ce_pix for pixel hcnt
    output reg        bg_v,           // solid background colour for the line
    output reg [12:0] bg_idx,
    output reg        fg_v,           // road pixel
    output reg [12:0] fg_idx
);

localparam [12:0] CB1 = 13'h1700, CB2 = 13'h1720, CB3 = 13'h1780;
localparam [11:0] HOFF = 12'h552;    // (0x5f8 + xoffs) & 0xfff, xoffs = -166

// line buffers
reg [13:0] lb [0:1023];               // {fg_v, fg_idx}
reg        lbg_v [0:1];
reg [12:0] lbg_idx [0:1];
wire disp_bank = vcnt[0];
wire rend_bank = ~vcnt[0];

// ---------------------------------------------------------------- per-line registers
typedef enum logic [2:0] { S_IDLE, S_READ, S_SETUP, S_PIX, S_DONE } st_t;
st_t st;
reg  [8:0] ry;
reg  [2:0] ctl;
reg  [4:0] rc;                        // read micro-sequence counter
reg [15:0] data0, data1, hpos0w, hpos1w, color0, color1;
reg        line_fg;                   // foreground pass draws anything
reg [11:0] base0, base1;
reg [12:0] ct00, ct01, ct02, ct03, ct07, ct10, ct11, ct12, ct13, ct17;
reg [10:0] pc;                        // pixel cycle counter (2 per pixel)
reg  [7:0] q0p0, q0p1;                // road 0 plane bytes

wire [8:0] idx0 = ctl[2] ? ry : data0[8:0];
wire [8:0] idx1 = ctl[2] ? ry : data1[8:0];   // + 0x100 for road 1 tables when direct

function automatic [12:0] ct0(input [2:0] p);
    case (p) 3'd0: ct0 = ct00; 3'd1: ct0 = ct01; 3'd2: ct0 = ct02; 3'd3: ct0 = ct03; 3'd7: ct0 = ct07; default: ct0 = 13'd0; endcase
endfunction
function automatic [12:0] ct1(input [2:0] p);
    case (p) 3'd0: ct1 = ct10; 3'd1: ct1 = ct11; 3'd2: ct1 = ct12; 3'd3: ct1 = ct13; 3'd7: ct1 = ct17; default: ct1 = 13'd0; endcase
endfunction
function automatic [7:0] pmap(input sel, input [2:0] p);   // MAME priority_map
    if (!sel) case (p) 3'd0: pmap = 8'h80; 3'd1: pmap = 8'h81; 3'd2: pmap = 8'h81; 3'd3: pmap = 8'h87; 3'd7: pmap = 8'h00; default: pmap = 8'h00; endcase
    else      case (p) 3'd0: pmap = 8'h81; 3'd1: pmap = 8'h81; 3'd2: pmap = 8'h81; 3'd3: pmap = 8'h8f; 3'd7: pmap = 8'h80; default: pmap = 8'h00; endcase
endfunction

// pixel pipeline: issue road 0 addresses at even pc, road 1 at odd pc;
// road 0 bytes return two clocks later (even), road 1 bytes at the next odd.
wire [9:0]  x_issue = pc[10:1];
wire [11:0] h0_i = base0 + {2'd0, x_issue};
wire [11:0] h1_i = base1 + {2'd0, x_issue};
wire [10:0] pcm3  = pc - 11'd3;
wire [9:0]  x_w   = pcm3[10:1];               // pixel being written at odd pc >= 3
wire [11:0] h0_w = base0 + {2'd0, x_w};
wire [11:0] h1_w = base1 + {2'd0, x_w};
wire        solid0 = data0[11], solid1 = data1[11];
wire [15:0] rom_base0 = {2'd0, data0[8:1], 6'd0};            // line * 0x40
wire [15:0] rom_base1 = 16'h8000 + {2'd0, data1[8:1], 6'd0};

wire [2:0] b0 = ~h0_w[2:0];
wire [2:0] b1 = ~h1_w[2:0];
wire [1:0] rawa = {q0p1[b0], q0p0[b0]};
wire [1:0] rawb = {rom_q1[b1], rom_q0[b1]};
wire       st0 = (h0_w[8:3] == 6'd31) && (rawa == 2'd3);   // stripe marker x 248..255
wire       st1 = (h1_w[8:3] == 6'd31) && (rawb == 2'd3);
wire [2:0] pix0 = (solid0 || h0_w[11:9] != 3'd0) ? 3'd3 : {st0, rawa};
wire [2:0] pix1 = (solid1 || h1_w[11:9] != 3'd0) ? 3'd3 : {st1, rawb};
wire [7:0] pm0  = pmap(ctl[1], pix0);
wire       use1 = pm0[pix1];
reg [12:0] fg_pix_w;
always @* begin
    case (ctl[1:0])
        2'd0: fg_pix_w = ct0(pix0);
        2'd3: fg_pix_w = ct1(pix1);
        default: fg_pix_w = use1 ? ct1(pix1) : ct0(pix0);
    endcase
end

always @(posedge clk) begin
    if (reset) begin st <= S_IDLE; ry <= 9'd0; rc <= 5'd0; pc <= 11'd0; end
    else case (st)
        S_IDLE: if (line_start) begin
            ry  <= (vcnt == 9'd261) ? 9'd0 : vcnt + 9'd1;
            ctl <= control;
            rc  <= 5'd0;
            st  <= S_READ;
        end
        // six RAM reads, three clocks each (address, RAM, capture)
        S_READ: begin
            rc <= rc + 5'd1;
            case (rc)
                5'd0:  ram_addr <= {2'd0, ry};
                5'd2:  data0 <= ram_q;
                5'd3:  ram_addr <= 11'h100 + {2'd0, ry};
                5'd5:  data1 <= ram_q;
                5'd6:  ram_addr <= 11'h200 + {2'd0, idx0};
                5'd8:  hpos0w <= ram_q;
                5'd9:  ram_addr <= 11'h400 + (ctl[2] ? (11'h100 + {2'd0, ry}) : {2'd0, idx1});
                5'd11: hpos1w <= ram_q;
                5'd12: ram_addr <= 11'h600 + {2'd0, idx0};
                5'd14: color0 <= ram_q;
                5'd15: ram_addr <= 11'h600 + (ctl[2] ? (11'h100 + {2'd0, ry}) : {2'd0, idx1});
                5'd17: begin color1 <= ram_q; st <= S_SETUP; end
                default: ;
            endcase
        end
        S_SETUP: begin
            // background colour for this line (MAME ROAD_BACKGROUND pass)
            lbg_v[rend_bank] <= 1'b0;
            case (ctl[1:0])
                2'd0: if (solid0) begin lbg_v[rend_bank] <= 1'b1; lbg_idx[rend_bank] <= CB3 | {6'd0, data0[6:0]}; end
                2'd1: if (solid0) begin lbg_v[rend_bank] <= 1'b1; lbg_idx[rend_bank] <= CB3 | {6'd0, data0[6:0]}; end
                      else if (solid1) begin lbg_v[rend_bank] <= 1'b1; lbg_idx[rend_bank] <= CB3 | {6'd0, data1[6:0]}; end
                2'd2: if (solid1) begin lbg_v[rend_bank] <= 1'b1; lbg_idx[rend_bank] <= CB3 | {6'd0, data1[6:0]}; end
                      else if (solid0) begin lbg_v[rend_bank] <= 1'b1; lbg_idx[rend_bank] <= CB3 | {6'd0, data0[6:0]}; end
                default: if (solid1) begin lbg_v[rend_bank] <= 1'b1; lbg_idx[rend_bank] <= CB3 | {6'd0, data1[6:0]}; end
            endcase
            // foreground pass enable
            line_fg <= !(solid0 && solid1) &&
                       !(ctl[1:0] == 2'd0 && solid0) && !(ctl[1:0] == 2'd3 && solid1);
            base0 <= hpos0w[11:0] - HOFF;
            base1 <= hpos1w[11:0] - HOFF;
            ct00 <= CB1 ^ 13'h00 ^ {12'd0, color0[0]};
            ct01 <= CB1 ^ 13'h02 ^ {12'd0, color0[1]};
            ct02 <= CB1 ^ 13'h04 ^ {12'd0, color0[2]};
            ct03 <= data0[9] ? (CB1 ^ 13'h00 ^ {12'd0, color0[0]}) : (CB2 ^ 13'h00 ^ {9'd0, color0[11:8]});
            ct07 <= CB1 ^ 13'h06 ^ {12'd0, color0[3]};
            ct10 <= CB1 ^ 13'h08 ^ {12'd0, color1[4]};
            ct11 <= CB1 ^ 13'h0a ^ {12'd0, color1[5]};
            ct12 <= CB1 ^ 13'h0c ^ {12'd0, color1[6]};
            ct13 <= data1[9] ? (CB1 ^ 13'h08 ^ {12'd0, color1[4]}) : (CB2 ^ 13'h10 ^ {9'd0, color1[11:8]});
            ct17 <= CB1 ^ 13'h0e ^ {12'd0, color1[7]};
            pc <= 11'd0;
            st <= S_PIX;
        end
        S_PIX: begin
            pc <= pc + 11'd1;
            if (!pc[0]) begin      // issue road 0 plane addresses, capture nothing
                rom_addr0 <= rom_base0 + {10'd0, h0_i[8:3]};
                rom_addr1 <= rom_base0 + 16'h4000 + {10'd0, h0_i[8:3]};
                if (pc >= 11'd2) begin q0p0 <= rom_q0; q0p1 <= rom_q1; end   // road 0 bytes of pixel (pc-2)/2
            end
            else begin             // issue road 1 plane addresses; write pixel x_w
                rom_addr0 <= rom_base1 + {10'd0, h1_i[8:3]};
                rom_addr1 <= rom_base1 + 16'h4000 + {10'd0, h1_i[8:3]};
                if (pc >= 11'd3 && x_w < 10'd320)
                    lb[{rend_bank, x_w[8:0]}] <= {line_fg, fg_pix_w};
            end
            if (pc == 11'd643) st <= S_DONE;    // last write at pc = 3 + 2*319 = 641
        end
        S_DONE: st <= S_IDLE;
        default: st <= S_IDLE;
    endcase
end

// ---------------------------------------------------------------- display side
always @(posedge clk) begin
    if (ce_pix) begin
        {fg_v, fg_idx} <= lb[{disp_bank, hcnt}];
        bg_v   <= lbg_v[disp_bank];
        bg_idx <= lbg_idx[disp_bank];
    end
end
endmodule
