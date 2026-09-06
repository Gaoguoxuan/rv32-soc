module tb_decoder_m4;

    logic [31:0] instr;

    logic        reg_we;
    logic [3:0]  alu_op;

    logic [1:0]  op_a_sel;
    logic        op_b_imm;

    logic [2:0]  imm_sel;

    logic [2:0]  load_type;
    logic [2:0]  store_type;

    logic        mem_load;
    logic        mem_store;

    logic [1:0]  wb_sel;

    logic [2:0]  branch_type;
    logic [1:0]  jump;

    logic        illegal;

    int errors = 0;


    decoder dut (
        .instr     (instr),

        .reg_we    (reg_we),

        .alu_op    (alu_op),

        .op_a_sel  (op_a_sel),
        .op_b_imm  (op_b_imm),

        .imm_sel   (imm_sel),

        .load_type(load_type),
        .store_type(store_type),

        .mem_load  (mem_load),
        .mem_store (mem_store),

        .wb_sel    (wb_sel),

        .branch_type    (branch_type),
        .jump      (jump),

        .illegal   (illegal)
    );


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

    localparam logic [2:0] BR_NONE = 3'b000;
    localparam logic [2:0] BR_BEQ  = 3'b001;
    localparam logic [2:0] BR_BNE  = 3'b010;
    localparam logic [2:0] BR_BLT  = 3'b011;
    localparam logic [2:0] BR_BGE  = 3'b100;
    localparam logic [2:0] BR_BLTU = 3'b101;
    localparam logic [2:0] BR_BGEU = 3'b110;


    task automatic check_alu(
        input logic [31:0] insn,
        input logic [3:0]  expected_op,
        input logic        expected_imm,
        input string       name
    );

        begin

            instr = insn;

            #1;

            if (
                illegal !== 1'b0 ||
                reg_we !== 1'b1 ||
                alu_op !== expected_op ||
                op_b_imm !== expected_imm
            ) begin

                $display(
                    "[FAIL] %-8s instr=%08x alu=%0d imm=%0d illegal=%0d",
                    name,
                    instr,
                    alu_op,
                    op_b_imm,
                    illegal
                );

                errors++;

            end

            else begin

                $display(
                    "[PASS] %-8s instr=%08x",
                    name,
                    instr
                );

            end

        end

    endtask

    task automatic check_branch(
        input logic [2:0] funct3,
        input logic [2:0] expected_type,
        input string      name
    );
        begin

            instr = 32'b0;

            instr[6:0]   = 7'b1100011;
            instr[14:12] = funct3;

            #1;

            if (
                illegal === 1'b0 &&
                branch_type === expected_type
            ) begin

                $display(
                    "[PASS] %-5s funct3=%03b branch_type=%03b",
                    name,
                    funct3,
                    branch_type
                );

            end
            else begin

                $display(
                    "[FAIL] %-5s funct3=%03b branch_type=%03b expected=%03b",
                    name,
                    funct3,
                    branch_type,
                    expected_type
                );

                errors++;

            end

        end
    endtask


    initial begin

        // R-type

        check_alu(
            32'h002081B3,
            ALU_ADD,
            1'b0,
            "ADD"
        );

        check_alu(
            32'h402081B3,
            ALU_SUB,
            1'b0,
            "SUB"
        );


        // I-type

        check_alu(
            32'h00508193,
            ALU_ADD,
            1'b1,
            "ADDI"
        );

        check_branch(3'b000, BR_BEQ,  "BEQ");
        check_branch(3'b001, BR_BNE,  "BNE");

        check_branch(3'b100, BR_BLT,  "BLT");
        check_branch(3'b101, BR_BGE,  "BGE");

        check_branch(3'b110, BR_BLTU, "BLTU");
        check_branch(3'b111, BR_BGEU, "BGEU");


        if (errors == 0) begin

            $display("");
            $display("=========================");
            $display("   M4.1 DECODER PASS");
            $display("=========================");

        end

        else begin

            $display(
                "%0d TEST(S) FAILED",
                errors
            );

            $fatal(1);

        end


        $finish;

    end

endmodule
