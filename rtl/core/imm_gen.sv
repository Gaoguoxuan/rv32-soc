module imm_gen (
    input  logic [31:0] instr,

    output logic [31:0] imm_i,
    output logic [31:0] imm_s,
    output logic [31:0] imm_b
);

    always_comb begin

        // I-type
        // imm[11：0] = instr[31:20]
        imm_i = {{20{instr[31]}}, instr[31:20]};

        // S-type
        // imm[11:5] = instr[31:25]
        // imm[4:0]  = instr[11:7]
        imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};

        // B-type
        //
        // imm[12]   = instr[31]
        // imm[11]   = instr[7]
        // imm[10:5] = instr[30:25]
        // imm[4:1]  = instr[11:8]
        // imm[0]    = 0
        imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};

    end

endmodule
