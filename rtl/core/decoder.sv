module decoder (
    input  logic [31:0] instr,

    output logic        reg_we,
    output logic        alu_src_imm,
    output logic [3:0]  alu_op,

    output logic [1:0]  imm_sel,

    output logic        mem_we,
    // 写回寄存器的数据来源
    // 1 -> RAM
    // 0 -> ALU
    output logic        wb_sel_mem,

    output logic        branch_beq,

    output logic        illegal
);

    // Opecodes
    localparam logic [6:0] OPCODE_OP     = 7'b0110011;
    localparam logic [6:0] OPCODE_OP_IMM = 7'b0010011;
    localparam logic [6:0] OPCODE_LOAD   = 7'b0000011;
    localparam logic [6:0] OPCODE_STORE  = 7'b0100011;
    localparam logic [6:0] OPCODE_BRANCH = 7'b1100011;

    // ALU operations
    localparam logic [3:0] ALU_ADD = 4'b0000;
    localparam logic [3:0] ALU_SUB = 4'b0001;

    // Immediate selection
    localparam logic [1:0] IMM_I = 2'b00;
    localparam logic [1:0] IMM_S = 2'b01;
    localparam logic [1:0] IMM_B = 2'b10;

    always_comb begin

        // Safe defaults
        reg_we      = 1'b0;
        alu_src_imm = 1'b0;
        alu_op      = ALU_ADD;

        imm_sel     = IMM_I;

        mem_we      = 1'b0;
        wb_sel_mem  = 1'b0;

        branch_beq  = 1'b0;

        illegal     = 1'b1;

        case (instr[6:0])

            //=================================
            // R-type： ADD / SUB
            //=================================

            OPCODE_OP: begin
                
                if (instr[14:12] == 3'b000) begin
                    
                    // ADD
                    if (instr[31:25] == 7'b0000000) begin
                        reg_we      = 1'b1;
                        alu_src_imm = 1'b0;
                        alu_op      = ALU_ADD;
                        illegal     = 1'b0;
                    end

                    // SUB
                    else if (instr[31:25] == 7'b0100000) begin
                        reg_we      = 1'b1;
                        alu_src_imm = 1'b0;
                        alu_op      = ALU_SUB;
                        illegal     = 1'b0;
                    end
                end
            end

            //=================================
            // I-type： ADDI 
            //=================================

            OPCODE_OP_IMM: begin

                // funct3 == 000 → ADDI
                if (instr[14:12] == 3'b000) begin
                    reg_we      = 1'b1;
                    alu_src_imm = 1'b1;
                    alu_op      = ALU_ADD;
                    illegal     = 1'b0;
                end

            end

            //=================================
            // LOAD: LW
            //=================================

            OPCODE_LOAD: begin
                
                if (instr[14:12] == 3'b010) begin
                    reg_we      = 1'b1;
                    alu_src_imm = 1'b0;
                    alu_op      = ALU_ADD;
                    imm_sel     = IMM_I;
                    wb_sel_mem  = 1'b1;
                    illegal     = 1'b0;
                end
            end

            //=================================
            // STORE: SW
            //=================================

            OPCODE_STORE: begin
                
                if (instr[14:12] == 3'b010) begin
                    alu_src_imm = 1'b1;
                    alu_op      = ALU_ADD;
                    imm_sel     = IMM_S;
                    mem_we      = 1'b1;
                    illegal     = 1'b0;
                end
            end

            //=================================
            // BRANCH: BEQ
            //=================================

            OPCODE_BRANCH: begin
                
                if (instr[14:12] == 3'b000) begin
                    imm_sel     = IMM_B;
                    branch_beq  = 1'b1;
                    illegal     = 1'b0;
                end
            end

            default: begin
            end

        endcase
    end

endmodule
