`timescale 1ns/1ps
`default_nettype none

module tensorpu #(
    parameter DIM        = 2,
    parameter DATA_WIDTH = 32
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

    localparam integer WORDS = DIM * DIM;
    localparam integer ACC_WIDTH = 64;
    localparam [7:0] DIM_U8 = DIM;

    localparam [7:0] REG_CONTROL = 8'h00;
    localparam [7:0] REG_STATUS  = 8'h04;
    localparam [7:0] REG_CONFIG  = 8'h08;
    localparam [7:0] A_BASE      = 8'h10;
    localparam [7:0] B_BASE      = 8'h40;
    localparam [7:0] C_BASE      = 8'h80;

    localparam [2:0] ST_IDLE   = 3'd0;
    localparam [2:0] ST_LOAD_A = 3'd1;
    localparam [2:0] ST_LOAD_B = 3'd2;
    localparam [2:0] ST_RUN    = 3'd3;
    localparam [2:0] ST_STORE  = 3'd4;

    function integer clog2;
        input integer value;
        integer tmp;
        begin
            tmp = value - 1;
            clog2 = 0;
            while (tmp > 0) begin
                tmp = tmp >> 1;
                clog2 = clog2 + 1;
            end
            if (clog2 == 0) begin
                clog2 = 1;
            end
        end
    endfunction

    localparam integer SRAM_ADDR_WIDTH = clog2(WORDS);

    reg [2:0] state;
    reg       run_issued;
    reg [SRAM_ADDR_WIDTH-1:0] load_idx;
    reg [SRAM_ADDR_WIDTH-1:0] store_idx;

    reg signed [DATA_WIDTH-1:0] a_buf [0:WORDS-1];
    reg signed [DATA_WIDTH-1:0] b_buf [0:WORDS-1];
    reg signed [DATA_WIDTH-1:0] c_buf [0:WORDS-1];

    reg [WORDS*DATA_WIDTH-1:0] a_flat;
    reg [WORDS*DATA_WIDTH-1:0] b_flat;
    wire [WORDS*DATA_WIDTH-1:0] c_flat;

    reg                       a_we;
    reg [3:0]                 a_be;
    reg [SRAM_ADDR_WIDTH-1:0] a_addr;
    reg [31:0]                a_wdata;
    wire [31:0]               a_rdata;

    reg                       b_we;
    reg [3:0]                 b_be;
    reg [SRAM_ADDR_WIDTH-1:0] b_addr;
    reg [31:0]                b_wdata;
    wire [31:0]               b_rdata;

    reg                       c_we;
    reg [3:0]                 c_be;
    reg [SRAM_ADDR_WIDTH-1:0] c_addr;
    reg [31:0]                c_wdata;
    wire [31:0]               c_rdata;

    reg array_start;
    wire array_done;

    wire cpu_write = cs && we;
    wire cpu_read  = cs && !we;
    wire start_cmd = cpu_write && (addr == REG_CONTROL) && be[0] && wdata[0];
    wire clear_done_cmd = cpu_write && (addr == REG_CONTROL) && be[0] && wdata[1];

    wire in_a_region = (addr >= A_BASE) && (addr < (A_BASE + WORDS*4));
    wire in_b_region = (addr >= B_BASE) && (addr < (B_BASE + WORDS*4));
    wire in_c_region = (addr >= C_BASE) && (addr < (C_BASE + WORDS*4));

    wire [SRAM_ADDR_WIDTH-1:0] cpu_a_idx = (addr - A_BASE) >> 2;
    wire [SRAM_ADDR_WIDTH-1:0] cpu_b_idx = (addr - B_BASE) >> 2;
    wire [SRAM_ADDR_WIDTH-1:0] cpu_c_idx = (addr - C_BASE) >> 2;

    integer i;

    tpu_sram #(
        .ADDR_WIDTH (SRAM_ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_a_sram (
        .clk   (clk),
        .rst_n (rst_n),
        .we    (a_we),
        .be    (a_be),
        .addr  (a_addr),
        .wdata (a_wdata),
        .rdata (a_rdata)
    );

    tpu_sram #(
        .ADDR_WIDTH (SRAM_ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_b_sram (
        .clk   (clk),
        .rst_n (rst_n),
        .we    (b_we),
        .be    (b_be),
        .addr  (b_addr),
        .wdata (b_wdata),
        .rdata (b_rdata)
    );

    tpu_sram #(
        .ADDR_WIDTH (SRAM_ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_c_sram (
        .clk   (clk),
        .rst_n (rst_n),
        .we    (c_we),
        .be    (c_be),
        .addr  (c_addr),
        .wdata (c_wdata),
        .rdata (c_rdata)
    );

    tpu_systolic_array #(
        .DIM        (DIM),
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH)
    ) u_array (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (array_start),
        .a_matrix (a_flat),
        .b_matrix (b_flat),
        .busy     (),
        .done     (array_done),
        .c_matrix (c_flat)
    );

    always @(*) begin
        for (i = 0; i < WORDS; i = i + 1) begin
            a_flat[i*DATA_WIDTH +: DATA_WIDTH] = a_buf[i];
            b_flat[i*DATA_WIDTH +: DATA_WIDTH] = b_buf[i];
        end
    end

    always @(*) begin
        a_we = 1'b0;
        a_be = 4'b0000;
        a_addr = {SRAM_ADDR_WIDTH{1'b0}};
        a_wdata = 32'd0;

        b_we = 1'b0;
        b_be = 4'b0000;
        b_addr = {SRAM_ADDR_WIDTH{1'b0}};
        b_wdata = 32'd0;

        c_we = 1'b0;
        c_be = 4'b0000;
        c_addr = {SRAM_ADDR_WIDTH{1'b0}};
        c_wdata = 32'd0;

        if (state == ST_LOAD_A) begin
            a_addr = load_idx;
        end

        if (state == ST_LOAD_B) begin
            b_addr = load_idx;
        end

        if (state == ST_STORE) begin
            c_we = 1'b1;
            c_be = 4'b1111;
            c_addr = store_idx;
            c_wdata = c_buf[store_idx];
        end

        if (state == ST_IDLE) begin
            if (cpu_write && in_a_region) begin
                a_we = 1'b1;
                a_be = be;
                a_addr = cpu_a_idx;
                a_wdata = wdata;
            end else if ((cpu_read || cpu_write) && in_a_region) begin
                a_addr = cpu_a_idx;
            end

            if (cpu_write && in_b_region) begin
                b_we = 1'b1;
                b_be = be;
                b_addr = cpu_b_idx;
                b_wdata = wdata;
            end else if ((cpu_read || cpu_write) && in_b_region) begin
                b_addr = cpu_b_idx;
            end

            if (cpu_write && in_c_region) begin
                c_we = 1'b1;
                c_be = be;
                c_addr = cpu_c_idx;
                c_wdata = wdata;
            end else if ((cpu_read || cpu_write) && in_c_region) begin
                c_addr = cpu_c_idx;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata <= 32'd0;
            state <= ST_IDLE;
            run_issued <= 1'b0;
            load_idx <= {SRAM_ADDR_WIDTH{1'b0}};
            store_idx <= {SRAM_ADDR_WIDTH{1'b0}};
            array_start <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
            for (i = 0; i < WORDS; i = i + 1) begin
                a_buf[i] <= {DATA_WIDTH{1'b0}};
                b_buf[i] <= {DATA_WIDTH{1'b0}};
                c_buf[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            array_start <= 1'b0;

            if (clear_done_cmd) begin
                done <= 1'b0;
            end

            case (state)
                ST_IDLE: begin
                    run_issued <= 1'b0;
                    busy <= 1'b0;
                    if (start_cmd) begin
                        done <= 1'b0;
                        busy <= 1'b1;
                        load_idx <= {SRAM_ADDR_WIDTH{1'b0}};
                        state <= ST_LOAD_A;
                    end
                end

                ST_LOAD_A: begin
                    busy <= 1'b1;
                    a_buf[load_idx] <= a_rdata;
                    if (load_idx == WORDS - 1) begin
                        load_idx <= {SRAM_ADDR_WIDTH{1'b0}};
                        state <= ST_LOAD_B;
                    end else begin
                        load_idx <= load_idx + 1'b1;
                    end
                end

                ST_LOAD_B: begin
                    busy <= 1'b1;
                    b_buf[load_idx] <= b_rdata;
                    if (load_idx == WORDS - 1) begin
                        state <= ST_RUN;
                        run_issued <= 1'b0;
                    end else begin
                        load_idx <= load_idx + 1'b1;
                    end
                end

                ST_RUN: begin
                    busy <= 1'b1;
                    if (!run_issued) begin
                        array_start <= 1'b1;
                        run_issued <= 1'b1;
                    end
                    if (array_done) begin
                        for (i = 0; i < WORDS; i = i + 1) begin
                            c_buf[i] <= c_flat[i*DATA_WIDTH +: DATA_WIDTH];
                        end
                        store_idx <= {SRAM_ADDR_WIDTH{1'b0}};
                        state <= ST_STORE;
                        run_issued <= 1'b0;
                    end
                end

                ST_STORE: begin
                    busy <= 1'b1;
                    if (store_idx == WORDS - 1) begin
                        state <= ST_IDLE;
                        busy <= 1'b0;
                        done <= 1'b1;
                    end else begin
                        store_idx <= store_idx + 1'b1;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                    busy <= 1'b0;
                end
            endcase

            if (cpu_read) begin
                case (addr)
                    REG_CONTROL: rdata <= {30'd0, done, busy};
                    REG_STATUS:  rdata <= {30'd0, done, busy};
                    REG_CONFIG:  rdata <= {16'd0, DIM_U8, DIM_U8};
                    default: begin
                        if (state == ST_IDLE && in_a_region) begin
                            rdata <= a_rdata;
                        end else if (state == ST_IDLE && in_b_region) begin
                            rdata <= b_rdata;
                        end else if (state == ST_IDLE && in_c_region) begin
                            rdata <= c_rdata;
                        end else begin
                            rdata <= 32'd0;
                        end
                    end
                endcase
            end
        end
    end

endmodule

`default_nettype wire
