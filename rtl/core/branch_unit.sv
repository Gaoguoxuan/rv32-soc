module branch_unit (
    input  logic [2:0]  branch_type,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic        taken
);

    localparam logic [2:0] BR_NONE = 3'b000;
    localparam logic [2:0] BR_BEQ  = 3'b001;
    localparam logic [2:0] BR_BNE  = 3'b010;
    localparam logic [2:0] BR_BLT  = 3'b011;
    localparam logic [2:0] BR_BGE  = 3'b100;
    localparam logic [2:0] BR_BLTU = 3'b101;
    localparam logic [2:0] BR_BGEU = 3'b110;

    always_comb begin

        taken = 1'b0;

        case (branch_type)

            BR_BEQ:
                taken = (a == b);

            BR_BNE:
                taken = (a != b);

            BR_BLT:
                taken = ($signed(a) < $signed(b));

            BR_BGE:
                taken = ($signed(a) >= $signed(b));

            BR_BLTU:
                taken = (a < b);

            BR_BGEU:
                taken = (a >= b);

            default:
                taken = 1'b0;

        endcase

    end

endmodule
