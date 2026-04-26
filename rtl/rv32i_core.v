`timescale 1ns/1ps
`default_nettype none

module rv32i_core (
    input  wire        clk,
    input  wire        rst_n,

    output reg         mem_cs,
    output reg         mem_we,
    output reg  [3:0]  mem_be,
    output reg  [31:0] mem_addr,
    output reg  [31:0] mem_wdata,
    input  wire [31:0] mem_rdata,

    output reg         halted,
    output wire [31:0] debug_pc
);

    localparam [2:0] ST_FETCH_REQ = 3'd0;
    localparam [2:0] ST_FETCH_WAIT = 3'd1;
    localparam [2:0] ST_FETCH_RSP = 3'd2;
    localparam [2:0] ST_EXEC = 3'd3;
    localparam [2:0] ST_LOAD_WAIT = 3'd4;
    localparam [2:0] ST_LOAD_RSP = 3'd5;
    localparam [2:0] ST_STORE_WAIT = 3'd6;
    localparam [2:0] ST_HALT = 3'd7;

    localparam [6:0] OPCODE_LOAD = 7'b0000011;
    localparam [6:0] OPCODE_MISC_MEM = 7'b0001111;
    localparam [6:0] OPCODE_OP_IMM = 7'b0010011;
    localparam [6:0] OPCODE_AUIPC = 7'b0010111;
    localparam [6:0] OPCODE_STORE = 7'b0100011;
    localparam [6:0] OPCODE_OP = 7'b0110011;
    localparam [6:0] OPCODE_LUI = 7'b0110111;
    localparam [6:0] OPCODE_BRANCH = 7'b1100011;
    localparam [6:0] OPCODE_JALR = 7'b1100111;
    localparam [6:0] OPCODE_JAL = 7'b1101111;
    localparam [6:0] OPCODE_SYSTEM = 7'b1110011;

    reg [2:0]  state;
    reg [31:0] pc;
    reg [31:0] instr;
    reg [31:0] regs [0:31];

    reg [4:0]  load_rd;
    reg [2:0]  load_funct3;
    reg [1:0]  load_byte_offset;
    reg [31:0] load_next_pc;

    integer i;

    wire [6:0] opcode = instr[6:0];
    wire [4:0] rd = instr[11:7];
    wire [2:0] funct3 = instr[14:12];
    wire [4:0] rs1 = instr[19:15];
    wire [4:0] rs2 = instr[24:20];
    wire [6:0] funct7 = instr[31:25];

    wire [31:0] rs1_val = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
    wire [31:0] rs2_val = (rs2 == 5'd0) ? 32'd0 : regs[rs2];

    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7],
                         instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12],
                         instr[20], instr[30:21], 1'b0};

    wire [31:0] pc_plus4 = pc + 32'd4;
    wire [31:0] load_addr = rs1_val + imm_i;
    wire [31:0] store_addr = rs1_val + imm_s;

    assign debug_pc = pc;

    function [31:0] load_extend;
        input [31:0] word;
        input [2:0]  size;
        input [1:0]  byte_offset;
        reg   [7:0]  byte_value;
        reg   [15:0] half_value;
        begin
            case (byte_offset)
                2'd0: byte_value = word[7:0];
                2'd1: byte_value = word[15:8];
                2'd2: byte_value = word[23:16];
                default: byte_value = word[31:24];
            endcase

            half_value = byte_offset[1] ? word[31:16] : word[15:0];

            case (size)
                3'b000: load_extend = {{24{byte_value[7]}}, byte_value};
                3'b001: load_extend = {{16{half_value[15]}}, half_value};
                3'b010: load_extend = word;
                3'b100: load_extend = {24'd0, byte_value};
                3'b101: load_extend = {16'd0, half_value};
                default: load_extend = 32'd0;
            endcase
        end
    endfunction

    function [3:0] store_be;
        input [2:0] size;
        input [1:0] byte_offset;
        begin
            case (size)
                3'b000: store_be = 4'b0001 << byte_offset;
                3'b001: store_be = byte_offset[1] ? 4'b1100 : 4'b0011;
                3'b010: store_be = 4'b1111;
                default: store_be = 4'b0000;
            endcase
        end
    endfunction

    function [31:0] store_wdata;
        input [31:0] value;
        input [2:0]  size;
        input [1:0]  byte_offset;
        begin
            case (size)
                3'b000: store_wdata = {4{value[7:0]}} << (byte_offset * 8);
                3'b001: store_wdata = byte_offset[1] ? {value[15:0], 16'd0}
                                                      : {16'd0, value[15:0]};
                3'b010: store_wdata = value;
                default: store_wdata = 32'd0;
            endcase
        end
    endfunction

    function is_load_aligned;
        input [2:0] size;
        input [1:0] byte_offset;
        begin
            case (size)
                3'b000, 3'b100: is_load_aligned = 1'b1;
                3'b001, 3'b101: is_load_aligned = (byte_offset[0] == 1'b0);
                3'b010: is_load_aligned = (byte_offset == 2'b00);
                default: is_load_aligned = 1'b0;
            endcase
        end
    endfunction

    function is_store_aligned;
        input [2:0] size;
        input [1:0] byte_offset;
        begin
            case (size)
                3'b000: is_store_aligned = 1'b1;
                3'b001: is_store_aligned = (byte_offset[0] == 1'b0);
                3'b010: is_store_aligned = (byte_offset == 2'b00);
                default: is_store_aligned = 1'b0;
            endcase
        end
    endfunction

    task write_rd;
        input [4:0]  dest;
        input [31:0] value;
        begin
            if (dest != 5'd0) begin
                regs[dest] <= value;
            end
        end
    endtask

    task halt_core;
        begin
            halted <= 1'b1;
            state <= ST_HALT;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_FETCH_REQ;
            pc <= 32'd0;
            instr <= 32'd0;
            mem_cs <= 1'b0;
            mem_we <= 1'b0;
            mem_be <= 4'b0000;
            mem_addr <= 32'd0;
            mem_wdata <= 32'd0;
            halted <= 1'b0;
            load_rd <= 5'd0;
            load_funct3 <= 3'd0;
            load_byte_offset <= 2'd0;
            load_next_pc <= 32'd0;

            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= 32'd0;
            end
        end else begin
            mem_cs <= 1'b0;
            mem_we <= 1'b0;
            mem_be <= 4'b0000;
            regs[0] <= 32'd0;

            case (state)
                ST_FETCH_REQ: begin
                    if (pc[1:0] != 2'b00) begin
                        halt_core();
                    end else begin
                        mem_cs <= 1'b1;
                        mem_we <= 1'b0;
                        mem_be <= 4'b1111;
                        mem_addr <= pc;
                        state <= ST_FETCH_WAIT;
                    end
                end

                ST_FETCH_WAIT: begin
                    state <= ST_FETCH_RSP;
                end

                ST_FETCH_RSP: begin
                    instr <= mem_rdata;
                    state <= ST_EXEC;
                end

                ST_EXEC: begin
                    case (opcode)
                        OPCODE_LUI: begin
                            write_rd(rd, imm_u);
                            pc <= pc_plus4;
                            state <= ST_FETCH_REQ;
                        end

                        OPCODE_AUIPC: begin
                            write_rd(rd, pc + imm_u);
                            pc <= pc_plus4;
                            state <= ST_FETCH_REQ;
                        end

                        OPCODE_JAL: begin
                            write_rd(rd, pc_plus4);
                            pc <= pc + imm_j;
                            state <= ST_FETCH_REQ;
                        end

                        OPCODE_JALR: begin
                            if (funct3 == 3'b000) begin
                                write_rd(rd, pc_plus4);
                                pc <= ((rs1_val + imm_i) & 32'hffff_fffe);
                                state <= ST_FETCH_REQ;
                            end else begin
                                halt_core();
                            end
                        end

                        OPCODE_BRANCH: begin
                            case (funct3)
                                3'b000: begin
                                    pc <= (rs1_val == rs2_val) ? (pc + imm_b) : pc_plus4;
                                    state <= ST_FETCH_REQ;
                                end
                                3'b001: begin
                                    pc <= (rs1_val != rs2_val) ? (pc + imm_b) : pc_plus4;
                                    state <= ST_FETCH_REQ;
                                end
                                3'b100: begin
                                    pc <= ($signed(rs1_val) < $signed(rs2_val)) ?
                                          (pc + imm_b) : pc_plus4;
                                    state <= ST_FETCH_REQ;
                                end
                                3'b101: begin
                                    pc <= ($signed(rs1_val) >= $signed(rs2_val)) ?
                                          (pc + imm_b) : pc_plus4;
                                    state <= ST_FETCH_REQ;
                                end
                                3'b110: begin
                                    pc <= (rs1_val < rs2_val) ? (pc + imm_b) : pc_plus4;
                                    state <= ST_FETCH_REQ;
                                end
                                3'b111: begin
                                    pc <= (rs1_val >= rs2_val) ? (pc + imm_b) : pc_plus4;
                                    state <= ST_FETCH_REQ;
                                end
                                default: halt_core();
                            endcase
                        end

                        OPCODE_LOAD: begin
                            if (!is_load_aligned(funct3, load_addr[1:0])) begin
                                halt_core();
                            end else begin
                                load_rd <= rd;
                                load_funct3 <= funct3;
                                load_byte_offset <= load_addr[1:0];
                                load_next_pc <= pc_plus4;
                                mem_cs <= 1'b1;
                                mem_we <= 1'b0;
                                mem_be <= 4'b1111;
                                mem_addr <= {load_addr[31:2], 2'b00};
                                state <= ST_LOAD_WAIT;
                            end
                        end

                        OPCODE_STORE: begin
                            if (!is_store_aligned(funct3, store_addr[1:0])) begin
                                halt_core();
                            end else begin
                                mem_cs <= 1'b1;
                                mem_we <= 1'b1;
                                mem_be <= store_be(funct3, store_addr[1:0]);
                                mem_addr <= {store_addr[31:2], 2'b00};
                                mem_wdata <= store_wdata(rs2_val, funct3, store_addr[1:0]);
                                pc <= pc_plus4;
                                state <= ST_STORE_WAIT;
                            end
                        end

                        OPCODE_OP_IMM: begin
                            case (funct3)
                                3'b000: begin
                                    write_rd(rd, rs1_val + imm_i);
                                    pc <= pc_plus4;
                                    state <= ST_FETCH_REQ;
                                end
                                3'b010: begin
                                    write_rd(rd, ($signed(rs1_val) < $signed(imm_i)) ? 32'd1 : 32'd0);
                                    pc <= pc_plus4;
                                    state <= ST_FETCH_REQ;
                                end
                                3'b011: begin
                                    write_rd(rd, (rs1_val < imm_i) ? 32'd1 : 32'd0);
                                    pc <= pc_plus4;
                                    state <= ST_FETCH_REQ;
                                end
                                3'b100: begin
                                    write_rd(rd, rs1_val ^ imm_i);
                                    pc <= pc_plus4;
                                    state <= ST_FETCH_REQ;
                                end
                                3'b110: begin
                                    write_rd(rd, rs1_val | imm_i);
                                    pc <= pc_plus4;
                                    state <= ST_FETCH_REQ;
                                end
                                3'b111: begin
                                    write_rd(rd, rs1_val & imm_i);
                                    pc <= pc_plus4;
                                    state <= ST_FETCH_REQ;
                                end
                                3'b001: begin
                                    if (funct7 == 7'b0000000) begin
                                        write_rd(rd, rs1_val << instr[24:20]);
                                        pc <= pc_plus4;
                                        state <= ST_FETCH_REQ;
                                    end else begin
                                        halt_core();
                                    end
                                end
                                3'b101: begin
                                    if (funct7 == 7'b0000000) begin
                                        write_rd(rd, rs1_val >> instr[24:20]);
                                        pc <= pc_plus4;
                                        state <= ST_FETCH_REQ;
                                    end else if (funct7 == 7'b0100000) begin
                                        write_rd(rd, $signed(rs1_val) >>> instr[24:20]);
                                        pc <= pc_plus4;
                                        state <= ST_FETCH_REQ;
                                    end else begin
                                        halt_core();
                                    end
                                end
                                default: begin
                                    halt_core();
                                end
                            endcase
                        end

                        OPCODE_OP: begin
                            if ((funct7 != 7'b0000000) && (funct7 != 7'b0100000)) begin
                                halt_core();
                            end else begin
                                case ({instr[30], funct3})
                                    4'b0_000: write_rd(rd, rs1_val + rs2_val);
                                    4'b1_000: write_rd(rd, rs1_val - rs2_val);
                                    4'b0_001: write_rd(rd, rs1_val << rs2_val[4:0]);
                                    4'b0_010: write_rd(rd, ($signed(rs1_val) < $signed(rs2_val)) ?
                                                       32'd1 : 32'd0);
                                    4'b0_011: write_rd(rd, (rs1_val < rs2_val) ? 32'd1 : 32'd0);
                                    4'b0_100: write_rd(rd, rs1_val ^ rs2_val);
                                    4'b0_101: write_rd(rd, rs1_val >> rs2_val[4:0]);
                                    4'b1_101: write_rd(rd, $signed(rs1_val) >>> rs2_val[4:0]);
                                    4'b0_110: write_rd(rd, rs1_val | rs2_val);
                                    4'b0_111: write_rd(rd, rs1_val & rs2_val);
                                    default: begin
                                        halt_core();
                                    end
                                endcase

                                if (({instr[30], funct3} == 4'b0_000) ||
                                    ({instr[30], funct3} == 4'b1_000) ||
                                    ({instr[30], funct3} == 4'b0_001) ||
                                    ({instr[30], funct3} == 4'b0_010) ||
                                    ({instr[30], funct3} == 4'b0_011) ||
                                    ({instr[30], funct3} == 4'b0_100) ||
                                    ({instr[30], funct3} == 4'b0_101) ||
                                    ({instr[30], funct3} == 4'b1_101) ||
                                    ({instr[30], funct3} == 4'b0_110) ||
                                    ({instr[30], funct3} == 4'b0_111)) begin
                                    pc <= pc_plus4;
                                    state <= ST_FETCH_REQ;
                                end
                            end
                        end

                        OPCODE_MISC_MEM: begin
                            pc <= pc_plus4;
                            state <= ST_FETCH_REQ;
                        end

                        OPCODE_SYSTEM: begin
                            if ((instr == 32'h0000_0073) || (instr == 32'h0010_0073)) begin
                                halt_core();
                            end else begin
                                halt_core();
                            end
                        end

                        default: begin
                            halt_core();
                        end
                    endcase
                end

                ST_LOAD_WAIT: begin
                    state <= ST_LOAD_RSP;
                end

                ST_LOAD_RSP: begin
                    write_rd(load_rd, load_extend(mem_rdata, load_funct3, load_byte_offset));
                    pc <= load_next_pc;
                    state <= ST_FETCH_REQ;
                end

                ST_STORE_WAIT: begin
                    state <= ST_FETCH_REQ;
                end

                ST_HALT: begin
                    halted <= 1'b1;
                    state <= ST_HALT;
                end

                default: begin
                    halt_core();
                end
            endcase
        end
    end

endmodule

`default_nettype wire
