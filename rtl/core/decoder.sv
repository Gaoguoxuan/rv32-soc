module decoder (
    input  logic [31:0] instr,

    output logic        reg_we,

    output logic [3:0]  alu_op,

    output logic [1:0]  op_a_sel,
    output logic        op_b_imm,

    output logic [2:0]  imm_sel,

    output logic        mem_load,
    output logic        mem_store,

    output logic [1:0]  wb_sel,

    output logic        branch,
    output logic [1:0]  jump,

    output logic        illegal
);

    // ========================================
    // Opcode
    // ========================================

    localparam logic [6:0] OPCODE_OP     = 7'b0110011;

    localparam logic [6:0] OPCODE_OP_IMM = 7'b0010011;


    // ========================================
    // ALU Operations
    // ========================================

    localparam logic [3:0] ALU_ADD  = 4'b0000;
    localparam logic [3:0] ALU_SUB  = 4'b0001;
    localparam logic [3:0] ALU_AND  = 4'b0010;
    localparam logic [3:0] ALU_OR   = 4'b0011;
    localparam logic [3:0] ALU_XOR  = 4'b0100;
    localparam logic [3:0] ALU_SLL  = 4'b0101;
    localparam logic [3:0] ALU_SRL  = 4'b0110;
    localparam logic [3:0] ALU_SRA  = 4'b0111;
    localparam logic [3:0] ALU_SLT  = 4'b1000;
    localparam logic [3:0] ALU_SLTU = 4'b1001;


    // ========================================
    // Operand A selection
    // ========================================

    localparam logic [1:0] OP_A_RS1  = 2'b00;
    localparam logic [1:0] OP_A_PC   = 2'b01;
    localparam logic [1:0] OP_A_ZERO = 2'b10;


    // ========================================
    // Immediate selection
    // ========================================

    localparam logic [2:0] IMM_I = 3'b000;
    localparam logic [2:0] IMM_S = 3'b001;
    localparam logic [2:0] IMM_B = 3'b010;
    localparam logic [2:0] IMM_U = 3'b011;
    localparam logic [2:0] IMM_J = 3'b100;


    // ========================================
    // Writeback selection
    // ========================================

    localparam logic [1:0] WB_ALU = 2'b00;
    localparam logic [1:0] WB_MEM = 2'b01;
    localparam logic [1:0] WB_PC4 = 2'b10;


    always_comb begin

        // ====================================
        // Safe Defaults
        // ====================================

        reg_we    = 1'b0;

        alu_op    = ALU_ADD;

        op_a_sel  = OP_A_RS1;
        op_b_imm  = 1'b0;

        imm_sel   = IMM_I;

        mem_load  = 1'b0;
        mem_store = 1'b0;

        wb_sel    = WB_ALU;

        branch    = 1'b0;
        jump      = 2'b00;

        illegal   = 1'b1;


        case (instr[6:0])


            // ==================================
            // R-type
            // ==================================

            OPCODE_OP: begin

                op_a_sel = OP_A_RS1;
                op_b_imm = 1'b0;

                reg_we   = 1'b1;
                wb_sel   = WB_ALU;


                case (instr[14:12])


                    // ADD / SUB
                    3'b000: begin

                        if (instr[31:25] == 7'b0000000) begin
                            alu_op  = ALU_ADD;
                            illegal = 1'b0;
                        end

                        else if (instr[31:25] == 7'b0100000) begin
                            alu_op  = ALU_SUB;
                            illegal = 1'b0;
                        end

                    end


                    // SLL
                    3'b001: begin

                        if (instr[31:25] == 7'b0000000) begin
                            alu_op  = ALU_SLL;
                            illegal = 1'b0;
                        end

                    end


                    // SLT
                    3'b010: begin

                        if (instr[31:25] == 7'b0000000) begin
                            alu_op  = ALU_SLT;
                            illegal = 1'b0;
                        end

                    end


                    // SLTU
                    3'b011: begin

                        if (instr[31:25] == 7'b0000000) begin
                            alu_op  = ALU_SLTU;
                            illegal = 1'b0;
                        end

                    end


                    // XOR
                    3'b100: begin

                        if (instr[31:25] == 7'b0000000) begin
                            alu_op  = ALU_XOR;
                            illegal = 1'b0;
                        end

                    end


                    // SRL / SRA
                    3'b101: begin

                        if (instr[31:25] == 7'b0000000) begin
                            alu_op  = ALU_SRL;
                            illegal = 1'b0;
                        end

                        else if (instr[31:25] == 7'b0100000) begin
                            alu_op  = ALU_SRA;
                            illegal = 1'b0;
                        end

                    end


                    // OR
                    3'b110: begin

                        if (instr[31:25] == 7'b0000000) begin
                            alu_op  = ALU_OR;
                            illegal = 1'b0;
                        end

                    end


                    // AND
                    3'b111: begin

                        if (instr[31:25] == 7'b0000000) begin
                            alu_op  = ALU_AND;
                            illegal = 1'b0;
                        end

                    end


                    default: begin
                    end

                endcase

            end


            // ==================================
            // I-type ALU
            // ==================================

            OPCODE_OP_IMM: begin

                reg_we    = 1'b1;

                op_a_sel  = OP_A_RS1;
                op_b_imm  = 1'b1;

                imm_sel   = IMM_I;

                wb_sel    = WB_ALU;


                case (instr[14:12])


                    // ADDI
                    3'b000: begin

                        alu_op  = ALU_ADD;
                        illegal = 1'b0;

                    end


                    // SLLI
                    3'b001: begin

                        if (instr[31:25] == 7'b0000000) begin
                            alu_op  = ALU_SLL;
                            illegal = 1'b0;
                        end

                    end


                    // SLTI
                    3'b010: begin

                        alu_op  = ALU_SLT;
                        illegal = 1'b0;

                    end


                    // SLTIU
                    3'b011: begin

                        alu_op  = ALU_SLTU;
                        illegal = 1'b0;

                    end


                    // XORI
                    3'b100: begin

                        alu_op  = ALU_XOR;
                        illegal = 1'b0;

                    end


                    // SRLI / SRAI
                    3'b101: begin

                        if (instr[31:25] == 7'b0000000) begin
                            alu_op  = ALU_SRL;
                            illegal = 1'b0;
                        end

                        else if (instr[31:25] == 7'b0100000) begin
                            alu_op  = ALU_SRA;
                            illegal = 1'b0;
                        end

                    end


                    // ORI
                    3'b110: begin

                        alu_op  = ALU_OR;
                        illegal = 1'b0;

                    end


                    // ANDI
                    3'b111: begin

                        alu_op  = ALU_AND;
                        illegal = 1'b0;

                    end


                    default: begin
                    end

                endcase

            end


            default: begin
            end

        endcase


        // 如果最终仍然 illegal，
        // 禁止产生任何副作用。

        if (illegal) begin

            reg_we    = 1'b0;
            mem_load  = 1'b0;
            mem_store = 1'b0;

        end

    end

endmodule