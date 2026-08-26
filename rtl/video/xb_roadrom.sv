//============================================================================
//  Road ROM (64 KB) in BRAM, filled by the ROM loader; two read ports so a
//  road's two bitplanes (plane 1 at +0x4000) are fetched in one clock.
//  One true-dual-port altsyncram (port A: loader write / read 0, port B:
//  read 1). Described behaviourally the array got duplicated for the third
//  port (96 M10K instead of 64), which broke the M10K budget in M14. The
//  loader writes only while the core is held in reset, so port A never has
//  a live read to lose to a write.
//============================================================================
module xb_roadrom (
    input             clk,
    input             wr,
    input      [15:0] wr_addr,
    input       [7:0] wr_data,
    input      [15:0] rd_addr0,
    input      [15:0] rd_addr1,
    output      [7:0] rd_q0,
    output      [7:0] rd_q1
);
`ifdef ALTERA_RESERVED_QIS
altsyncram ram (
    .clock0(clk),
    .address_a(wr ? wr_addr : rd_addr0),
    .data_a(wr_data),
    .wren_a(wr),
    .q_a(rd_q0),
    .address_b(rd_addr1),
    .q_b(rd_q1),
    .aclr0(1'b0), .aclr1(1'b0),
    .addressstall_a(1'b0), .addressstall_b(1'b0),
    .byteena_a(1'b1), .byteena_b(1'b1),
    .clock1(1'b1),
    .clocken0(1'b1), .clocken1(1'b1), .clocken2(1'b1), .clocken3(1'b1),
    .data_b({8{1'b1}}),
    .eccstatus(),
    .rden_a(1'b1), .rden_b(1'b1),
    .wren_b(1'b0)
);
defparam
    ram.address_reg_b = "CLOCK0",
    ram.clock_enable_input_a = "BYPASS",
    ram.clock_enable_input_b = "BYPASS",
    ram.clock_enable_output_a = "BYPASS",
    ram.clock_enable_output_b = "BYPASS",
    ram.indata_reg_b = "CLOCK0",
    ram.intended_device_family = "Cyclone V",
    ram.lpm_type = "altsyncram",
    ram.numwords_a = 65536,
    ram.numwords_b = 65536,
    ram.operation_mode = "BIDIR_DUAL_PORT",
    ram.outdata_aclr_a = "NONE",
    ram.outdata_aclr_b = "NONE",
    ram.outdata_reg_a = "UNREGISTERED",
    ram.outdata_reg_b = "UNREGISTERED",
    ram.power_up_uninitialized = "FALSE",
    ram.read_during_write_mode_mixed_ports = "DONT_CARE",
    ram.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
    ram.width_a = 8,
    ram.width_b = 8,
    ram.width_byteena_a = 1,
    ram.width_byteena_b = 1,
    ram.widthad_a = 16,
    ram.widthad_b = 16,
    ram.wrcontrol_wraddress_reg_b = "CLOCK0";
`else
reg [7:0] rom [0:65535];
reg [7:0] q0, q1;
assign rd_q0 = q0;
assign rd_q1 = q1;
`ifdef SIMULATION
initial if ($test$plusargs("roadrom")) $readmemh("roadrom.hex", rom);
`endif
always @(posedge clk) begin
    if (wr) rom[wr_addr] <= wr_data;
    q0 <= rom[rd_addr0];
    q1 <= rom[rd_addr1];
end
`endif
endmodule
