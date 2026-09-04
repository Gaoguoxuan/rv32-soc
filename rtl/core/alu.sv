module alu(
    input   logic [31:0] a,
    input   logic [31:0] b,
    input   logic [3:0]  op,
    output  logic [31:0] res
);

    localparam logic [3:0] ALU_ADD  = 4'b0000;
    localparam logic [3:0] ALU_SUB  = 4'B0001;
    localparam logic [3:0] ALU_AND  = 4'b0010;
    localparam logic [3:0] ALU_OR   = 4'b0011;
    localparam logic [3:0] ALU_XOR  = 4'b0100;
    localparam logic [3:0] ALU_SLL  = 4'b0101;
    localparam logic [3:0] ALU_SRL  = 4'b0110;
    localparam logic [3:0] ALU_SRA  = 4'b0111;
    localparam logic [3:0] ALU_SLT  = 4'b1000;
    localparam logic [3:0] ALU_SLTU = 4'b1001;

    always_comb begin
        case (op)

            ALU_ADD : begin
                res = a + b;
            end

            ALU_SUB : begin
                res = a - b;
            end

            ALU_AND : begin
                res = a & b;
            end

            ALU_OR  : begin
                res = a | b;
            end

            ALU_XOR : begin
                res = a ^ b;
            end

            ALU_SLL : begin
                res = a << b[4:0];
            end

            ALU_SRL : begin
                res = a >> b[4:0];
            end

            ALU_SRA : begin
                res = $signed(a) >>> b[4:0];
            end

            ALU_SLT : begin
                res = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            end

            ALU_SLTU : begin
                res = (a < b) ? 32'd1 : 32'd0;
            end

            default : begin
                res = 32'd0;
            end

        endcase
    end

endmodule
