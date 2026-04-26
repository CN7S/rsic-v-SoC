`timescale 1ns/1ps
`default_nettype none

module little_soc_tb;

    reg clk;
    reg rst_n;

    wire        halted;
    wire [31:0] debug_pc;

    integer cycle;

    little_soc #(
        .SRAM_ADDR_WIDTH (16),
        .SRAM_INIT_FILE  ("sw/smoke.hex")
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .halted   (halted),
        .debug_pc (debug_pc)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        cycle = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        while (!halted && cycle < 200) begin
            @(posedge clk);
            cycle = cycle + 1;
        end

        if (!halted) begin
            $display("FAIL: timeout at pc=0x%08x", debug_pc);
            $finish;
        end

        if (dut.u_sram.mem[24] !== 32'd12) begin
            $display("FAIL: expected mem[0x60]=12, got 0x%08x", dut.u_sram.mem[24]);
            $finish;
        end

        if (dut.u_cpu.regs[4] !== 32'd12) begin
            $display("FAIL: expected x4=12, got 0x%08x", dut.u_cpu.regs[4]);
            $finish;
        end

        if (dut.u_cpu.regs[5] !== 32'd0) begin
            $display("FAIL: expected x5=0 after taken branch, got 0x%08x", dut.u_cpu.regs[5]);
            $finish;
        end

        $display("PASS: halted at pc=0x%08x after %0d cycles", debug_pc, cycle);
        $finish;
    end

endmodule

`default_nettype wire
