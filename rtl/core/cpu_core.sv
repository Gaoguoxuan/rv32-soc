module cpu_core (
    input  logic        clk,
    input  logic        rst,

    // Instruction interface
    input  logic [31:0] instr,
    output logic [31:0] pc,

    // Data mamory interface
    output logic [31:0] mem_addr,
    output logic [31:0] mem_wdata,
    input  logic [31:0] mem_rdata,
    output logic        mem_we,

    // Debug signals
    output logic        dbg_reg_we,
    output logic [4:0]  dbg_rd_addr,
    output logic [31:0] dbg_rd_data,

    output logic [31:0] dbg_rs1_data,
    output logic [31:0] dbg_rs2_data,

    output logic [31:0] dbg_imm,

    output logic        dbg_branch_taken,
    output logic        dbg_illegal
);

    //============================
    // Instruction fields
    //============================

    logic [4:0] rs1_addr;
    logic [4:0] rs2_addr;
    logic [4:0] rd_addr;

    //============================
    // Register fields
    //============================

    logic [31:0] rs1_data;
    logic [31:0] rs2_data;

    logic        reg_we;
    logic        rf_we;

    //============================
    // Immediate
    //============================

    logic [31:0] imm_i;
    logic [31:0] imm_s;
    logic [31:0] imm_b;
    logic [31:0] imm;

    logic [1:0]  imm_sel;

    //============================
    // ALU
    //============================

    logic        alu_src_imm;
    logic [3:0]  alu_op;

    logic [31:0] alu_b;
    logic [31:0] alu_result;

    //============================
    // Memory / Writeback
    //============================

    logic        mem_we_int;
    logic        wb_sel_mem;

    logic [31:0] writeback_data;

    //============================
    // Branch
    //============================

    logic        branch_beq;
    logic        branch_taken;

    logic [31:0] next_pc;


    logic        illegal;

    localparam logic [1:0] IMM_I = 2'b00;
    localparam logic [1:0] IMM_S = 2'b01;
    localparam logic [1:0] IMM_B = 2'b10;

    //============================
    // Instruction fields
    //============================

    assign rd_addr  = instr[11:7];
    assign rs1_addr = instr[19:15];
    assign rs2_addr = instr[24:20];

    //============================
    // Decoder
    //============================

    decoder u_decoder (
        .instr       (instr),

        .reg_we      (reg_we),
        .alu_src_imm (alu_src_imm),
        .alu_op      (alu_op),

        .imm_sel     (imm_sel),

        .mem_we      (mem_we_int),
        .wb_sel_mem  (wb_sel_mem),

        .branch_beq  (branch_beq),

        .illegal     (illegal)
    );

    // ==============================
    // Immediate generator
    // ==============================

    imm_gen u_imm_gen (
        .instr (instr),

        .imm_i (imm_i),
        .imm_s (imm_s),
        .imm_b (imm_b)
    );

    always_comb begin
        
        case (imm_sel)

            IMM_I:
                imm = imm_i;

            IMM_S:
                imm = imm_s;

            IMM_B:
                imm = imm_b;

            default:
                imm = 32'b0;

        endcase

    end

    // ==============================
    // Register File
    // ==============================

    assign rf_we = reg_we && !illegal && (rd_addr != 5'd0);

    regfile u_regfile (
        .clk      (clk),
        .rst      (rst),

        .we       (rf_we),
        .rd_addr  (rd_addr),
        .rd_data  (writeback_data),

        .rs1_addr (rs1_addr),
        .rs2_addr (rs2_addr),

        .rs1_data (rs1_data),
        .rs2_data (rs2_data)
    );

    // ==============================
    // ALU input mux
    // ==============================

    assign alu_b = alu_src_imm ? imm_i : rs2_data;

    // ============================
    // ALU
    // ============================

    alu u_alu (
        .a      (rs1_data),
        .b      (alu_b),
        .op     (alu_op),
        .res    (alu_result)
    );

    // ============================
    // Data Memory Interface
    // ============================

    // sw x3, 0(x0)
    // address = x0 + 0  ALU中来自rs1_data x0与立即数0相加后的结果作为address
    // x3作为rs2_data将写入adress寻址区域
    assign mem_addr = alu_result;

    assign mem_wdata = rs2_data;

    assign mem_we = mem_we_int && !illegal;

    // ============================
    // Writeback MUX
    // ============================

    // lw x5, 0(x0)
    // alu_result作为address寻址内存
    // 根据wb_sel_mem == 1将内存中对应区域的data取出写回reg x5
    assign writeback_data = wb_sel_mem ? mem_rdata : alu_result;

    // ============================
    // Branch
    // ============================

    assign branch_taken = branch_beq && (rs1_data == rs2_data); 

    assign next_pc = branch_taken ? (pc + imm_b) : (pc + 32'd4);

    // ============================
    // PC
    // ============================

    pc u_pc (
        .clk     (clk),
        .rst     (rst),
        .next_pc (next_pc),
        .pc      (pc)
    );



    // ==============================
    // Debug
    // ==============================

    assign dbg_reg_we       = rf_we;
    assign dbg_rd_addr      = rd_addr;
    assign dbg_rd_data      = writeback_data;

    assign dbg_rs1_data     = rs1_data;
    assign dbg_rs2_data     = rs2_data;

    assign dbg_imm          = imm;

    assign dbg_branch_taken = branch_taken;

    assign dbg_illegal      = illegal;

endmodule
