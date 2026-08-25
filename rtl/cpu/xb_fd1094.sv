//============================================================================
//  Hitachi FD1094 (encrypted 68000) decryption block, sitting on the main
//  CPU's program ROM path between the ROM cache and the bus. The ctrl and
//  dec modules are jtcores' (Jose Tejada, GPL-3, rtl/cpu/fd1094/); this
//  wrapper adds the 8 KB key RAM (filled by the ROM loader from the stream's
//  key region), the function-code decode and the one-clock ack delay the
//  registered decryptor output needs. Program-space reads are decrypted,
//  data reads pass through; with `enable` low the block is transparent and
//  adds no latency.
//============================================================================
module xb_fd1094 (
    input             clk,
    input             reset,
    input             enable,

    // key RAM load
    input             key_wr,
    input      [12:0] key_waddr,
    input       [7:0] key_wdata,

    // bus side
    input       [2:0] fc,
    input             as_n,
    input      [23:1] addr,
    input      [15:0] enc,
    input             ack_in,       // ROM cache data valid (level)
    output     [15:0] dec,
    output            ack_out
);

reg  [7:0] key_ram [0:8191];
reg  [7:0] key_q;
wire [12:0] key_addr;
always @(posedge clk) begin
    if (key_wr) key_ram[key_waddr] <= key_wdata;
    key_q <= key_ram[key_addr];
end

wire inta_n   = ~&{fc[2], fc[1], fc[0], ~as_n};   // interrupt acknowledge cycle
wire vrq      = ~&fc;
wire op_n     = (fc[1:0] != 2'b10);                // 0: program space
wire sup_prog = (fc == 3'd6);
wire [7:0] st, gkey0;
wire       ok_dly;
wire [15:0] dec_w;

jts16_fd1094_ctrl u_ctrl (
    .rst(reset), .clk(clk),
    .inta_n(inta_n), .op_n(op_n),
    .addr(addr), .dec(dec_w), .gkey0(gkey0),
    .sup_prog(sup_prog), .dtackn(~ack_out), .st(st)
);

// the decryptor captures the global key bytes 0..3 from the key writes;
// in simulation the +keyrom preload replays those four writes
reg         sim_we = 1'b0;
reg  [12:0] sim_addr = 13'd0;
reg   [7:0] sim_data = 8'd0;
jts16_fd1094_dec #(.SIMFILE("")) u_dec (
    .rst(reset), .clk(clk),
    .key_addr(key_addr), .key_data(key_q),
    .prog_addr(key_wr ? key_waddr : sim_addr), .fd1094_we(key_wr | sim_we), .prog_data(key_wr ? key_wdata : sim_data),
    .dec_en(enable), .vrq(vrq), .st(st), .gkey0(gkey0),
    .op_n(op_n), .addr(addr), .enc(enc), .dec(dec_w),
    .rom_ok(ack_in), .ok_dly(ok_dly)
);

assign dec     = dec_w;
assign ack_out = ack_in && (ok_dly || !enable);

`ifdef SIMULATION
// +keyrom: preload the key (keyrom.hex, one byte per line) instead of the loader
integer sim_i;
initial if ($test$plusargs("keyrom")) begin
    $readmemh("keyrom.hex", key_ram);
    repeat (4) @(posedge clk);
    for (sim_i = 0; sim_i < 4; sim_i = sim_i + 1) begin
        @(posedge clk);
        sim_we <= 1'b1; sim_addr <= sim_i[12:0]; sim_data <= key_ram[sim_i];
    end
    @(posedge clk);
    sim_we <= 1'b0;
end
`endif

endmodule
