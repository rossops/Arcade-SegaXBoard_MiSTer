//============================================================================
//  Sega 315-5250 compare / timer / 68000-Z80 interface
//  Word offsets (address bits 4:1), reference MAME segaic16_m.cpp:
//    0,1  bounds (write executes compare)      3 flags: 0x8000 below min,
//    2    value (write executes + history)        0x4000 above max, 0 inside
//    4    history bits (read; write clears)    5 = reg1 mirror, 6 = reg2 mirror
//    6    value (write executes, no history)   7 clamped value
//    8,C  timer reload value (12 bits)         9,D interrupt acknowledge (r/w)
//    A,E  timer enable (bit 0)                 B,F sound latch -> Z80 NMI
//  Timer: 12-bit up-counter clocked by EXCK (V0). On each rising edge:
//    old = counter; if (enable) counter++; if (old == 0xFFF) { irq; counter = reload }
//  so a counter parked at 0xFFF fires every clock regardless of the enable.
//  The sub-CPU instance leaves timer_irq / snd_* unconnected.
//============================================================================
module xb_cmptimer_5250 (
    input             clk,
    input             reset,
    input             cs,
    input             we,
    input       [3:0] addr,
    input      [15:0] din,
    input       [1:0] be,
    output reg [15:0] dout,

    input             exck,        // V0 from the video counter
    output reg        timer_irq,   // level, cleared by ack

    output reg  [7:0] snd_latch,
    output reg        snd_nmi,     // level, cleared by snd_read
    input             snd_read     // Z80 read of port 0x40 (one clk pulse)
);

reg [15:0] r0, r1, r2, r3, r4, r7;
reg [11:0] reload;
reg        enable;
reg [11:0] counter;
reg [4:0]  hist_bit;        // MAME's m_bit keeps counting; bits >= 16 fall off the u16
reg        exck_d;

function automatic [15:0] merge(input [15:0] old, input [15:0] d, input [1:0] ben);
    merge = {ben[1] ? d[15:8] : old[15:8], ben[0] ? d[7:0] : old[7:0]};
endfunction

// compare result for arbitrary operands (combinational helper)
function automatic [31:0] compare(input [15:0] b1, input [15:0] b2, input [15:0] v);
    logic signed [15:0] mn, mx, sv;
    logic [15:0] r7n, r3n;
    mn = ($signed(b1) < $signed(b2)) ? $signed(b1) : $signed(b2);
    mx = ($signed(b1) > $signed(b2)) ? $signed(b1) : $signed(b2);
    sv = $signed(v);
    if (sv < mn)      begin r7n = mn; r3n = 16'h8000; end
    else if (sv > mx) begin r7n = mx; r3n = 16'h4000; end
    else              begin r7n = sv; r3n = 16'h0000; end
    compare = {r7n, r3n};
endfunction

always @(posedge clk) begin
    if (reset) begin
        r0 <= 0; r1 <= 0; r2 <= 0; r3 <= 0; r4 <= 0; r7 <= 0;
        reload <= 0; enable <= 1'b0; counter <= 0; hist_bit <= 0;
        timer_irq <= 1'b0; snd_latch <= 0; snd_nmi <= 1'b0; exck_d <= 1'b0;
    end
    else begin
        exck_d <= exck;
        if (exck && !exck_d) begin
            if (counter == 12'hFFF) begin
                timer_irq <= 1'b1;
                counter   <= reload;
            end
            else if (enable) counter <= counter + 12'd1;
        end

        if (snd_read) snd_nmi <= 1'b0;

        if (cs) begin
            if (we) begin
                logic [15:0] n0, n1, n2;
                logic [31:0] c;
                n0 = r0; n1 = r1; n2 = r2;
                case (addr)
                    4'h0: begin n0 = merge(r0, din, be); r0 <= n0; c = compare(n0, n1, n2); r7 <= c[31:16]; r3 <= c[15:0]; end
                    4'h1: begin n1 = merge(r1, din, be); r1 <= n1; c = compare(n0, n1, n2); r7 <= c[31:16]; r3 <= c[15:0]; end
                    4'h2: begin
                        n2 = merge(r2, din, be); r2 <= n2; c = compare(n0, n1, n2); r7 <= c[31:16]; r3 <= c[15:0];
                        // history: r4 |= (flags == 0) << bit++
                        if (c[15:0] == 16'd0 && !hist_bit[4]) r4 <= r4 | (16'd1 << hist_bit[3:0]);
                        if (!hist_bit[4]) hist_bit <= hist_bit + 5'd1;
                    end
                    4'h4: begin r4 <= 16'd0; hist_bit <= 5'd0; end
                    4'h6: begin n2 = merge(r2, din, be); r2 <= n2; c = compare(n0, n1, n2); r7 <= c[31:16]; r3 <= c[15:0]; end
                    4'h8, 4'hC: begin logic [15:0] t; t = merge({4'd0, reload}, din, be); reload <= t[11:0]; end
                    4'h9, 4'hD: timer_irq <= 1'b0;
                    4'hA, 4'hE: begin logic [15:0] t; t = merge({15'd0, enable}, din, be); enable <= t[0]; end
                    4'hB, 4'hF: begin snd_latch <= din[7:0]; snd_nmi <= 1'b1; end
                    default: ;
                endcase
            end
            else begin
                if (addr == 4'h9 || addr == 4'hD) timer_irq <= 1'b0;
            end
        end
    end
end

always @* begin
    case (addr)
        4'h0: dout = r0;
        4'h1: dout = r1;
        4'h2: dout = r2;
        4'h3: dout = r3;
        4'h4: dout = r4;
        4'h5: dout = r1;
        4'h6: dout = r2;
        4'h7: dout = r7;
        default: dout = 16'hFFFF;
    endcase
end
endmodule
