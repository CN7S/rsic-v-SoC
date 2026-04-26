`timescale 1ns/1ps
`default_nettype none

module tensorpu #(
    parameter CALC_LATENCY = 4
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cs,
    input  wire        we,
    input  wire [3:0]  be,
    input  wire [7:0]  addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    output reg         busy,
    output reg         done
);

    localparam [7:0] REG_CONTROL = 8'h00;
    localparam [7:0] REG_STATUS  = 8'h04;
    localparam [7:0] REG_A00     = 8'h10;
    localparam [7:0] REG_A01     = 8'h14;
    localparam [7:0] REG_A10     = 8'h18;
    localparam [7:0] REG_A11     = 8'h1c;
    localparam [7:0] REG_B00     = 8'h20;
    localparam [7:0] REG_B01     = 8'h24;
    localparam [7:0] REG_B10     = 8'h28;
    localparam [7:0] REG_B11     = 8'h2c;
    localparam [7:0] REG_C00     = 8'h40;
    localparam [7:0] REG_C01     = 8'h44;
    localparam [7:0] REG_C10     = 8'h48;
    localparam [7:0] REG_C11     = 8'h4c;

    reg signed [31:0] a00;
    reg signed [31:0] a01;
    reg signed [31:0] a10;
    reg signed [31:0] a11;
    reg signed [31:0] b00;
    reg signed [31:0] b01;
    reg signed [31:0] b10;
    reg signed [31:0] b11;
    reg signed [31:0] c00;
    reg signed [31:0] c01;
    reg signed [31:0] c10;
    reg signed [31:0] c11;

    reg [7:0] cycles_left;

    function [31:0] merge_bytes;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0]  byte_en;
        integer lane;
        begin
            merge_bytes = old_value;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                if (byte_en[lane]) begin
                    merge_bytes[lane*8 +: 8] = new_value[lane*8 +: 8];
                end
            end
        end
    endfunction

    function signed [31:0] dot2;
        input signed [31:0] lhs0;
        input signed [31:0] rhs0;
        input signed [31:0] lhs1;
        input signed [31:0] rhs1;
        reg signed [63:0] sum;
        begin
            sum = (lhs0 * rhs0) + (lhs1 * rhs1);
            dot2 = sum[31:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata <= 32'd0;
            busy <= 1'b0;
            done <= 1'b0;
            cycles_left <= 8'd0;
            a00 <= 32'sd0;
            a01 <= 32'sd0;
            a10 <= 32'sd0;
            a11 <= 32'sd0;
            b00 <= 32'sd0;
            b01 <= 32'sd0;
            b10 <= 32'sd0;
            b11 <= 32'sd0;
            c00 <= 32'sd0;
            c01 <= 32'sd0;
            c10 <= 32'sd0;
            c11 <= 32'sd0;
        end else begin
            if (busy) begin
                if (cycles_left <= 8'd1) begin
                    c00 <= dot2(a00, b00, a01, b10);
                    c01 <= dot2(a00, b01, a01, b11);
                    c10 <= dot2(a10, b00, a11, b10);
                    c11 <= dot2(a10, b01, a11, b11);
                    busy <= 1'b0;
                    done <= 1'b1;
                    cycles_left <= 8'd0;
                end else begin
                    cycles_left <= cycles_left - 8'd1;
                end
            end

            if (cs && we) begin
                case (addr)
                    REG_CONTROL: begin
                        if (be[0] && wdata[1]) begin
                            done <= 1'b0;
                        end

                        if (be[0] && wdata[0] && !busy) begin
                            busy <= 1'b1;
                            done <= 1'b0;
                            cycles_left <= CALC_LATENCY[7:0];
                        end
                    end
                    REG_A00: a00 <= merge_bytes(a00, wdata, be);
                    REG_A01: a01 <= merge_bytes(a01, wdata, be);
                    REG_A10: a10 <= merge_bytes(a10, wdata, be);
                    REG_A11: a11 <= merge_bytes(a11, wdata, be);
                    REG_B00: b00 <= merge_bytes(b00, wdata, be);
                    REG_B01: b01 <= merge_bytes(b01, wdata, be);
                    REG_B10: b10 <= merge_bytes(b10, wdata, be);
                    REG_B11: b11 <= merge_bytes(b11, wdata, be);
                    default: begin
                    end
                endcase
            end

            if (cs && !we) begin
                case (addr)
                    REG_CONTROL: rdata <= {30'd0, done, busy};
                    REG_STATUS:  rdata <= {30'd0, done, busy};
                    REG_A00:     rdata <= a00;
                    REG_A01:     rdata <= a01;
                    REG_A10:     rdata <= a10;
                    REG_A11:     rdata <= a11;
                    REG_B00:     rdata <= b00;
                    REG_B01:     rdata <= b01;
                    REG_B10:     rdata <= b10;
                    REG_B11:     rdata <= b11;
                    REG_C00:     rdata <= c00;
                    REG_C01:     rdata <= c01;
                    REG_C10:     rdata <= c10;
                    REG_C11:     rdata <= c11;
                    default:     rdata <= 32'd0;
                endcase
            end
        end
    end

endmodule

`default_nettype wire
