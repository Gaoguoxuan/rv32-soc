module tb_decoder_m4;

    logic [31:0] instr;

    logic        reg_we;
    logic [3:0]  alu_op;

    logic [1:0]  op_a_sel;
    logic        op_b_imm;

    logic [2:0]  imm_sel;

    logic        mem_load;
    logic        mem_store;

    logic [1:0]  wb_sel;

    logic        branch;
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

        .mem_load  (mem_load),
        .mem_store (mem_store),

        .wb_sel    (wb_sel),

        .branch    (branch),
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
