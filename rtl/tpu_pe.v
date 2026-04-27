`timescale 1ns/1ps
`default_nettype none

module tpu_pe #(
    parameter DATA_WIDTH = 32,
    parameter ACC_WIDTH  = 64
) (
    input  wire                               clk,
    input  wire                               rst_n,
    input  wire                               clear_acc,
    input  wire                               enable,
    input  wire signed [DATA_WIDTH-1:0]       in_a,
    input  wire signed [DATA_WIDTH-1:0]       in_b,
    input  wire                               in_valid_a,
    input  wire                               in_valid_b,
    output reg  signed [DATA_WIDTH-1:0]       out_a,
    output reg  signed [DATA_WIDTH-1:0]       out_b,
    output reg                                out_valid_a,
    output reg                                out_valid_b,
    output reg  signed [ACC_WIDTH-1:0]        acc
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_a <= {DATA_WIDTH{1'b0}};
            out_b <= {DATA_WIDTH{1'b0}};
            out_valid_a <= 1'b0;
            out_valid_b <= 1'b0;
            acc <= {ACC_WIDTH{1'b0}};
        end else begin
            if (clear_acc) begin
                out_a <= {DATA_WIDTH{1'b0}};
                out_b <= {DATA_WIDTH{1'b0}};
                out_valid_a <= 1'b0;
                out_valid_b <= 1'b0;
                acc <= {ACC_WIDTH{1'b0}};
            end else if (enable) begin
                out_a <= in_a;
                out_b <= in_b;
                out_valid_a <= in_valid_a;
                out_valid_b <= in_valid_b;

                if (in_valid_a && in_valid_b) begin
                    acc <= acc + (in_a * in_b);
                end
            end else begin
                out_a <= {DATA_WIDTH{1'b0}};
                out_b <= {DATA_WIDTH{1'b0}};
                out_valid_a <= 1'b0;
                out_valid_b <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
