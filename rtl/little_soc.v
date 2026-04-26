`timescale 1ns/1ps
`default_nettype none

module little_soc #(
    parameter SRAM_ADDR_WIDTH = 16,
    parameter SRAM_INIT_FILE  = ""
) (
    input  wire clk,
    input  wire rst_n,
    output wire halted,
    output wire [31:0] debug_pc
);

    wire        mem_cs;
    wire        mem_we;
    wire [3:0]  mem_be;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [31:0] mem_rdata;

    rv32i_core u_cpu (
        .clk       (clk),
        .rst_n     (rst_n),
        .mem_cs    (mem_cs),
        .mem_we    (mem_we),
        .mem_be    (mem_be),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_rdata (mem_rdata),
        .halted    (halted),
        .debug_pc  (debug_pc)
    );

    sram_1cycle #(
        .ADDR_WIDTH (SRAM_ADDR_WIDTH),
        .DATA_WIDTH (32),
        .INIT_FILE  (SRAM_INIT_FILE)
    ) u_sram (
        .clk   (clk),
        .rst_n (rst_n),
        .cs    (mem_cs),
        .we    (mem_we),
        .be    (mem_be),
        .addr  (mem_addr[SRAM_ADDR_WIDTH-1:0]),
        .wdata (mem_wdata),
        .rdata (mem_rdata)
    );

endmodule

`default_nettype wire
