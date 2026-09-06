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

    output logic [2:0]  branch_type,
    output logic [1:0]  jump,

    output logic        illegal
);

    // ========================================
    // Opcode
    // ========================================

    localparam logic [6:0] OPCODE_OP     = 7'b0110011;

    localparam logic [6:0] OPCODE_OP_IMM = 7'b0010011;

    localparam logic [6:0] OPCODE_LOAD   = 7'b0000011;
    localparam logic [6:0] OPCODE_STORE  = 7'b0100011;
    localparam logic [6:0] OPCODE_BRANCH = 7'b1100011;

    localparam logic [6:0] OPCODE_LUI    = 7'b0110111;
    localparam logic [6:0] OPCODE_AUIPC  = 7'b0010111;

    localparam logic [6:0] OPCODE_JAL    = 7'b1101111;
    localparam logic [6:0] OPCODE_JALR   = 7'b1100111;


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

    // ========================================
    // Branch type
    // ========================================

    localparam logic [2:0] BR_NONE = 3'b000;
    localparam logic [2:0] BR_BEQ  = 3'b001;
    localparam logic [2:0] BR_BNE  = 3'b010;
    localparam logic [2:0] BR_BLT  = 3'b011;
    localparam logic [2:0] BR_BGE  = 3'b100;
    localparam logic [2:0] BR_BLTU = 3'b101;
    localparam logic [2:0] BR_BGEU = 3'b110;

    // ========================================
    // Jump type
    // ========================================

    localparam logic [1:0] JUMP_NONE = 2'b00;
    localparam logic [1:0] JUMP_JAL  = 2'b01;
    localparam logic [1:0] JUMP_JALR = 2'b10;

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

        branch_type = 3'b000;
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

            // ==================================
            // I-type LOAD
            // ================================== 

            OPCODE_LOAD: begin

                // LW
                if (instr[14:12] == 3'b010) begin

                    reg_we    = 1'b1;

                    op_a_sel  = OP_A_RS1;
                    op_b_imm  = 1'b1;

                    imm_sel   = IMM_I;

                    alu_op    = ALU_ADD;

                    mem_load  = 1'b1;

                    wb_sel    = WB_MEM;

                    illegal   = 1'b0;

                end

            end

            // ==================================
            // I-type JALR
            // ================================== 

            OPCODE_JALR: begin

                if (instr[14:12] == 3'b000) begin

                    reg_we   = 1'b1;

                    imm_sel  = IMM_I;

                    wb_sel   = WB_PC4;

                    jump     = JUMP_JALR;

                    illegal  = 1'b0;

                end

            end

            // ==================================
            // S-type
            // ================================== 

            OPCODE_STORE: begin

                // SW
                if (instr[14:12] == 3'b010) begin

                    op_a_sel  = OP_A_RS1;
                    op_b_imm  = 1'b1;

                    imm_sel   = IMM_S;

                    alu_op    = ALU_ADD;

                    mem_store = 1'b1;

                    illegal   = 1'b0;

                end

            end

            // ==================================
            // B-type
            // ================================== 

            OPCODE_BRANCH: begin

                imm_sel = IMM_B;

                case (instr[14:12])

                    3'b000: begin
                        branch_type = BR_BEQ;
                        illegal = 1'b0;
                    end

                    3'b001: begin
                        branch_type = BR_BNE;
                        illegal = 1'b0;
                    end

                    3'b100: begin
                        branch_type = BR_BLT;
                        illegal = 1'b0;
                    end

                    3'b101: begin
                        branch_type = BR_BGE;
                        illegal = 1'b0;
                    end

                    3'b110: begin
                        branch_type = BR_BLTU;
                        illegal = 1'b0;
                    end

                    3'b111: begin
                        branch_type = BR_BGEU;
                        illegal = 1'b0;
                    end

                    default: begin
                    end

                endcase

            end

            // ==================================
            // U-type
            // ================================== 

            OPCODE_LUI: begin

                reg_we    = 1'b1;

                op_a_sel  = OP_A_ZERO;
                op_b_imm  = 1'b1;

                imm_sel   = IMM_U;

                alu_op    = ALU_ADD;

                wb_sel    = WB_ALU;

                illegal   = 1'b0;

            end

            OPCODE_AUIPC: begin

                reg_we    = 1'b1;

                op_a_sel  = OP_A_PC;
                op_b_imm  = 1'b1;

                imm_sel   = IMM_U;

                alu_op    = ALU_ADD;

                wb_sel    = WB_ALU;

                illegal   = 1'b0;

            end

            // ==================================
            // J-type
            // ================================== 

            OPCODE_JAL: begin

                reg_we   = 1'b1;

                imm_sel  = IMM_J;

                wb_sel   = WB_PC4;

                jump     = JUMP_JAL;

                illegal  = 1'b0;

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
