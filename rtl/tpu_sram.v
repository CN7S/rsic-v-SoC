`timescale 1ns/1ps
`default_nettype none

module tpu_sram #(
    parameter ADDR_WIDTH = 2,
    parameter DATA_WIDTH = 32
) (
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      we,
    input  wire [DATA_WIDTH/8-1:0]   be,
    input  wire [ADDR_WIDTH-1:0]     addr,
    input  wire [DATA_WIDTH-1:0]     wdata,
    output wire [DATA_WIDTH-1:0]     rdata
);

    localparam integer DEPTH = (1 << ADDR_WIDTH);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    integer i;
    integer lane;

    assign rdata = mem[addr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < DEPTH; i = i + 1) begin
                mem[i] <= {DATA_WIDTH{1'b0}};
            end
        end else if (we) begin
            for (lane = 0; lane < DATA_WIDTH/8; lane = lane + 1) begin
                if (be[lane]) begin
                    mem[addr][lane*8 +: 8] <= wdata[lane*8 +: 8];
                end
            end
        end
    end

endmodule

`default_nettype wire
