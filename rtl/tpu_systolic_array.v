`timescale 1ns/1ps
`default_nettype none

module tpu_systolic_array #(
    parameter DIM        = 2,
    parameter DATA_WIDTH = 32,
    parameter ACC_WIDTH  = 64
) (
    input  wire                               clk,
    input  wire                               rst_n,
    input  wire                               start,
    input  wire [DIM*DIM*DATA_WIDTH-1:0]      a_matrix,
    input  wire [DIM*DIM*DATA_WIDTH-1:0]      b_matrix,
    output reg                                busy,
    output reg                                done,
    output wire [DIM*DIM*DATA_WIDTH-1:0]      c_matrix
);

    localparam integer RUN_CYCLES = (3 * DIM) - 2;

    integer i;
    integer j;

    reg [15:0] run_counter;
    reg        clear_phase;

    reg signed [DATA_WIDTH-1:0] west_data  [0:DIM-1];
    reg                         west_valid [0:DIM-1];
    reg signed [DATA_WIDTH-1:0] north_data  [0:DIM-1];
    reg                         north_valid [0:DIM-1];

    wire signed [DATA_WIDTH-1:0] east_data   [0:DIM-1][0:DIM-1];
    wire                         east_valid  [0:DIM-1][0:DIM-1];
    wire signed [DATA_WIDTH-1:0] south_data  [0:DIM-1][0:DIM-1];
    wire                         south_valid [0:DIM-1][0:DIM-1];
    wire signed [ACC_WIDTH-1:0]  acc_data    [0:DIM-1][0:DIM-1];

    function signed [DATA_WIDTH-1:0] mat_elem;
        input [DIM*DIM*DATA_WIDTH-1:0] matrix_flat;
        input integer row;
        input integer col;
        integer idx;
        begin
            idx = ((row * DIM) + col) * DATA_WIDTH;
            mat_elem = matrix_flat[idx +: DATA_WIDTH];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            done <= 1'b0;
            run_counter <= 16'd0;
            clear_phase <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                busy <= 1'b1;
                run_counter <= 16'd0;
                clear_phase <= 1'b1;
            end else if (busy) begin
                if (clear_phase) begin
                    clear_phase <= 1'b0;
                end else if (run_counter == RUN_CYCLES - 1) begin
                    busy <= 1'b0;
                    clear_phase <= 1'b0;
                    done <= 1'b1;
                end else begin
                    run_counter <= run_counter + 16'd1;
                end
            end
        end
    end

    always @(*) begin
        integer k;
        for (i = 0; i < DIM; i = i + 1) begin
            k = run_counter - i;
            if (busy && !clear_phase && (k >= 0) && (k < DIM)) begin
                west_data[i] = mat_elem(a_matrix, i, k);
                west_valid[i] = 1'b1;
            end else begin
                west_data[i] = {DATA_WIDTH{1'b0}};
                west_valid[i] = 1'b0;
            end
        end

        for (j = 0; j < DIM; j = j + 1) begin
            k = run_counter - j;
            if (busy && !clear_phase && (k >= 0) && (k < DIM)) begin
                north_data[j] = mat_elem(b_matrix, k, j);
                north_valid[j] = 1'b1;
            end else begin
                north_data[j] = {DATA_WIDTH{1'b0}};
                north_valid[j] = 1'b0;
            end
        end
    end

    genvar r;
    genvar c;
    generate
        for (r = 0; r < DIM; r = r + 1) begin : gen_row
            for (c = 0; c < DIM; c = c + 1) begin : gen_col
                wire signed [DATA_WIDTH-1:0] pe_in_a = (c == 0) ? west_data[r] : east_data[r][c-1];
                wire signed [DATA_WIDTH-1:0] pe_in_b = (r == 0) ? north_data[c] : south_data[r-1][c];
                wire pe_in_valid_a = (c == 0) ? west_valid[r] : east_valid[r][c-1];
                wire pe_in_valid_b = (r == 0) ? north_valid[c] : south_valid[r-1][c];

                tpu_pe #(
                    .DATA_WIDTH (DATA_WIDTH),
                    .ACC_WIDTH  (ACC_WIDTH)
                ) u_pe (
                    .clk         (clk),
                    .rst_n       (rst_n),
                    .clear_acc   (clear_phase),
                    .enable      (busy && !clear_phase),
                    .in_a        (pe_in_a),
                    .in_b        (pe_in_b),
                    .in_valid_a  (pe_in_valid_a),
                    .in_valid_b  (pe_in_valid_b),
                    .out_a       (east_data[r][c]),
                    .out_b       (south_data[r][c]),
                    .out_valid_a (east_valid[r][c]),
                    .out_valid_b (south_valid[r][c]),
                    .acc         (acc_data[r][c])
                );

                assign c_matrix[((r * DIM) + c) * DATA_WIDTH +: DATA_WIDTH] =
                    acc_data[r][c][DATA_WIDTH-1:0];
            end
        end
    endgenerate

endmodule

`default_nettype wire
