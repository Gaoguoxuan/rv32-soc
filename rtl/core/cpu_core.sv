module cpu_core (
    input  logic        clk,
    input  logic        rst,

    input  logic [31:0] instr,
    output logic [31:0] pc,

    // Debug signals
    output logic        dbg_reg_we,
    output logic [4:0]  dbg_rd_addr,
    output logic [31:0] dbg_rd_data,
    output logic [31:0] dbg_rs1_data,
    output logic [31:0] dbg_imm,
    output logic        dbg_illegal
);

    logic [31:0] next_pc;

    logic [4:0] rs1_addr;
    logic [4:0] rs2_addr;
    logic [4:0] rd_addr;

    logic [31:0] rs1_data;
    logic [31:0] rs2_data;

    logic [31:0] imm_i;

    logic        reg_we;
    logic        rf_we;
    logic        alu_src_imm;
    logic [3:0]  alu_op;
    logic        illegal;

    logic [31:0] alu_b;
    logic [31:0] alu_result;


    // ==============================
    // PC
    // ==============================

    assign next_pc = pc + 32'd4;

    pc u_pc (
        .clk     (clk),
        .rst     (rst),
        .next_pc (next_pc),
        .pc      (pc)
    );


    // ==============================
    // Instruction fields
    // ==============================

    assign rd_addr  = instr[11:7];
    assign rs1_addr = instr[19:15];
    assign rs2_addr = instr[24:20];


    // ==============================
    // Decoder
    // ==============================

    decoder u_decoder (
        .instr       (instr),
        .reg_we      (reg_we),
        .alu_src_imm (alu_src_imm),
        .alu_op      (alu_op),
        .illegal     (illegal)
    );


    // ==============================
    // Immediate generator
    // ==============================

    imm_gen u_imm_gen (
        .instr (instr),
        .imm_i (imm_i)
    );


    // ==============================
    // Register File
    // ==============================

    assign rf_we = reg_we && (rd_addr != 5'd0);

    regfile u_regfile (
        .clk      (clk),
        .rst      (rst),

        .we       (rf_we),
        .rd_addr  (rd_addr),
        .rd_data  (alu_result),

        .rs1_addr (rs1_addr),
        .rs2_addr (rs2_addr),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data)
    );


    // ==============================
    // ALU input mux
    // ==============================

    assign alu_b =
        alu_src_imm ? imm_i : rs2_data;


    // ==============================
    // ALU
    // ==============================

    alu u_alu (
        .a      (rs1_data),
        .b      (alu_b),
        .op     (alu_op),
        .res    (alu_result)
    );


    // ==============================
    // Debug
    // ==============================

    assign dbg_reg_we   = rf_we;
    assign dbg_rd_addr  = rd_addr;
    assign dbg_rd_data  = alu_result;
    assign dbg_rs1_data = rs1_data;
    assign dbg_imm      = imm_i;
    assign dbg_illegal  = illegal;

endmodule
