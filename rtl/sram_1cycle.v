`timescale 1ns/1ps
`default_nettype none

module sram_1cycle #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32,
    parameter INIT_FILE  = ""
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    cs,
    input  wire                    we,
    input  wire [DATA_WIDTH/8-1:0] be,
    input  wire [ADDR_WIDTH-1:0]   addr,
    input  wire [DATA_WIDTH-1:0]   wdata,
    output reg  [DATA_WIDTH-1:0]   rdata
);

    localparam BYTE_LANES = DATA_WIDTH / 8;
    localparam DEPTH      = (1 << ADDR_WIDTH) / BYTE_LANES;

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    wire [ADDR_WIDTH-1:2] word_addr = addr[ADDR_WIDTH-1:2];

    integer i;
    integer lane;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1) begin
            mem[i] = {DATA_WIDTH{1'b0}};
        end

        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata <= {DATA_WIDTH{1'b0}};
        end else if (cs) begin
            rdata <= mem[word_addr];

            if (we) begin
                for (lane = 0; lane < BYTE_LANES; lane = lane + 1) begin
                    if (be[lane]) begin
                        mem[word_addr][lane*8 +: 8] <= wdata[lane*8 +: 8];
                    end
                end
            end
        end
    end

endmodule

`default_nettype wire
