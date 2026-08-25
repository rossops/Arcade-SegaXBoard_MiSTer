//============================================================================
//  Sega 315-5242 colour section: 8192 x 16-bit palette RAM (CPU port A,
//  pixel port B) and the 5-bit resistor ladder outputs.
//  Palette word: bit 15 = effects select (1 hilight / 0 shadow), 14:12 = LSB
//  of B/G/R, 11:8 B, 7:4 G, 3:0 R (MAME paletteram_w). `effects` selects the
//  shadow/hilight bank for the pixel (sprite shadow pen).
//  Output is registered two clocks after the address.
//============================================================================
module xb_palette_5242 (
    input             clk,
    // CPU
    input      [12:0] a_addr,
    input      [15:0] a_din,
    input       [1:0] a_be,
    input             a_we,
    output     [15:0] a_dout,
    // pixel
    input      [12:0] b_addr,
    input             b_effects,
    output reg  [7:0] r, g, b
);
`include "xb_pal_lut.svh"

// palette RAM: same altsyncram form as xb_dpram (explicit for Quartus 17)
wire [15:0] word_q;
`ifdef ALTERA_RESERVED_QIS
altsyncram ram (
    .clock0(clk),
    .address_a(a_addr), .data_a(a_din), .byteena_a(a_be), .wren_a(a_we), .q_a(a_dout_w),
    .clock1(clk),
    .address_b(b_addr), .q_b(word_q),
    .aclr0(1'b0), .aclr1(1'b0), .addressstall_a(1'b0), .addressstall_b(1'b0),
    .byteena_b(1'b1), .clocken0(1'b1), .clocken1(1'b1), .clocken2(1'b1), .clocken3(1'b1),
    .data_b({16{1'b1}}), .eccstatus(), .rden_a(1'b1), .rden_b(1'b1), .wren_b(1'b0)
);
defparam
    ram.address_reg_b = "CLOCK1", ram.clock_enable_input_a = "BYPASS", ram.clock_enable_input_b = "BYPASS",
    ram.clock_enable_output_a = "BYPASS", ram.clock_enable_output_b = "BYPASS", ram.indata_reg_b = "CLOCK1",
    ram.intended_device_family = "Cyclone V", ram.lpm_type = "altsyncram",
    ram.numwords_a = 8192, ram.numwords_b = 8192, ram.operation_mode = "BIDIR_DUAL_PORT",
    ram.outdata_aclr_a = "NONE", ram.outdata_aclr_b = "NONE",
    ram.outdata_reg_a = "UNREGISTERED", ram.outdata_reg_b = "UNREGISTERED",
    ram.power_up_uninitialized = "FALSE", ram.read_during_write_mode_mixed_ports = "DONT_CARE",
    ram.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
    ram.width_a = 16, ram.width_b = 16, ram.width_byteena_a = 2, ram.width_byteena_b = 1,
    ram.widthad_a = 13, ram.widthad_b = 13, ram.wrcontrol_wraddress_reg_b = "CLOCK1";
wire [15:0] a_dout_w;
assign a_dout = a_dout_w;                   // q_a is already the registered read
`else
reg [15:0] mem [0:8191];
reg [15:0] word_r, a_q;
assign a_dout = a_q;
`ifdef SIMULATION
integer i;
initial for (i = 0; i < 8192; i = i + 1) mem[i] = 16'h0000;
`endif
always @(posedge clk) begin
    if (a_we) begin
        if (a_be[1]) mem[a_addr][15:8] <= a_din[15:8];
        if (a_be[0]) mem[a_addr][7:0]  <= a_din[7:0];
    end
    a_q    <= mem[a_addr];
    word_r <= mem[b_addr];
end
assign word_q = word_r;
`endif
reg [15:0] word;
reg        eff_d;
always @(posedge clk) begin
    word  <= word_q;
    eff_d <= b_effects;
end

wire [4:0] r5 = {word[3:0],  word[12]};
wire [4:0] g5 = {word[7:4],  word[13]};
wire [4:0] b5 = {word[11:8], word[14]};
always @(posedge clk) begin
    if (!eff_d)        begin r <= pal_normal(r5);  g <= pal_normal(g5);  b <= pal_normal(b5);  end
    else if (word[15]) begin r <= pal_hilight(r5); g <= pal_hilight(g5); b <= pal_hilight(b5); end
    else               begin r <= pal_shadow(r5);  g <= pal_shadow(g5);  b <= pal_shadow(b5);  end
end
endmodule
