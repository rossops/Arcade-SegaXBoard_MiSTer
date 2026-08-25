//============================================================================
//  Sega 315-5218 PCM (SegaPCM), MAME segapcm.cpp with BANK_512 (bankshift
//  12, bankmask 0x70). 16 channels, register RAM at 8*ch:
//    0x02 vol L, 0x03 vol R, 0x04/0x05 loop (bits 15:8 / 23:16), 0x06 end
//    (compared with addr[23:16] + 1), 0x07 delta, 0x84/0x85 current address
//    (bits 15:8 / 23:16), 0x86 flags: bit0 stop, bit1 no loop, 6:4 bank.
//  Every 128 chip clocks (31.25 kHz) each active channel advances by delta
//  (8.8 fixed point in addr[15:0]), fetches ROM byte offset + addr[23:8],
//  and adds (byte - 0x80) * vol to the left/right sums. The sums are in
//  MAME's 1/32768 units, i.e. directly 16-bit samples.
//  ROM bytes come from SDRAM port p6 (16-bit words, byte selected by A0);
//  the stream pads the PCM slot with 0xFF like MAME's ERASEFF region.
//============================================================================
import xb_pkg::*;

module xb_segapcm_5218 #(
    parameter [24:0] PCM_BASE = SDR_PCM_BASE
) (
    input             clk,          // clk_sys
    input             reset,
    input             tick,         // one pulse per 128 chip clocks (31.25 kHz)
    input       [7:0] bankmask,     // descriptor: 0x70 for aburner2

    // Z80 register access (F000-F0FF)
    input             cs,
    input             we,
    input       [7:0] addr,
    input       [7:0] din,
    output      [7:0] dout,

    // SDRAM p6
    output reg        rom_req,
    output reg [24:1] rom_addr,
    input      [15:0] rom_dout,
    input             rom_ack,

    output reg signed [15:0] out_l,
    output reg signed [15:0] out_r
);

reg  [7:0] regs [0:255];
reg [7:0] low [0:15];               // MAME m_low: addr[7:0] per channel
integer i;

// Z80 side: registered read
reg [7:0] rd_q;
assign dout = rd_q;

// engine
typedef enum logic [2:0] { E_IDLE, E_LOAD, E_CHECK, E_FETCH, E_WAIT, E_ACC, E_NEXT, E_DONE } es_t;
es_t es;
reg  [3:0] ch;
reg [23:0] a;
reg [23:0] loop;
reg  [7:0] endb, delta, volr, voll, flags;
reg  [6:0] bank;
reg        rom_odd;
reg signed [19:0] sum_l, sum_r;

// register RAM: Z80 write wins; engine writes back 0x84/0x85/0x86 and low
always @(posedge clk) begin
    if (reset) begin
        for (i = 0; i < 256; i = i + 1) regs[i] <= 8'hFF;
        for (i = 0; i < 16; i = i + 1) low[i] <= 8'd0;
        es <= E_IDLE; rom_req <= 1'b0; out_l <= 0; out_r <= 0; ch <= 0;
        sum_l <= 0; sum_r <= 0;
    end
    else begin
        rom_req <= 1'b0;
        rd_q <= regs[addr];
        if (cs && we) regs[addr] <= din;

        case (es)
        E_IDLE: if (tick) begin ch <= 4'd0; sum_l <= 0; sum_r <= 0; es <= E_LOAD; end
        E_LOAD: begin
            flags <= regs[{1'b1, ch, 3'd6}];
            bank  <= regs[{1'b1, ch, 3'd6}][6:0] & bankmask[6:0];
            a     <= {regs[{1'b1, ch, 3'd5}], regs[{1'b1, ch, 3'd4}], low[ch]};
            loop  <= {regs[{1'b0, ch, 3'd5}], regs[{1'b0, ch, 3'd4}], 8'd0};
            endb  <= regs[{1'b0, ch, 3'd6}] + 8'd1;
            delta <= regs[{1'b0, ch, 3'd7}];
            voll  <= regs[{1'b0, ch, 3'd2}] & 8'h7F;
            volr  <= regs[{1'b0, ch, 3'd3}] & 8'h7F;
            es <= E_CHECK;
        end
        E_CHECK: begin
            if (flags[0]) es <= E_NEXT;                       // inactive
            else if (a[23:16] == endb) begin
                if (flags[1]) begin                           // no loop: stop
                    regs[{1'b1, ch, 3'd6}][0] <= 1'b1;
                    low[ch] <= 8'd0;
                    es <= E_NEXT;
                end
                else begin a <= loop; es <= E_FETCH; end
            end
            else es <= E_FETCH;
        end
        E_FETCH: begin
            // byte address: (bank << 12) + addr[23:8]; bank field in bits 6:4 -> <<12 gives 64 KB units
            logic [24:0] ba;
            // offset = (flags & bankmask) << 12; bank bits 6:4 -> 64 KB units
            ba = PCM_BASE + {6'd0, bank, 12'd0} + {9'd0, a[23:8]};
            rom_addr <= ba[24:1];
            rom_odd  <= ba[0];
            rom_req  <= 1'b1;
            es <= E_WAIT;
        end
        E_WAIT: if (rom_ack) es <= E_ACC;
        E_ACC: begin
            logic signed [8:0] v;
            logic [23:0] na;
            v = $signed({1'b0, rom_odd ? rom_dout[15:8] : rom_dout[7:0]}) - 9'sd128;
            sum_l <= sum_l + v * $signed({1'b0, voll});
            sum_r <= sum_r + v * $signed({1'b0, volr});
            na = a + {16'd0, delta};
            regs[{1'b1, ch, 3'd4}] <= na[15:8];
            regs[{1'b1, ch, 3'd5}] <= na[23:16];
            low[ch] <= na[7:0];
            es <= E_NEXT;
        end
        E_NEXT: begin
            if (ch == 4'd15) es <= E_DONE;
            else begin ch <= ch + 4'd1; es <= E_LOAD; end
        end
        E_DONE: begin
            out_l <= (sum_l > 20'sd32767) ? 16'sd32767 : (sum_l < -20'sd32768) ? -16'sd32768 : sum_l[15:0];
            out_r <= (sum_r > 20'sd32767) ? 16'sd32767 : (sum_r < -20'sd32768) ? -16'sd32768 : sum_r[15:0];
            es <= E_IDLE;
        end
        default: es <= E_IDLE;
        endcase
    end
end
endmodule
