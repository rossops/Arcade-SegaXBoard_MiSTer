//============================================================================
//  ADC0804 (IC165) with the X Board's 8-way analog multiplexer
//  A write starts a conversion (ignored while one is running); 74 ADC clocks
//  later (ADC clock = 68000 E = 1.25 MHz -> 59.2 us) the result is latched
//  and /INTR asserts. A read returns the last result and clears /INTR.
//  Channel select = I/O chip #1 port C bits 4:2 (MAME, from the schematic).
//  Reference MAME adc0804.cpp + segaxbd.cpp analog_r.
//============================================================================
module xb_adc0804 (
    input             clk,
    input             reset,
    input             ce_adc,      // 1.25 MHz enable
    input             cs,
    input             we,
    output      [7:0] dout,
    output            intr,        // active high "conversion done" (PORT A bit 6)

    input       [2:0] channel,
    input       [7:0] adc_reverse, // descriptor: channel n reads 255 - value
    input       [7:0] ch0, ch1, ch2, ch3, ch4, ch5, ch6, ch7
);

reg [7:0] result;
reg       busy;
reg [6:0] count;
reg       intr_r;

wire [7:0] sel = channel == 3'd0 ? ch0 : channel == 3'd1 ? ch1 : channel == 3'd2 ? ch2 :
                 channel == 3'd3 ? ch3 : channel == 3'd4 ? ch4 : channel == 3'd5 ? ch5 :
                 channel == 3'd6 ? ch6 : ch7;
wire [7:0] vin = adc_reverse[channel] ? (8'd255 - sel) : sel;

assign dout = result;
assign intr = intr_r;

always @(posedge clk) begin
    if (reset) begin
        result <= 8'd0; busy <= 1'b0; count <= 7'd0; intr_r <= 1'b0;
    end
    else begin
        if (cs && we && !busy) begin
            busy  <= 1'b1;
            count <= 7'd0;
        end
        if (cs && !we) intr_r <= 1'b0;
        if (busy && ce_adc) begin
            if (count == 7'd73) begin
                busy   <= 1'b0;
                result <= vin;      // sampled at end of conversion (MAME)
                intr_r <= 1'b1;
            end
            else count <= count + 7'd1;
        end
    end
end
endmodule
