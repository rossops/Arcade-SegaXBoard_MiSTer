//============================================================================
//  Byte-enabled dual-port RAM: port A (CPU clock) read/write with byte
//  enables, port B (renderer clock, may differ) read-only. Both outputs are
//  registered: data appears one clock after the address is presented.
//  Quartus 17 does not infer a two-clock byte-enabled RAM from the
//  behavioural description (it turned into flip-flops), so the hardware
//  build instantiates altsyncram explicitly, as the System 32 core does.
//============================================================================
module xb_dpram #(
    parameter AW = 13,           // word address width
    parameter INIT_FF = 0        // fill with 0xFFFF at reset (sim only)
) (
    input             clk,       // port A (CPU)
    input    [AW-1:0] a_addr,
    input      [15:0] a_din,
    input       [1:0] a_be,
    input             a_we,
    output     [15:0] a_dout,
    input             b_clk,     // port B (renderer)
    input    [AW-1:0] b_addr,
    output     [15:0] b_dout
);
`ifdef ALTERA_RESERVED_QIS
altsyncram ram (
    .clock0(clk),
    .address_a(a_addr),
    .data_a(a_din),
    .byteena_a(a_be),
    .wren_a(a_we),
    .q_a(a_dout),
    .clock1(b_clk),
    .address_b(b_addr),
    .q_b(b_dout),
    .aclr0(1'b0), .aclr1(1'b0),
    .addressstall_a(1'b0), .addressstall_b(1'b0),
    .byteena_b(1'b1),
    .clocken0(1'b1), .clocken1(1'b1), .clocken2(1'b1), .clocken3(1'b1),
    .data_b({16{1'b1}}),
    .eccstatus(),
    .rden_a(1'b1), .rden_b(1'b1),
    .wren_b(1'b0)
);
defparam
    ram.address_reg_b = "CLOCK1",
    ram.clock_enable_input_a = "BYPASS",
    ram.clock_enable_input_b = "BYPASS",
    ram.clock_enable_output_a = "BYPASS",
    ram.clock_enable_output_b = "BYPASS",
    ram.indata_reg_b = "CLOCK1",
    ram.intended_device_family = "Cyclone V",
    ram.lpm_type = "altsyncram",
    ram.numwords_a = 1 << AW,
    ram.numwords_b = 1 << AW,
    ram.operation_mode = "BIDIR_DUAL_PORT",
    ram.outdata_aclr_a = "NONE",
    ram.outdata_aclr_b = "NONE",
    ram.outdata_reg_a = "UNREGISTERED",
    ram.outdata_reg_b = "UNREGISTERED",
    ram.power_up_uninitialized = "FALSE",
    ram.read_during_write_mode_mixed_ports = "DONT_CARE",
    ram.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
    ram.width_a = 16,
    ram.width_b = 16,
    ram.width_byteena_a = 2,
    ram.width_byteena_b = 1,
    ram.widthad_a = AW,
    ram.widthad_b = AW,
    ram.wrcontrol_wraddress_reg_b = "CLOCK1";
`else
reg [15:0] mem [0:(1<<AW)-1];
reg [15:0] a_q, b_q;
assign a_dout = a_q;
assign b_dout = b_q;
`ifdef SIMULATION
integer i;
initial for (i = 0; i < (1<<AW); i = i + 1) mem[i] = INIT_FF ? 16'hFFFF : 16'h0000;
`endif
always @(posedge clk) begin
    if (a_we) begin
        if (a_be[1]) mem[a_addr][15:8] <= a_din[15:8];
        if (a_be[0]) mem[a_addr][7:0]  <= a_din[7:0];
    end
    a_q <= mem[a_addr];
end
always @(posedge b_clk) b_q <= mem[b_addr];
`endif
endmodule
