module tb_branch_unit;

    logic [2:0]  branch_type;
    logic [31:0] a;
    logic [31:0] b;
    logic        taken;

    int errors = 0;

    localparam logic [2:0] BR_NONE = 3'b000;
    localparam logic [2:0] BR_BEQ  = 3'b001;
    localparam logic [2:0] BR_BNE  = 3'b010;
    localparam logic [2:0] BR_BLT  = 3'b011;
    localparam logic [2:0] BR_BGE  = 3'b100;
    localparam logic [2:0] BR_BLTU = 3'b101;
    localparam logic [2:0] BR_BGEU = 3'b110;

    branch_unit dut (
        .branch_type (branch_type),
        .a           (a),
        .b           (b),
        .taken       (taken)
    );

    task automatic check(
        input logic [2:0]  type_i,
        input logic [31:0] a_i,
        input logic [31:0] b_i,
        input logic        expected,
        input string       name
    );
        begin

            branch_type = type_i;
            a = a_i;
            b = b_i;

            #1;

            if (taken === expected) begin
                $display("[PASS] %-15s taken=%0d", name, taken);
            end
            else begin
                $display(
                    "[FAIL] %-15s taken=%0d expected=%0d",
                    name,
                    taken,
                    expected
                );

                errors++;
            end

        end
    endtask

    initial begin

        check(BR_BEQ,  32'd5,        32'd5,        1'b1, "BEQ true");
        check(BR_BEQ,  32'd5,        32'd6,        1'b0, "BEQ false");

        check(BR_BNE,  32'd5,        32'd6,        1'b1, "BNE true");
        check(BR_BNE,  32'd5,        32'd5,        1'b0, "BNE false");

        check(BR_BLT,  32'hFFFFFFFF, 32'd1,        1'b1, "BLT -1 < 1");
        check(BR_BGE,  32'hFFFFFFFF, 32'd1,        1'b0, "BGE -1 >= 1");

        check(BR_BLTU, 32'hFFFFFFFF, 32'd1,        1'b0, "BLTU max < 1");
        check(BR_BGEU, 32'hFFFFFFFF, 32'd1,        1'b1, "BGEU max >= 1");

        if (errors == 0) begin
            $display("");
            $display("=========================");
            $display("   BRANCH UNIT PASS");
            $display("=========================");
        end
        else begin
            $fatal(1, "%0d TEST(S) FAILED", errors);
        end

        $finish;

    end

endmodule