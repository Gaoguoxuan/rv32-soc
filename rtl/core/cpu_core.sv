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
    output logic [3:0]  mem_wstrb


    // Debug signals
    // output logic        dbg_reg_we,
    // output logic [4:0]  dbg_rd_addr,
    // output logic [31:0] dbg_rd_data,

    // output logic [31:0] dbg_rs1_data,
    // output logic [31:0] dbg_rs2_data,

    // output logic [31:0] dbg_imm,

    // output logic        dbg_branch_taken,
    // output logic        dbg_illegal
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

    localparam logic [2:0] IMM_I = 3'b000;
    localparam logic [2:0] IMM_S = 3'b001;
    localparam logic [2:0] IMM_B = 3'b010;
    localparam logic [2:0] IMM_U = 3'b011;
    localparam logic [2:0] IMM_J = 3'b100;

    logic [31:0] imm_i;
    logic [31:0] imm_s;
    logic [31:0] imm_b;
    logic [31:0] imm_u;
    logic [31:0] imm_j;

    logic [31:0] imm;

    logic [2:0] imm_sel;

    //============================
    // ALU
    //============================

    localparam logic [1:0] OP_A_RS1  = 2'b00;
    localparam logic [1:0] OP_A_PC   = 2'b01;
    localparam logic [1:0] OP_A_ZERO = 2'b10;

    logic [1:0] op_a_sel;
    logic       op_b_imm;

    logic [31:0] alu_a;
    logic [31:0] alu_b;
    logic [3:0]  alu_op;

    logic [31:0] alu_result;

    //============================
    // Memory / Writeback
    //============================

    //logic        mem_we_int;
    logic [1:0]  wb_sel;

    logic [31:0] writeback_data;

    logic [2:0]  load_type;
    logic [1:0]  store_type;

    logic [31:0] load_data;

    logic [31:0] lsu_wdata;
    logic [3:0]  lsu_wstrb;

    logic        lsu_misaligned;

    //============================
    // CSR signals
    //============================

    localparam logic [1:0] CSR_NONE = 2'b00;
    localparam logic [1:0] CSR_RW   = 2'b01;
    localparam logic [1:0] CSR_RS   = 2'b10;
    localparam logic [1:0] CSR_RC   = 2'b11;

    logic        csr_en;
    logic [1:0]  csr_cmd;
    logic        csr_use_imm;

    logic [11:0] csr_addr;

    logic        trap_enter;
    logic        mret_enter;

    logic [31:0] trap_pc;
    logic [31:0] trap_cause;
    logic [31:0] trap_vector;

    logic [31:0] trap_tval;
    logic [31:0] mtval;

    logic [31:0] csr_rdata;
    logic [31:0] csr_wdata;
    logic [31:0] csr_src;

    logic        csr_valid;
    logic        csr_writable;
    logic        csr_we;

    logic        csr_write_intent;
    logic        csr_access_illegal;
    logic        effective_illegal;

    logic [31:0] csr_zimm;

    logic [31:0] mstatus;
    logic [31:0] mie;
    logic [31:0] mtvec;
    logic [31:0] mscratch;
    logic [31:0] mepc;
    logic [31:0] mcause;
    logic [31:0] mip;

    assign csr_addr = instr[31:20];

    assign csr_zimm = {27'b0, instr[19:15]};

    assign csr_src = csr_use_imm
                   ? csr_zimm
                   : rs1_data;
                   
    //assign trap_enter = sys_ecall && !effective_illegal;
    assign trap_enter = effective_illegal || sys_ecall;
    assign mret_enter = sys_mret && !effective_illegal;

    assign trap_vector = mtvec & 32'hFFFF_FFFC;

    assign trap_pc = pc;

    //assign trap_cause = 32'd11;
    assign trap_cause = effective_illegal ? 32'd2 : 32'd11;

    assign trap_tval = !effective_illegal     ? 32'b0 : 
                        (instr[1:0] == 2'b11) ? instr : 
                                                {16'b0, instr[15:0]};

    csr_file u_csr_file (
        .clk          (clk),
        .rst          (rst),

        .csr_addr     (csr_addr),

        .trap_enter  (trap_enter),
        .trap_pc     (trap_pc),
        .trap_cause  (trap_cause),

        .mret_enter  (mret_enter),

        .trap_tval   (trap_tval),

        .mtval        (mtval),

        .csr_rdata    (csr_rdata),
        .csr_valid    (csr_valid),
        .csr_writable (csr_writable),

        .csr_we       (csr_we),
        .csr_wdata    (csr_wdata),

        .mstatus      (mstatus),
        .mie          (mie),
        .mtvec        (mtvec),
        .mscratch     (mscratch),
        .mepc         (mepc),
        .mcause       (mcause),
        .mip          (mip)
    );

    always_comb begin

        csr_wdata = csr_rdata;

        case (csr_cmd)

            CSR_RW:
                csr_wdata = csr_src;

            CSR_RS:
                csr_wdata = csr_rdata | csr_src;

            CSR_RC:
                csr_wdata = csr_rdata & ~csr_src;

            default:
                csr_wdata = csr_rdata;

        endcase

    end

    always_comb begin

        csr_write_intent = 1'b0;

        case (csr_cmd)

            CSR_RW:
                csr_write_intent = 1'b1;

            CSR_RS,
            CSR_RC:
                csr_write_intent = (instr[19:15] != 5'b0);

            default:
                csr_write_intent = 1'b0;

        endcase

    end

    // 非法 CSR 访问
    assign csr_access_illegal = csr_en && (!csr_valid || (csr_write_intent && !csr_writable));

    assign effective_illegal  = illegal || csr_access_illegal;

    assign csr_we = csr_en && csr_write_intent && !effective_illegal;


    //============================
    // Branch
    //============================

    logic [2:0] branch_type;
    logic       branch_taken;

    localparam logic [1:0] JUMP_NONE = 2'b00;
    localparam logic [1:0] JUMP_JAL  = 2'b01;
    localparam logic [1:0] JUMP_JALR = 2'b10;
    
    logic [1:0] jump;

    branch_unit u_branch_unit (
        .branch_type (branch_type),
        .a           (rs1_data),
        .b           (rs2_data),
        .taken       (branch_taken)
    );

    logic [31:0] next_pc;


    logic        illegal;

    //============================
    // Instruction fields
    //============================

    assign rd_addr  = instr[11:7];
    assign rs1_addr = instr[19:15];
    assign rs2_addr = instr[24:20];

    //============================
    // Decoder
    //============================

    logic       mem_load;
    logic       mem_store;

    logic       sys_ecall;
    logic       sys_mret;

    decoder u_decoder (
        .instr       (instr),

        .reg_we      (reg_we),

        .alu_op      (alu_op),

        .op_a_sel    (op_a_sel),
        .op_b_imm    (op_b_imm),

        .load_type  (load_type),
        .store_type (store_type),

        .imm_sel     (imm_sel),

        .mem_load    (mem_load),
        .mem_store   (mem_store),

        .wb_sel      (wb_sel),

        .branch_type (branch_type),
        .jump        (jump),

        .csr_en      (csr_en),
        .csr_cmd     (csr_cmd),
        .csr_use_imm (csr_use_imm),
        
        .sys_ecall   (sys_ecall),
        .sys_mret    (sys_mret),

        .illegal     (illegal)
    );

    

    // ==============================
    // Immediate generator
    // ==============================

    imm_gen u_imm_gen (
        .instr (instr),

        .imm_i (imm_i),
        .imm_s (imm_s),
        .imm_b (imm_b),
        .imm_u (imm_u),
        .imm_j (imm_j)
    );

    always_comb begin

        case (imm_sel)

            IMM_I:
                imm = imm_i;

            IMM_S:
                imm = imm_s;

            IMM_B:
                imm = imm_b;

            IMM_U:
                imm = imm_u;

            IMM_J:
                imm = imm_j;

            default:
                imm = 32'b0;

        endcase

    end

    // ==============================
    // Register File
    // ==============================

    assign rf_we = reg_we && !effective_illegal && !lsu_misaligned &&(rd_addr != 5'd0);

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

    always_comb begin

        case (op_a_sel)

            OP_A_RS1:
                alu_a = rs1_data;

            OP_A_PC:
                alu_a = pc;

            OP_A_ZERO:
                alu_a = 32'b0;

            default:
                alu_a = 32'b0;

        endcase

    end

    assign alu_b = op_b_imm ? imm : rs2_data;

    // ============================
    // ALU
    // ============================

    alu u_alu (
        .a      (alu_a),
        .b      (alu_b),
        .op     (alu_op),
        .res    (alu_result)
    );

    // ============================
    // LSU
    // ============================


    lsu u_lsu (
        .addr        (alu_result),

        .store_data  (rs2_data),

        .mem_rdata   (mem_rdata),

        .load_type   (load_type),
        .store_type  (store_type),

        .load_data   (load_data),

        .mem_wdata   (lsu_wdata),
        .mem_wstrb   (lsu_wstrb),

        .misaligned  (lsu_misaligned)
    );

    // ============================
    // Data Memory Interface
    // ============================

    // sw x3, 0(x0)
    // address = x0 + 0  ALU中来自rs1_data x0与立即数0相加后的结果作为address
    // x3作为rs2_data将写入adress寻址区域
    assign mem_addr = alu_result;

    assign mem_wdata = lsu_wdata;
    assign mem_wstrb = lsu_wstrb;

    assign mem_we = mem_store && !effective_illegal && !lsu_misaligned && (|lsu_wstrb);

    // ============================
    // Writeback MUX
    // ============================

    localparam logic [1:0] WB_ALU = 2'b00;
    localparam logic [1:0] WB_MEM = 2'b01;
    localparam logic [1:0] WB_PC4 = 2'b10;
    localparam logic [1:0] WB_CSR = 2'b11;

    always_comb begin

        case (wb_sel)

            WB_ALU:
                writeback_data = alu_result;

            WB_MEM:
                writeback_data = load_data;

            WB_PC4:
                writeback_data = pc + 32'd4;
            
            WB_CSR:
                writeback_data = csr_rdata;

            default:
                writeback_data = 32'b0;

        endcase

    end


    //assign branch_taken = (|branch_type) && (rs1_data == rs2_data); 

    //assign next_pc = branch_taken ? (pc + imm_b) : (pc + 32'd4);

    // ============================
    // PC
    // ============================

    always_comb begin

        next_pc = pc + 32'd4;

        if (trap_enter) begin

            next_pc = trap_vector;

        end

        else if (mret_enter) begin

            next_pc = mepc;

        end

        else if (jump == JUMP_JAL) begin

            next_pc = pc + imm_j;

        end

        else if (jump == JUMP_JALR) begin

            next_pc = (rs1_data + imm_i) & 32'hFFFF_FFFE;

        end

        else if (branch_taken) begin

            next_pc = pc + imm_b;

        end

    end

    pc u_pc (
        .clk     (clk),
        .rst     (rst),
        .next_pc (next_pc),
        .pc      (pc)
    );



    // ==============================
    // Debug
    // ==============================

    // assign dbg_reg_we       = rf_we;
    // assign dbg_rd_addr      = rd_addr;
    // assign dbg_rd_data      = writeback_data;

    // assign dbg_rs1_data     = rs1_data;
    // assign dbg_rs2_data     = rs2_data;

    // assign dbg_imm          = imm;

    // assign dbg_branch_taken = branch_taken;

    // assign dbg_illegal      = illegal;

endmodule
