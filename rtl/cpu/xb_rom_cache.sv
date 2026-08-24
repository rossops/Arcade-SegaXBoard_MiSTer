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

reg [63:0] line_data [0:LINES-1];
reg [TW-1:0] line_tag [0:LINES-1];
reg [LINES-1:0] line_valid;

wire [IW-1:0] idx = cpu_addr[IW+2:3];
wire [TW-1:0] tag = cpu_addr[AW:IW+3];

reg        miss_pending;
reg [IW-1:0] miss_idx;
reg [TW-1:0] miss_tag;
reg        hit_r;
reg [AW:1] served_addr;

wire hit_now = line_valid[idx] && (line_tag[idx] == tag);

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

        if (rom_ack && miss_pending) begin
            miss_pending <= 1'b0;
            line_data[miss_idx]  <= rom_data;
            line_tag[miss_idx]   <= miss_tag;
            line_valid[miss_idx] <= 1'b1;
        end

        if (cpu_req) begin
            if (hit_now) begin
                cpu_data    <= sel(line_data[idx], cpu_addr[2:1]);
                hit_r       <= 1'b1;
                served_addr <= cpu_addr;
            end
            else begin
                hit_r <= 1'b0;
                if (!miss_pending) begin
                    miss_pending <= 1'b1;
                    miss_idx     <= idx;
                    miss_tag     <= tag;
                    rom_addr     <= cpu_addr[AW:3];
                    rom_req      <= 1'b1;
                end
            end
        end
        else hit_r <= 1'b0;
    end
end
endmodule
