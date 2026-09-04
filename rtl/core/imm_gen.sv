module imm_gen (
    input  logic [31:0] instr,
    output logic [31:0] imm_i
);

    always_comb begin
        imm_i = {{20{instr[31]}}, instr[31:20]};
    end

endmodule
