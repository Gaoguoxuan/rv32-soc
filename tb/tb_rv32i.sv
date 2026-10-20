module tb_rv32i;

    // ============================================================
    // Clock / Reset
    // ============================================================

    logic clk;
    logic rst;


    // ============================================================
    // Instruction interface
    // ============================================================

    logic [31:0] pc;
    logic [31:0] instr;


    // ============================================================
    // Data memory interface
    // ============================================================

    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;

    logic        mem_we;
    logic [3:0]  mem_wstrb;


    // ============================================================
    // Memories
    // ============================================================

    logic [31:0] imem [0:255];
    logic [31:0] dmem [0:63];


    // ============================================================
    // Test statistics
    // ============================================================

    integer total_tests  = 0;
    integer passed_tests = 0;
    integer failed_tests = 0;


    // ============================================================
    // Opcodes
    // ============================================================

    localparam logic [6:0] OP       = 7'b0110011;
    localparam logic [6:0] OP_IMM   = 7'b0010011;

    localparam logic [6:0] LOAD     = 7'b0000011;
    localparam logic [6:0] STORE    = 7'b0100011;

    localparam logic [6:0] BRANCH   = 7'b1100011;

    localparam logic [6:0] LUI      = 7'b0110111;
    localparam logic [6:0] AUIPC    = 7'b0010111;

    localparam logic [6:0] JAL      = 7'b1101111;
    localparam logic [6:0] JALR     = 7'b1100111;


    localparam logic [31:0] NOP = 32'h00000013;


    // ============================================================
    // DUT
    // ============================================================

    cpu_core dut (
        .clk       (clk),
        .rst       (rst),

        .timer_irq (1'b0),

        .instr     (instr),
        .pc        (pc),

        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_rdata (mem_rdata),

        .mem_we    (mem_we),
        .mem_wstrb (mem_wstrb)
    );


    // ============================================================
    // Clock
    // ============================================================

    initial begin
        clk = 1'b0;

        forever #5
            clk = ~clk;
    end


    // ============================================================
    // Instruction fetch
    // ============================================================

    always_comb begin

        if (pc < 32'd1024)
            instr = imem[pc[9:2]];
        else
            instr = NOP;

    end


    // ============================================================
    // Data memory read
    //
    // Asynchronous read
    // ============================================================

    always_comb begin
        mem_rdata = dmem[mem_addr[7:2]];
    end


    // ============================================================
    // Data memory write
    //
    // Synchronous write + byte enable
    // ============================================================

    always_ff @(posedge clk) begin

        if (!rst && mem_we) begin

            if (mem_wstrb[0])
                dmem[mem_addr[7:2]][7:0] <= mem_wdata[7:0];

            if (mem_wstrb[1])
                dmem[mem_addr[7:2]][15:8] <= mem_wdata[15:8];

            if (mem_wstrb[2])
                dmem[mem_addr[7:2]][23:16] <= mem_wdata[23:16];

            if (mem_wstrb[3])
                dmem[mem_addr[7:2]][31:24] <= mem_wdata[31:24];

        end

    end


    // ============================================================
    // R-type encoder
    // ============================================================

    function automatic logic [31:0] enc_r (
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );

        enc_r = {
            funct7,
            rs2,
            rs1,
            funct3,
            rd,
            opcode
        };

    endfunction


    // ============================================================
    // I-type encoder
    // ============================================================

    function automatic logic [31:0] enc_i (
        input logic signed [31:0] imm,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );

        enc_i = {
            imm[11:0],
            rs1,
            funct3,
            rd,
            opcode
        };

    endfunction


    // ============================================================
    // S-type encoder
    // ============================================================

    function automatic logic [31:0] enc_s (
        input logic signed [31:0] imm,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [6:0] opcode
    );

        enc_s = {
            imm[11:5],
            rs2,
            rs1,
            funct3,
            imm[4:0],
            opcode
        };

    endfunction


    // ============================================================
    // B-type encoder
    // ============================================================

    function automatic logic [31:0] enc_b (
        input logic signed [31:0] imm,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [6:0] opcode
    );

        enc_b = {
            imm[12],
            imm[10:5],
            rs2,
            rs1,
            funct3,
            imm[4:1],
            imm[11],
            opcode
        };

    endfunction


    // ============================================================
    // U-type encoder
    // ============================================================

    function automatic logic [31:0] enc_u (
        input logic [19:0] imm,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );

        enc_u = {
            imm,
            rd,
            opcode
        };

    endfunction


    // ============================================================
    // J-type encoder
    // ============================================================

    function automatic logic [31:0] enc_j (
        input logic signed [31:0] imm,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );

        enc_j = {
            imm[20],
            imm[10:1],
            imm[11],
            imm[19:12],
            rd,
            opcode
        };

    endfunction


    // ============================================================
    // Prepare one isolated test
    // ============================================================

    task automatic prepare_test;

        integer i;

        begin

            rst = 1'b1;

            for (i = 0; i < 256; i = i + 1)
                imem[i] = NOP;

            for (i = 0; i < 64; i = i + 1)
                dmem[i] = 32'b0;

        end

    endtask


    // ============================================================
    // Release reset
    // ============================================================

    task automatic release_reset;

        begin

            repeat (2)
                @(posedge clk);

            @(negedge clk);

            rst = 1'b0;

        end

    endtask


    // ============================================================
    // Run CPU
    // ============================================================

    task automatic run_cycles (
        input integer cycles
    );

        begin

            repeat (cycles)
                @(posedge clk);

            #1;

        end

    endtask


    // ============================================================
    // Report
    // ============================================================

    task automatic report (
        input string name,
        input logic  success
    );

        begin

            total_tests++;

            if (success) begin

                passed_tests++;

                $display(
                    "[PASS] %-8s",
                    name
                );

            end

            else begin

                failed_tests++;

                $display(
                    "[FAIL] %-8s",
                    name
                );

            end

        end

    endtask


    // ============================================================
    // Generic R-type test
    // ============================================================

    task automatic test_r (
        input string name,

        input logic [6:0] funct7,
        input logic [2:0] funct3,

        input integer signed a,
        input integer signed b,

        input logic [31:0] expected
    );

        begin

            prepare_test();


            // x1 = a
            imem[0] = enc_i(
                a,
                5'd0,
                3'b000,
                5'd1,
                OP_IMM
            );


            // x2 = b
            imem[1] = enc_i(
                b,
                5'd0,
                3'b000,
                5'd2,
                OP_IMM
            );


            // target instruction:
            // x3 = op(x1, x2)
            imem[2] = enc_r(
                funct7,
                5'd2,
                5'd1,
                funct3,
                5'd3,
                OP
            );


            release_reset();

            run_cycles(3);


            report(
                name,
                dut.u_regfile.regs[3] === expected
            );

        end

    endtask


    // ============================================================
    // Generic I-type ALU test
    // ============================================================

    task automatic test_i (
        input string name,

        input logic [2:0] funct3,

        input integer signed a,
        input integer signed imm,

        input logic [31:0] expected
    );

        begin

            prepare_test();


            // x1 = a
            imem[0] = enc_i(
                a,
                5'd0,
                3'b000,
                5'd1,
                OP_IMM
            );


            // x3 = op(x1, imm)
            imem[1] = enc_i(
                imm,
                5'd1,
                funct3,
                5'd3,
                OP_IMM
            );


            release_reset();

            run_cycles(2);


            report(
                name,
                dut.u_regfile.regs[3] === expected
            );

        end

    endtask


    // ============================================================
    // Load test
    // ============================================================

    task automatic test_load (
        input string name,

        input logic [2:0] funct3,

        input integer address,

        input logic [31:0] expected
    );

        begin

            prepare_test();


            // Little endian:
            //
            // addr 0 = 01
            // addr 1 = 7F
            // addr 2 = FF
            // addr 3 = 80

            dmem[0] = 32'h80FF7F01;


            imem[0] = enc_i(
                address,
                5'd0,
                funct3,
                5'd3,
                LOAD
            );


            release_reset();

            run_cycles(1);


            report(
                name,
                dut.u_regfile.regs[3] === expected
            );

        end

    endtask


    // ============================================================
    // Store test
    // ============================================================

    task automatic test_store (
        input string name,

        input logic [2:0] funct3,

        input integer value,
        input integer address,

        input logic [31:0] initial_word,
        input logic [31:0] expected_word
    );

        begin

            prepare_test();


            dmem[0] = initial_word;


            // x1 = value
            imem[0] = enc_i(
                value,
                5'd0,
                3'b000,
                5'd1,
                OP_IMM
            );


            // store x1,address(x0)
            imem[1] = enc_s(
                address,
                5'd1,
                5'd0,
                funct3,
                STORE
            );


            release_reset();

            run_cycles(2);


            report(
                name,
                dmem[0] === expected_word
            );

        end

    endtask


    // ============================================================
    // Branch test
    // ============================================================

    task automatic test_branch (
        input string name,

        input logic [2:0] funct3,

        input integer signed a,
        input integer signed b,

        input logic expected_taken
    );

        logic [31:0] expected_x10;

        begin

            prepare_test();


            // x1 = a
            imem[0] = enc_i(
                a,
                5'd0,
                3'b000,
                5'd1,
                OP_IMM
            );


            // x2 = b
            imem[1] = enc_i(
                b,
                5'd0,
                3'b000,
                5'd2,
                OP_IMM
            );


            // PC = 8
            //
            // branch +8 -> PC 16
            //
            // taken     : skip imem[3]
            // not taken : execute imem[3]

            imem[2] = enc_b(
                8,
                5'd2,
                5'd1,
                funct3,
                BRANCH
            );


            // Fall-through marker
            imem[3] = enc_i(
                1,
                5'd0,
                3'b000,
                5'd10,
                OP_IMM
            );


            // Branch target marker
            imem[4] = enc_i(
                1,
                5'd0,
                3'b000,
                5'd11,
                OP_IMM
            );


            release_reset();

            run_cycles(6);


            if (expected_taken)
                expected_x10 = 32'd0;
            else
                expected_x10 = 32'd1;

            $display(
                "DEBUG %-5s a=%08x b=%08x x10=%08x x11=%08x",
                name,
                dut.u_regfile.regs[1],
                dut.u_regfile.regs[2],
                dut.u_regfile.regs[10],
                dut.u_regfile.regs[11]
            );


            report(
                name,

                (
                    dut.u_regfile.regs[10]
                        === expected_x10
                )
                &&
                (
                    dut.u_regfile.regs[11]
                        === 32'd1
                )
            );

        end

    endtask


    // ============================================================
    // Main regression
    // ============================================================

    initial begin

        rst = 1'b1;


        $dumpfile(
            "build/rv32i.vcd"
        );

        $dumpvars(
            0,
            tb_rv32i
        );


        // ========================================================
        // R-type
        // ========================================================

        $display("");
        $display("========== R-TYPE ==========");


        test_r(
            "ADD",
            7'b0000000,
            3'b000,
            10,
            3,
            32'd13
        );


        test_r(
            "SUB",
            7'b0100000,
            3'b000,
            10,
            3,
            32'd7
        );


        test_r(
            "SLL",
            7'b0000000,
            3'b001,
            3,
            2,
            32'd12
        );


        test_r(
            "SLT",
            7'b0000000,
            3'b010,
            -1,
            1,
            32'd1
        );


        test_r(
            "SLTU",
            7'b0000000,
            3'b011,
            -1,
            1,
            32'd0
        );


        test_r(
            "XOR",
            7'b0000000,
            3'b100,
            10,
            3,
            32'd9
        );


        test_r(
            "SRL",
            7'b0000000,
            3'b101,
            -16,
            1,
            32'h7FFFFFF8
        );


        test_r(
            "SRA",
            7'b0100000,
            3'b101,
            -16,
            1,
            32'hFFFFFFF8
        );


        test_r(
            "OR",
            7'b0000000,
            3'b110,
            10,
            3,
            32'd11
        );


        test_r(
            "AND",
            7'b0000000,
            3'b111,
            10,
            3,
            32'd2
        );


        // ========================================================
        // I-type ALU
        // ========================================================

        $display("");
        $display("========== I-TYPE ==========");


        // ADDI 单独测试，避免完全依赖 helper setup

        prepare_test();

        imem[0] = enc_i(
            -5,
            5'd0,
            3'b000,
            5'd3,
            OP_IMM
        );

        release_reset();

        run_cycles(1);

        report(
            "ADDI",
            dut.u_regfile.regs[3]
                === 32'hFFFFFFFB
        );


        test_i(
            "SLTI",
            3'b010,
            -1,
            1,
            32'd1
        );


        test_i(
            "SLTIU",
            3'b011,
            -1,
            1,
            32'd0
        );


        test_i(
            "XORI",
            3'b100,
            32'h55,
            32'h0F,
            32'h0000005A
        );


        test_i(
            "ORI",
            3'b110,
            32'h50,
            32'h0F,
            32'h0000005F
        );


        test_i(
            "ANDI",
            3'b111,
            32'h5F,
            32'h0F,
            32'h0000000F
        );


        // SLLI
        test_i(
            "SLLI",
            3'b001,
            3,
            4,
            32'd48
        );


        // SRLI
        test_i(
            "SRLI",
            3'b101,
            -16,
            12'h001,
            32'h7FFFFFF8
        );


        // SRAI
        //
        // imm[11:5] = 0100000
        // shamt     = 1
        //
        // immediate encoding = 0x401

        test_i(
            "SRAI",
            3'b101,
            -16,
            12'h401,
            32'hFFFFFFF8
        );


        // ========================================================
        // LOAD
        // ========================================================

        $display("");
        $display("=========== LOAD ===========");


        test_load(
            "LB",
            3'b000,
            3,
            32'hFFFFFF80
        );


        test_load(
            "LH",
            3'b001,
            2,
            32'hFFFF80FF
        );


        test_load(
            "LW",
            3'b010,
            0,
            32'h80FF7F01
        );


        test_load(
            "LBU",
            3'b100,
            3,
            32'h00000080
        );


        test_load(
            "LHU",
            3'b101,
            2,
            32'h000080FF
        );


        // ========================================================
        // STORE
        // ========================================================

        $display("");
        $display("========== STORE ===========");


        // initial bytes:
        //
        // addr 0 = 44
        // addr 1 = 33
        // addr 2 = 22
        // addr 3 = 11

        test_store(
            "SB",
            3'b000,
            8'hAA,
            1,
            32'h11223344,
            32'h1122AA44
        );


        test_store(
            "SH",
            3'b001,
            12'h7AB,
            2,
            32'h11223344,
            32'h07AB3344
        );


        test_store(
            "SW",
            3'b010,
            12'h123,
            0,
            32'h11223344,
            32'h00000123
        );


        // ========================================================
        // BRANCH
        // ========================================================

        $display("");
        $display("========== BRANCH ==========");


        test_branch(
            "BEQ",
            3'b000,
            5,
            5,
            1'b1
        );


        test_branch(
            "BNE",
            3'b001,
            5,
            5,
            1'b0
        );


        test_branch(
            "BLT",
            3'b100,
            -1,
            1,
            1'b1
        );


        test_branch(
            "BGE",
            3'b101,
            -1,
            1,
            1'b0
        );


        test_branch(
            "BLTU",
            3'b110,
            -1,
            1,
            1'b0
        );


        test_branch(
            "BGEU",
            3'b111,
            -1,
            1,
            1'b1
        );


        // ========================================================
        // LUI
        // ========================================================

        $display("");
        $display("========= U/J TYPE =========");


        prepare_test();


        imem[0] = enc_u(
            20'h12345,
            5'd3,
            LUI
        );


        release_reset();

        run_cycles(1);


        report(
            "LUI",
            dut.u_regfile.regs[3]
                === 32'h12345000
        );


        // ========================================================
        // AUIPC
        //
        // Execute at PC = 4
        //
        // expected:
        //
        // 0x00000004 + 0x00001000
        // = 0x00001004
        // ========================================================

        prepare_test();


        imem[0] = NOP;

        imem[1] = enc_u(
            20'h00001,
            5'd4,
            AUIPC
        );


        release_reset();

        run_cycles(2);


        report(
            "AUIPC",
            dut.u_regfile.regs[4]
                === 32'h00001004
        );


        // ========================================================
        // JAL
        //
        // PC 0 -> PC 8
        //
        // x5 = return address = 4
        // ========================================================

        prepare_test();


        imem[0] = enc_j(
            8,
            5'd5,
            JAL
        );


        // Must be skipped
        imem[1] = enc_i(
            1,
            5'd0,
            3'b000,
            5'd10,
            OP_IMM
        );


        // Target
        imem[2] = enc_i(
            1,
            5'd0,
            3'b000,
            5'd11,
            OP_IMM
        );


        release_reset();

        run_cycles(4);


        report(
            "JAL",

            (
                dut.u_regfile.regs[5]
                    === 32'd4
            )
            &&
            (
                dut.u_regfile.regs[10]
                    === 32'd0
            )
            &&
            (
                dut.u_regfile.regs[11]
                    === 32'd1
            )
        );


        // ========================================================
        // JALR
        //
        // x1 = 13
        //
        // JALR target:
        //
        // 13 & ~1 = 12
        //
        // This deliberately verifies bit 0 clearing.
        // ========================================================

        prepare_test();


        // x1 = 13
        imem[0] = enc_i(
            13,
            5'd0,
            3'b000,
            5'd1,
            OP_IMM
        );


        // PC = 4
        //
        // jalr x5,0(x1)
        //
        // x5 = 8
        // target = 12

        imem[1] = enc_i(
            0,
            5'd1,
            3'b000,
            5'd5,
            JALR
        );


        // Must be skipped
        imem[2] = enc_i(
            1,
            5'd0,
            3'b000,
            5'd10,
            OP_IMM
        );


        // Target PC = 12
        imem[3] = enc_i(
            1,
            5'd0,
            3'b000,
            5'd11,
            OP_IMM
        );


        release_reset();

        run_cycles(5);


        report(
            "JALR",

            (
                dut.u_regfile.regs[5]
                    === 32'd8
            )
            &&
            (
                dut.u_regfile.regs[10]
                    === 32'd0
            )
            &&
            (
                dut.u_regfile.regs[11]
                    === 32'd1
            )
        );


        // ========================================================
        // Summary
        // ========================================================

        $display("");
        $display("================================");
        $display("       RV32I REGRESSION");
        $display("================================");

        $display(
            "Passed : %0d",
            passed_tests
        );

        $display(
            "Failed : %0d",
            failed_tests
        );

        $display(
            "Total  : %0d",
            total_tests
        );


        if (
            failed_tests == 0 &&
            total_tests == 37
        ) begin

            $display("");
            $display("==============================");
            $display("        37 / 37 PASS");
            $display("==============================");

        end

        else begin

            $display("");
            $display("==============================");
            $display("      REGRESSION FAILED");
            $display("==============================");

            $fatal(
                1,
                "%0d test(s) failed",
                failed_tests
            );

        end


        $finish;

    end

endmodule
