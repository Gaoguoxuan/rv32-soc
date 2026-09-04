module tb_alu;

    logic [31:0] a;
    logic [31:0] b;
    logic [3:0]  op;
    logic [31:0] res;

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

    int errors = 0;

    alu dut (
        .a      (a),
        .b      (b),
        .op     (op),
        .res    (res)
    );

    task automatic check(
        input logic [3:0]  op_i,
        input logic [31:0] a_i,
        input logic [31:0] b_i,
        input logic [31:0] expected,
        input string       test_name
    );
        begin
            op = op_i;
            a  = a_i;
            b  = b_i;

            #1;
            if (res === expected) begin
                $display("[PASS] %-12s a=%08x b=%08x result=%08x",
                        test_name,a,b,res);
            end
            else begin
                $display("[FAIL] %-12s a=%08x b=%08x result=%08x expected=%08x",
                        test_name,a,b,res,expected);
                errors++;
            end
        end
    endtask

    initial begin
        
        $dumpfile("build/alu.vcd");
        $dumpvars(0, tb_alu);

        check(ALU_ADD,  32'd5,        32'd7,        32'd12,       "ADD");
        check(ALU_SUB,  32'd10,       32'd3,        32'd7,        "SUB");

        check(ALU_AND,  32'hF0F0F0F0, 32'h0FF00FF0, 32'h00F000F0, "AND");
        check(ALU_OR,   32'hF000000F, 32'h0F0000F0, 32'hFF0000FF, "OR");
        check(ALU_XOR,  32'hFFFF0000, 32'h00FFFF00, 32'hFF00FF00, "XOR");

        check(ALU_SLL,  32'h00000001, 32'd4,        32'h00000010, "SLL");
        check(ALU_SRL,  32'h80000000, 32'd1,        32'h40000000, "SRL");
        check(ALU_SRA,  32'h80000000, 32'd1,        32'hC0000000, "SRA");

        check(ALU_SLT,  32'hFFFFFFFF, 32'd1,        32'd1,        "SLT");
        check(ALU_SLTU, 32'hFFFFFFFF, 32'd1,        32'd0,        "SLTU");

        if(errors == 0) begin
            $display("");
            $display("=========================");
            $display("      ALL TESTS PASS");
            $display("=========================");
        end
        else begin
            $display("");
            $display("%0d TEST(S) FAILED", errors);
            $fatal(1);
        end

        $finish;
    end


endmodule
