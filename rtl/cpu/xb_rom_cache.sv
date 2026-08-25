//============================================================================
//  Read-only direct-mapped cache in front of an SDRAM 4-word burst port.
//  LINES lines x 8 bytes. Address bits [2:1] select the word inside the
//  line, the next log2(LINES) bits the line, the rest the tag.
//  cpu_req is a level (held while the CPU waits); cpu_ack is a level that
//  follows cpu_req once data is valid, so it plugs straight into the
//  xb_m68k_bus ack. Adapted from the System 32 V25 ROM cache.
//  The SDRAM port follows the sdram.sv contract: one transaction per rising
//  edge of rom_req; rom_ack is a 2-clk_ram (1 clk_sys) pulse.
//============================================================================
module xb_rom_cache #(
    parameter AW    = 19,      // CPU address bits [AW:1]
    parameter LINES = 512
) (
    input             clk,
    input             reset,
    input             invalidate,

    input             cpu_req,
    input    [AW:1]   cpu_addr,
    output reg [15:0] cpu_data,
    output            cpu_ack,

    output reg        rom_req,
    output reg [AW:3] rom_addr,
    input      [63:0] rom_data,
    input             rom_ack
);

localparam IW = $clog2(LINES);
localparam TW = AW - 2 - IW;

// line storage: data and tags in RAM. Quartus 17 inferred flip-flops for
// one of the two 68000 caches (16k ALMs), so the hardware build instantiates
// altsyncram explicitly; simulation keeps the arrays.
reg [LINES-1:0] line_valid;
wire [IW-1:0] idx = cpu_addr[IW+2:3];
wire [TW-1:0] tag = cpu_addr[AW:IW+3];

reg        miss_pending;
reg [IW-1:0] miss_idx;
reg [TW-1:0] miss_tag;
reg        hit_r;
reg [AW:1] served_addr;
wire       fill = rom_ack && miss_pending;

wire [63:0]   rd_line;     // line at idx, one clock after idx (registered read)
wire [TW-1:0] rd_tag;
`ifdef ALTERA_RESERVED_QIS
altsyncram data_ram (
    .clock0(clk), .address_a(miss_idx), .data_a(rom_data), .wren_a(fill),
    .clock1(clk), .address_b(idx), .q_b(rd_line),
    .aclr0(1'b0), .aclr1(1'b0), .addressstall_a(1'b0), .addressstall_b(1'b0),
    .byteena_a(1'b1), .byteena_b(1'b1), .clocken0(1'b1), .clocken1(1'b1), .clocken2(1'b1), .clocken3(1'b1),
    .data_b({64{1'b1}}), .eccstatus(), .q_a(), .rden_a(1'b1), .rden_b(1'b1), .wren_b(1'b0)
);
defparam data_ram.address_reg_b = "CLOCK1", data_ram.clock_enable_input_a = "BYPASS", data_ram.clock_enable_input_b = "BYPASS",
    data_ram.clock_enable_output_b = "BYPASS", data_ram.intended_device_family = "Cyclone V", data_ram.lpm_type = "altsyncram",
    data_ram.numwords_a = LINES, data_ram.numwords_b = LINES, data_ram.operation_mode = "DUAL_PORT",
    data_ram.outdata_aclr_b = "NONE", data_ram.outdata_reg_b = "UNREGISTERED", data_ram.power_up_uninitialized = "FALSE",
    data_ram.read_during_write_mode_mixed_ports = "DONT_CARE", data_ram.width_a = 64, data_ram.width_b = 64,
    data_ram.widthad_a = IW, data_ram.widthad_b = IW, data_ram.width_byteena_a = 1;
altsyncram tag_ram (
    .clock0(clk), .address_a(miss_idx), .data_a(miss_tag), .wren_a(fill),
    .clock1(clk), .address_b(idx), .q_b(rd_tag),
    .aclr0(1'b0), .aclr1(1'b0), .addressstall_a(1'b0), .addressstall_b(1'b0),
    .byteena_a(1'b1), .byteena_b(1'b1), .clocken0(1'b1), .clocken1(1'b1), .clocken2(1'b1), .clocken3(1'b1),
    .data_b({TW{1'b1}}), .eccstatus(), .q_a(), .rden_a(1'b1), .rden_b(1'b1), .wren_b(1'b0)
);
defparam tag_ram.address_reg_b = "CLOCK1", tag_ram.clock_enable_input_a = "BYPASS", tag_ram.clock_enable_input_b = "BYPASS",
    tag_ram.clock_enable_output_b = "BYPASS", tag_ram.intended_device_family = "Cyclone V", tag_ram.lpm_type = "altsyncram",
    tag_ram.numwords_a = LINES, tag_ram.numwords_b = LINES, tag_ram.operation_mode = "DUAL_PORT",
    tag_ram.outdata_aclr_b = "NONE", tag_ram.outdata_reg_b = "UNREGISTERED", tag_ram.power_up_uninitialized = "FALSE",
    tag_ram.read_during_write_mode_mixed_ports = "DONT_CARE", tag_ram.width_a = TW, tag_ram.width_b = TW,
    tag_ram.widthad_a = IW, tag_ram.widthad_b = IW, tag_ram.width_byteena_a = 1;
`else
reg [63:0]   line_data [0:LINES-1];
reg [TW-1:0] line_tag  [0:LINES-1];
reg [63:0]   rd_line_r;
reg [TW-1:0] rd_tag_r;
always @(posedge clk) begin
    if (fill) begin line_data[miss_idx] <= rom_data; line_tag[miss_idx] <= miss_tag; end
    rd_line_r <= line_data[idx];
    rd_tag_r  <= line_tag[idx];
end
assign rd_line = rd_line_r;
assign rd_tag  = rd_tag_r;
`endif

// the registered RAM read means the hit decision is for the address
// presented one clock earlier; hold it and compare with the current one
reg [IW-1:0] idx_d;
reg [TW-1:0] tag_d;
reg          req_d;
reg [AW:1]   addr_d;
always @(posedge clk) begin idx_d <= idx; tag_d <= tag; req_d <= cpu_req; addr_d <= cpu_addr; end
wire hit_now = req_d && line_valid[idx_d] && (rd_tag == tag_d) && !(fill && miss_idx == idx_d);

function automatic [15:0] sel(input [63:0] l, input [1:0] w);
    case (w)
        2'd0: sel = l[15:0];
        2'd1: sel = l[31:16];
        2'd2: sel = l[47:32];
        default: sel = l[63:48];
    endcase
endfunction

// ack is a level: valid while the same request is held and the line is present
assign cpu_ack = cpu_req && hit_r && (served_addr == cpu_addr);

always @(posedge clk) begin
    rom_req <= 1'b0;
    if (reset) begin
        line_valid <= '0;
        miss_pending <= 1'b0;
        hit_r <= 1'b0;
        served_addr <= '0;
    end
    else begin
        if (invalidate) line_valid <= '0;

        if (fill) begin
            miss_pending <= 1'b0;
            line_valid[miss_idx] <= 1'b1;
        end

        // decision for the request presented one clock ago (RAM read latency).
        // A request already served is not re-decided: the RAM read right after
        // a fill is stale for a clock and would otherwise restart the miss.
        if (req_d && cpu_req && addr_d == cpu_addr && !(hit_r && served_addr == addr_d)) begin
            if (fill && miss_idx == idx_d && miss_tag == tag_d) begin
                // the line being filled is the one requested: serve it from the fill
                cpu_data    <= sel(rom_data, addr_d[2:1]);
                hit_r       <= 1'b1;
                served_addr <= addr_d;
            end
            else if (hit_now) begin
                cpu_data    <= sel(rd_line, addr_d[2:1]);
                hit_r       <= 1'b1;
                served_addr <= addr_d;
            end
            else begin
                hit_r <= 1'b0;
                if (!miss_pending) begin
                    miss_pending <= 1'b1;
                    miss_idx     <= idx_d;
                    miss_tag     <= tag_d;
                    rom_addr     <= addr_d[AW:3];
                    rom_req      <= 1'b1;
                end
            end
        end
        else if (!cpu_req) hit_r <= 1'b0;
    end
end
endmodule
