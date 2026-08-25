//============================================================================
//  fx68k wrapper: two-phase enables from a /4 clock enable, a simple
//  request/acknowledge bus for the board decoders, and autovectored
//  interrupts (the X Board ties VPA low for interrupt acknowledge cycles).
//
//  clk_sys 50 MHz, CPU 12.5 MHz: enPhi1 on phase 0, enPhi2 on phase 2.
//  Bus contract towards the board:
//    bus_valid   high from the clk after ASn falls until ASn rises
//    bus_start   one-clk pulse on the first bus_valid clk (decoders sample)
//    bus_rd/wr   read or write cycle; bus_be = {UDS, LDS}
//    bus_ack     board asserts (level) when read data is valid / write taken;
//                DTACKn follows it until ASn negates
//  Interrupt acknowledge cycles (FC = 7) are autovectored via VPAn and are not
//  presented to the board.
//============================================================================
module xb_m68k_bus (
    input             clk,
    input             reset,           // sync reset (also pwrUp)
    input             ce_phase,        // /4 phase counter bit pattern supplied outside
    input       [1:0] phase,

    input       [2:0] ipl,             // active-high level (0..7), encoded
    input             halt_n,          // 0 = hold the CPU (bus request grant from the other CPU)

    output     [23:1] bus_addr,
    output            bus_valid,
    output reg        bus_start,
    output            bus_rd,
    output            bus_wr,
    output      [1:0] bus_be,
    output     [15:0] bus_dout,        // CPU -> board
    input      [15:0] bus_din,         // board -> CPU
    input             bus_ack,

    output            reset_out,       // 1 while the CPU executes RESET (drives /RESET to peripherals)

    // trace (sim)
    output      [2:0] fc,
    output            bus_as_n         // raw AS (interrupt acknowledge cycles too)
);

wire en1 = ce_phase && (phase == 2'd0);
wire en2 = ce_phase && (phase == 2'd2);

wire ASn, UDSn, LDSn, eRWn, VPAn_unused, E, VMAn, BGn, oRESETn, oHALTEDn;
wire FC0, FC1, FC2;
wire [15:0] iEdb, oEdb;
wire [23:1] eab;

assign fc = {FC2, FC1, FC0};
assign bus_as_n = ASn;
assign reset_out = ~oRESETn;
wire iack = (fc == 3'b111);

// autovector: VPAn low during interrupt acknowledge; DTACK from the board
wire vpa_n   = ~(iack && !ASn);
wire dtack_n = ~(bus_ack && !ASn && !iack);

// A cycle is presented to the board once AS is low and, for writes, the data
// strobes are asserted too (the 68000 asserts UDS/LDS one state after AS on
// writes, with the data bus driven by then).
wire cyc = !ASn && !iack && (eRWn || !(UDSn && LDSn));
reg  cyc_d;
always @(posedge clk) begin
    if (reset) begin cyc_d <= 1'b0; bus_start <= 1'b0; end
    else begin
        cyc_d <= cyc;
        bus_start <= cyc && !cyc_d;
    end
end

assign bus_valid = cyc;
assign bus_addr  = eab;
assign bus_rd    = bus_valid && eRWn;
assign bus_wr    = bus_valid && !eRWn;
assign bus_be    = {~UDSn, ~LDSn};
assign bus_dout  = oEdb;
assign iEdb      = bus_din;

// fx68k IPL inputs are active low, individually
wire [2:0] ipl_n = ~ipl;

fx68k cpu (
    .clk(clk),
    .HALTn(halt_n),
    .extReset(reset),
    .pwrUp(reset),
    .enPhi1(en1), .enPhi2(en2),
    .eRWn(eRWn), .ASn(ASn), .LDSn(LDSn), .UDSn(UDSn),
    .E(E), .VMAn(VMAn),
    .FC0(FC0), .FC1(FC1), .FC2(FC2),
    .BGn(BGn),
    .oRESETn(oRESETn), .oHALTEDn(oHALTEDn),
    .DTACKn(dtack_n), .VPAn(vpa_n),
    .BERRn(1'b1),
    .BRn(1'b1), .BGACKn(1'b1),
    .IPL0n(ipl_n[0]), .IPL1n(ipl_n[1]), .IPL2n(ipl_n[2]),
    .iEdb(iEdb), .oEdb(oEdb),
    .eab(eab)
);
endmodule
