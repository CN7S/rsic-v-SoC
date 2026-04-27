`timescale 1ns/1ps
`default_nettype none

module tensorpu_tb;

    reg clk;
    reg rst_n;
    reg cs;
    reg we;
    reg [3:0] be;
    reg [7:0] addr;
    reg [31:0] wdata;
    wire [31:0] rdata;
    wire busy;
    wire done;

    reg [31:0] status;
    reg [31:0] c00;
    reg [31:0] c01;
    reg [31:0] c10;
    reg [31:0] c11;
    reg done_seen;
    integer cycle;

    localparam [7:0] REG_CONTROL = 8'h00;
    localparam [7:0] REG_STATUS  = 8'h04;
    localparam [7:0] A_BASE      = 8'h10;
    localparam [7:0] B_BASE      = 8'h40;
    localparam [7:0] C_BASE      = 8'h80;

    tensorpu #(
        .DIM (2)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .cs    (cs),
        .we    (we),
        .be    (be),
        .addr  (addr),
        .wdata (wdata),
        .rdata (rdata),
        .busy  (busy),
        .done  (done)
    );

    task mmio_write;
        input [7:0] wr_addr;
        input [31:0] wr_data;
        begin
            @(posedge clk);
            cs <= 1'b1;
            we <= 1'b1;
            be <= 4'b1111;
            addr <= wr_addr;
            wdata <= wr_data;

            @(posedge clk);
            cs <= 1'b0;
            we <= 1'b0;
            be <= 4'b0000;
            addr <= 8'd0;
            wdata <= 32'd0;
        end
    endtask

    task mmio_read;
        input [7:0] rd_addr;
        output [31:0] rd_data;
        begin
            @(posedge clk);
            cs <= 1'b1;
            we <= 1'b0;
            be <= 4'b0000;
            addr <= rd_addr;

            @(posedge clk);
            rd_data = rdata;
            cs <= 1'b0;
            addr <= 8'd0;
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        cs = 1'b0;
        we = 1'b0;
        be = 4'b0000;
        addr = 8'd0;
        wdata = 32'd0;
        status = 32'd0;
        c00 = 32'd0;
        c01 = 32'd0;
        c10 = 32'd0;
        c11 = 32'd0;
        done_seen = 1'b0;
        cycle = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // A = [ [1,2], [3,4] ]
        mmio_write(A_BASE + 8'h00, 32'd1);
        mmio_write(A_BASE + 8'h04, 32'd2);
        mmio_write(A_BASE + 8'h08, 32'd3);
        mmio_write(A_BASE + 8'h0c, 32'd4);

        // B = [ [5,6], [7,8] ]
        mmio_write(B_BASE + 8'h00, 32'd5);
        mmio_write(B_BASE + 8'h04, 32'd6);
        mmio_write(B_BASE + 8'h08, 32'd7);
        mmio_write(B_BASE + 8'h0c, 32'd8);

        mmio_write(REG_CONTROL, 32'h0000_0001);

        while (cycle < 200 && !done_seen) begin
            mmio_read(REG_STATUS, status);
            cycle = cycle + 1;
            if (status[1]) begin
                done_seen = 1'b1;
            end
        end

        if (!done_seen) begin
            $display("FAIL: TPU done timeout, status=0x%08x", status);
            $finish;
        end

        mmio_read(C_BASE + 8'h00, c00);
        mmio_read(C_BASE + 8'h04, c01);
        mmio_read(C_BASE + 8'h08, c10);
        mmio_read(C_BASE + 8'h0c, c11);

        if (c00 !== 32'd19 || c01 !== 32'd22 || c10 !== 32'd43 || c11 !== 32'd50) begin
            $display("FAIL: C mismatch c00=%0d c01=%0d c10=%0d c11=%0d", c00, c01, c10, c11);
            $finish;
        end

        $display("PASS: TPU systolic matmul done in %0d polls", cycle);
        $finish;
    end

endmodule

`default_nettype wire
