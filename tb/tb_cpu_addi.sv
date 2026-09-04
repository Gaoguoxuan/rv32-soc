module tb_cpu_addi;

    logic clk;
    logic rst;

    logic [31:0] instr;
    logic [31:0] pc;

    logic        dbg_reg_we;
    logic [4:0]  dbg_rd_addr;
    logic [31:0] dbg_rd_data;
    logic [31:0] dbg_rs1_data;
    logic [31:0] dbg_imm;
    logic        dbg_illegal;

    int errors = 0;


    cpu_core dut (
        .clk          (clk),
        .rst          (rst),

        .instr        (instr),
        .pc           (pc),

        .dbg_reg_we   (dbg_reg_we),
        .dbg_rd_addr  (dbg_rd_addr),
        .dbg_rd_data  (dbg_rd_data),
        .dbg_rs1_data (dbg_rs1_data),
        .dbg_imm      (dbg_imm),
        .dbg_illegal  (dbg_illegal)
    );


    // ==============================
    // Clock
    // ==============================

    initial begin
        clk = 1'b0;

        forever #5 clk = ~clk;
    end


    // ==============================
    // Tiny instruction ROM
    // ==============================

    always_comb begin

        case (pc)

            // addi x1, x0, 5
            32'h00000000:
                instr = 32'h00500093;

            // addi x2, x1, 7
            32'h00000004:
                instr = 32'h00708113;

            // addi x3, x2, -2
            32'h00000008:
                instr = 32'hFFE10193;

            // addi x0, x0, 123
            // should NOT modify x0
            32'h0000000C:
                instr = 32'h07B00013;

            // addi x4, x0, 1
            // verifies x0 is still zero
            32'h00000010:
                instr = 32'h00100213;

            // addi x5, x4, 9
            32'h00000014:
                instr = 32'h00920293;

            // NOP = addi x0, x0, 0
            default:
                instr = 32'h00000013;

        endcase

    end


    task automatic check_cycle (
        input logic [31:0] expected_pc,
        input logic        expected_we,
        input logic [4:0]  expected_rd,
        input logic [31:0] expected_data,
        input string       test_name
    );

        begin

            #1;

            if (pc !== expected_pc) begin

                $display(
                    "[FAIL] %-20s PC=%08x expected=%08x",
                    test_name,
                    pc,
                    expected_pc
                );

                errors++;

            end
            else if (dbg_illegal !== 1'b0) begin

                $display(
                    "[FAIL] %-20s illegal instruction",
                    test_name
                );

                errors++;

            end
            else if (dbg_reg_we !== expected_we) begin

                $display(
                    "[FAIL] %-20s WE=%0d expected=%0d",
                    test_name,
                    dbg_reg_we,
                    expected_we
                );

                errors++;

            end
            else if (
                expected_we &&
                (
                    dbg_rd_addr !== expected_rd ||
                    dbg_rd_data !== expected_data
                )
            ) begin

                $display(
                    "[FAIL] %-20s rd=x%0d data=%08x expected x%0d=%08x",
                    test_name,
                    dbg_rd_addr,
                    dbg_rd_data,
                    expected_rd,
                    expected_data
                );

                errors++;

            end
            else begin

                if (expected_we) begin

                    $display(
                        "[PASS] %-20s PC=%08x -> x%0d=%08x",
                        test_name,
                        pc,
                        dbg_rd_addr,
                        dbg_rd_data
                    );

                end
                else begin

                    $display(
                        "[PASS] %-20s PC=%08x no register write",
                        test_name,
                        pc
                    );

                end

            end


            // 当前指令在接下来的 posedge 写回
            @(posedge clk);

            #1;

            // 等到下一周期中间
            @(negedge clk);

        end

    endtask


    initial begin

        $dumpfile("build/cpu_addi.vcd");

        $dumpvars(0, tb_cpu_addi);


        rst = 1'b1;


        // reset for two cycles
        repeat (2)
            @(posedge clk);


        @(negedge clk);

        rst = 1'b0;


        check_cycle(
            32'h00000000,
            1'b1,
            5'd1,
            32'd5,
            "ADDI x1,x0,5"
        );


        check_cycle(
            32'h00000004,
            1'b1,
            5'd2,
            32'd12,
            "ADDI x2,x1,7"
        );


        check_cycle(
            32'h00000008,
            1'b1,
            5'd3,
            32'd10,
            "ADDI x3,x2,-2"
        );


        check_cycle(
            32'h0000000C,
            1'b0,
            5'd0,
            32'd0,
            "WRITE x0 BLOCKED"
        );


        check_cycle(
            32'h00000010,
            1'b1,
            5'd4,
            32'd1,
            "x0 STILL ZERO"
        );


        check_cycle(
            32'h00000014,
            1'b1,
            5'd5,
            32'd10,
            "ADDI x5,x4,9"
        );


        if (errors == 0) begin

            $display("");
            $display("==============================");
            $display("         M2 ALL PASS");
            $display("==============================");

        end
        else begin

            $display("");
            $display(
                "%0d TEST(S) FAILED",
                errors
            );

            $fatal(1);

        end


        $finish;

    end

endmodule
