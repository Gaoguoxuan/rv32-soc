module tb_regfile;

    logic        clk;
    logic        rst;

    logic        we;
    logic [4:0]  rd_addr;
    logic [31:0] rd_data;

    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;

    int errors = 0;

    regfile dut (
        .clk      (clk),
        .rst      (rst),

        .we       (we),
        .rd_addr  (rd_addr),
        .rd_data  (rd_data),

        .rs1_addr (rs1_addr),
        .rs2_addr (rs2_addr),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic write_reg(
        input logic [4:0]  addr,
        input logic [31:0] data
    );
        begin
            @(negedge clk);

            we      = 1'b1;
            rd_addr = addr;
            rd_data = data;

            @(posedge clk);
            #1;

            we = 1'b0;
        end
    endtask

    task automatic check_reg(
        input logic [4:0]  addr,
        input logic [31:0] expected,
        input string       test_name
    );
        begin
            rs1_addr = addr;
            #1;

            if (rs1_data === expected) begin
                $display(
                    "[PASS] %-20s x%0d = %08x",
                    test_name,
                    addr,
                    rs1_data
                );
            end
            else begin
                $display(
                    "[FAIL] %-20s x%0d = %08x expected=%08x",
                    test_name,
                    addr,
                    rs1_data,
                    expected
                );

                errors++;
            end
        end
    endtask

    initial begin

        $dumpfile("build/regfile.vcd");
        $dumpvars(0, tb_regfile);

        rst      = 1'b1;
        we       = 1'b0;

        rd_addr  = 5'd0;
        rd_data  = 32'd0;

        rs1_addr = 5'd0;
        rs2_addr = 5'd0;

        repeat (2) @(posedge clk);

        #1;
        rst = 1'b0;

        // -------------------------
        // Test 1: reset
        // -------------------------

        check_reg(5'd1, 32'd0, "RESET x1");

        // -------------------------
        // Test 2: write/read x1
        // -------------------------

        write_reg(5'd1, 32'd100);

        check_reg(
            5'd1,
            32'd100,
            "WRITE x1"
        );

        // -------------------------
        // Test 3: write/read x2
        // -------------------------

        write_reg(
            5'd2,
            32'h12345678
        );

        check_reg(
            5'd2,
            32'h12345678,
            "WRITE x2"
        );

        // -------------------------
        // Test 4: dual read
        // -------------------------

        rs1_addr = 5'd1;
        rs2_addr = 5'd2;

        #1;

        if (
            rs1_data === 32'd100 &&
            rs2_data === 32'h12345678
        ) begin

            $display(
                "[PASS] DUAL READ            x1=%08x x2=%08x",
                rs1_data,
                rs2_data
            );

        end
        else begin

            $display(
                "[FAIL] DUAL READ            x1=%08x x2=%08x",
                rs1_data,
                rs2_data
            );

            errors++;
        end

        // -------------------------
        // Test 5: overwrite
        // -------------------------

        write_reg(
            5'd1,
            32'hDEADBEEF
        );

        check_reg(
            5'd1,
            32'hDEADBEEF,
            "OVERWRITE x1"
        );

        // -------------------------
        // Test 6: x0 cannot be written
        // -------------------------

        write_reg(
            5'd0,
            32'hFFFFFFFF
        );

        check_reg(
            5'd0,
            32'd0,
            "x0 HARDWIRED ZERO"
        );

        // -------------------------
        // Summary
        // -------------------------

        if (errors == 0) begin

            $display("");
            $display("=========================");
            $display("      ALL TESTS PASS");
            $display("=========================");

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