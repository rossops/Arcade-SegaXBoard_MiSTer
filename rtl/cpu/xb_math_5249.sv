//============================================================================
//  Sega 315-5249 hardware divider (one per 68000 on the X Board)
//  Word offsets (address bits 4:1):
//    0 dividend high, 1 dividend low, 2 divisor (r/w); 4 quotient / quotient
//    high, 5 remainder / quotient low, 6 flags (read-only).
//  A write with address bit 4 (offset & 8) set triggers the division; bit 3
//  (offset & 4) selects the mode: 0 = signed 32/16 with the quotient clamped
//  to 16 bits (flag 0x8000 on overflow), 1 = unsigned 32/16 with a 32-bit
//  quotient. Divide by zero: quotient = dividend, flag 0x4000.
//  Reference: MAME segaic16_m.cpp sega_315_5249_divider_device::execute.
//
//  The division is a restoring divider, 4 quotient bits per clock (8 clocks
//  = 160 ns at 50 MHz). Games read the quotient with the very next
//  instruction, i.e. >= 4 CPU clocks (320 ns) after the trigger write, so the
//  real chip answers at least that fast and this never stalls in practice.
//  As a safety net a read of offsets 4..6 while busy still holds DTACK.
//============================================================================
module xb_math_5249 (
    input             clk,
    input             reset,
    input             cs,
    input             we,
    input       [3:0] addr,        // word offset (address bits 4:1)
    input      [15:0] din,
    input       [1:0] be,
    output reg [15:0] dout,
    output            rdy          // low while a result read must wait
);

reg [15:0] dividend_hi, dividend_lo, divisor;
reg [15:0] quot_hi, quot_lo, flags;

// division engine
reg        busy;
reg        mode_r;          // 0 signed, 1 unsigned
reg [5:0]  step;
reg [31:0] q;               // quotient magnitude being built
reg [32:0] rem;             // partial remainder (33 bits for the trial subtract)
reg [31:0] dvd_abs;
reg [15:0] dvs_abs;
reg        neg_q, neg_r;
reg        div_zero;
reg [31:0] dividend_saved;
reg [15:0] divisor_saved;

wire trigger = cs && we && addr[3];
wire [31:0] dividend = {dividend_hi, dividend_lo};

// sign handling for signed mode
wire [31:0] dvd_mag = (!addr[2] && dividend[31]) ? (~dividend + 32'd1) : dividend;
wire [15:0] dvs_mag = (!addr[2] && divisor[15])  ? (~divisor + 16'd1)  : divisor;

assign rdy = !(busy && cs && !we && addr[2]);

always @(posedge clk) begin
    if (reset) begin
        dividend_hi <= 0; dividend_lo <= 0; divisor <= 0;
        quot_hi <= 0; quot_lo <= 0; flags <= 0;
        busy <= 1'b0; step <= 0; q <= 0; rem <= 0;
        dvd_abs <= 0; dvs_abs <= 0; neg_q <= 0; neg_r <= 0; div_zero <= 0;
        mode_r <= 0; dividend_saved <= 0; divisor_saved <= 0;
    end
    else begin
        if (cs && we) begin
            case (addr[1:0])
                2'd0: begin if (be[1]) dividend_hi[15:8] <= din[15:8]; if (be[0]) dividend_hi[7:0] <= din[7:0]; end
                2'd1: begin if (be[1]) dividend_lo[15:8] <= din[15:8]; if (be[0]) dividend_lo[7:0] <= din[7:0]; end
                2'd2: begin if (be[1]) divisor[15:8]     <= din[15:8]; if (be[0]) divisor[7:0]     <= din[7:0]; end
                default: ;
            endcase
        end

        if (trigger) begin
            // operands as they are after this same write (MAME updates the
            // register first, then executes)
            logic [31:0] dvd_now;
            logic [15:0] dvs_now;
            dvd_now = dividend;
            dvs_now = divisor;
            case (addr[1:0])
                2'd0: begin if (be[1]) dvd_now[31:24] = din[15:8]; if (be[0]) dvd_now[23:16] = din[7:0]; end
                2'd1: begin if (be[1]) dvd_now[15:8]  = din[15:8]; if (be[0]) dvd_now[7:0]   = din[7:0]; end
                2'd2: begin if (be[1]) dvs_now[15:8]  = din[15:8]; if (be[0]) dvs_now[7:0]   = din[7:0]; end
                default: ;
            endcase
            mode_r   <= addr[2];
            div_zero <= (dvs_now == 16'd0);
            dividend_saved <= dvd_now;
            divisor_saved  <= dvs_now;
            if (!addr[2]) begin
                dvd_abs <= dvd_now[31] ? (~dvd_now + 32'd1) : dvd_now;
                dvs_abs <= dvs_now[15] ? (~dvs_now + 16'd1) : dvs_now;
                neg_q   <= dvd_now[31] ^ dvs_now[15];
                neg_r   <= dvd_now[31];
            end
            else begin
                dvd_abs <= dvd_now;
                dvs_abs <= dvs_now;
                neg_q   <= 1'b0;
                neg_r   <= 1'b0;
            end
            q    <= 32'd0;
            rem  <= 33'd0;
            step <= 6'd0;
            busy <= 1'b1;
        end
        else if (busy) begin
            if (step < 6'd32) begin
                // restoring division, MSB first, four bits per clock
                logic [32:0] r, trial;
                logic [31:0] qq;
                integer k;
                r  = rem;
                qq = q;
                for (k = 0; k < 4; k = k + 1) begin
                    trial = {r[31:0], dvd_abs[31 - (step + k[5:0])]} - {17'd0, dvs_abs};
                    if (!trial[32]) begin r = trial;                                  qq = {qq[30:0], 1'b1}; end
                    else            begin r = {r[31:0], dvd_abs[31 - (step + k[5:0])]}; qq = {qq[30:0], 1'b0}; end
                end
                rem  <= r;
                q    <= qq;
                step <= step + 6'd4;
            end
            else begin
                busy <= 1'b0;
                flags <= 16'd0;
                if (div_zero) begin
                    // quotient = dividend, remainder computed from that
                    flags <= 16'h4000;
                    if (!mode_r) begin
                        logic signed [31:0] qz;
                        qz = $signed(dividend_saved);
                        if (qz < -32768)     begin quot_hi <= 16'h8000; flags <= 16'hC000; end
                        else if (qz > 32767) begin quot_hi <= 16'h7FFF; flags <= 16'hC000; end
                        else                  quot_hi <= qz[15:0];
                        // remainder = dividend - quotient*0 = dividend (low 16)
                        quot_lo <= dividend_saved[15:0];
                    end
                    else begin
                        quot_hi <= dividend_saved[31:16];
                        quot_lo <= dividend_saved[15:0];
                    end
                end
                else if (!mode_r) begin
                    logic signed [32:0] qs;
                    logic signed [32:0] rs;
                    qs = neg_q ? -$signed({1'b0, q}) : $signed({1'b0, q});
                    rs = neg_r ? -$signed({1'b0, rem[31:0]}) : $signed({1'b0, rem[31:0]});
                    if (qs < -32768) begin
                        quot_hi <= 16'h8000; flags <= 16'h8000;
                        // MAME: remainder = dividend - clamped_q * divisor
                        quot_lo <= dividend_saved[15:0] - (16'h8000 * divisor_saved);
                    end
                    else if (qs > 32767) begin
                        quot_hi <= 16'h7FFF; flags <= 16'h8000;
                        quot_lo <= dividend_saved[15:0] - (16'h7FFF * divisor_saved);
                    end
                    else begin
                        quot_hi <= qs[15:0];
                        quot_lo <= rs[15:0];
                    end
                end
                else begin
                    quot_hi <= q[31:16];
                    quot_lo <= q[15:0];
                end
            end
        end
    end
end

always @* begin
    case (addr[2:0])
        3'd0: dout = dividend_hi;
        3'd1: dout = dividend_lo;
        3'd2: dout = divisor;
        3'd4: dout = quot_hi;
        3'd5: dout = quot_lo;
        3'd6: dout = flags;
        default: dout = 16'hFFFF;
    endcase
end
endmodule
