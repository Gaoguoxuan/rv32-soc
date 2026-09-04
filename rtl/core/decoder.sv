module decoder (
    input  logic [31:0] instr,

    output logic        reg_we,
    output logic        alu_src_imm,
    output logic [3:0]  alu_op,
    output logic        illegal
);

    localparam logic [6:0] OPCODE_OP_IMM = 7'b0010011;

    localparam logic [3:0] ALU_ADD = 4'b0000;

    always_comb begin

        // 默认值
        reg_we      = 1'b0;
        alu_src_imm = 1'b0;
        alu_op      = ALU_ADD;
        illegal     = 1'b1;

        case (instr[6:0])

            OPCODE_OP_IMM: begin

                // funct3 == 000 → ADDI
                if (instr[14:12] == 3'b000) begin
                    reg_we      = 1'b1;
                    alu_src_imm = 1'b1;
                    alu_op      = ALU_ADD;
                    illegal     = 1'b0;
                end

            end

            default: begin
            end

        endcase
    end

endmodule
