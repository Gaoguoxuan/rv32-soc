module csr_file (
    input  logic        clk,
    input  logic        rst,

    input  logic [11:0] csr_addr,

    input logic        trap_enter,
    input logic [31:0] trap_pc,
    input logic [31:0] trap_cause,

    input logic        mret_enter,

    output logic [31:0] csr_rdata,
    output logic        csr_valid,
    output logic        csr_writable,

    input  logic        csr_we,
    input  logic [31:0] csr_wdata,

    output logic [31:0] mstatus,
    output logic [31:0] mie,
    output logic [31:0] mtvec,
    output logic [31:0] mscratch,
    output logic [31:0] mepc,
    output logic [31:0] mcause,
    output logic [31:0] mip
);

    // ============================================================
    // CSR addresses
    // ============================================================

    localparam logic [11:0] CSR_MSTATUS  = 12'h300;
    localparam logic [11:0] CSR_MIE      = 12'h304;
    localparam logic [11:0] CSR_MTVEC    = 12'h305;

    localparam logic [11:0] CSR_MSCRATCH = 12'h340;
    localparam logic [11:0] CSR_MEPC     = 12'h341;
    localparam logic [11:0] CSR_MCAUSE   = 12'h342;
    localparam logic [11:0] CSR_MIP      = 12'h344;


    // ============================================================
    // CSR read
    // ============================================================

    always_comb begin

        csr_rdata    = 32'b0;
        csr_valid    = 1'b1;
        csr_writable = 1'b1;

        case (csr_addr)

            CSR_MSTATUS:
                csr_rdata = mstatus;

            CSR_MIE:
                csr_rdata = mie;

            CSR_MTVEC:
                csr_rdata = mtvec;

            CSR_MSCRATCH:
                csr_rdata = mscratch;

            CSR_MEPC:
                csr_rdata = mepc;

            CSR_MCAUSE:
                csr_rdata = mcause;

            CSR_MIP: begin
                csr_rdata    = mip;

                // 后面由中断硬件维护。
                // M7 暂时把它作为只读 CSR。
                csr_writable = 1'b0;
            end

            default: begin
                csr_rdata    = 32'b0;
                csr_valid    = 1'b0;
                csr_writable = 1'b0;
            end

        endcase

    end


    // ============================================================
    // CSR write
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            mstatus  <= 32'b0;
            mie      <= 32'b0;
            mtvec    <= 32'b0;

            mscratch <= 32'b0;
            mepc     <= 32'b0;
            mcause   <= 32'b0;

            mip      <= 32'b0;

        end

        // ============================================================
        // Trap entry
        // ============================================================

        else if (trap_enter) begin

            mepc   <= trap_pc;
            mcause <= trap_cause;

            // mstatus.MPIE <- mstatus.MIE
            mstatus[7] <= mstatus[3];

            // mstatus.MIE <- 0
            mstatus[3] <= 1'b0;

            // MPP <- Machine mode = 2'b11
            mstatus[12:11] <= 2'b11;

        end

        // ============================================================
        // MRET
        // ============================================================

        else if (mret_enter) begin

            // MIE <- MPIE
            mstatus[3] <= mstatus[7];

            // MPIE <- 1
            mstatus[7] <= 1'b1;

            // MPP <- lowest supported privilege.
            //
            // 我们现在只有 M-mode，没有 U-mode，
            // M8 阶段先继续保持 Machine。
            mstatus[12:11] <= 2'b11;

        end

        else if (
            csr_we &&
            csr_valid &&
            csr_writable
        ) begin

            case (csr_addr)

                CSR_MSTATUS:
                    mstatus <= csr_wdata;

                CSR_MIE:
                    mie <= csr_wdata;

                CSR_MTVEC:
                    mtvec <= csr_wdata;

                CSR_MSCRATCH:
                    mscratch <= csr_wdata;

                CSR_MEPC:
                    mepc <= csr_wdata;

                CSR_MCAUSE:
                    mcause <= csr_wdata;

                default: begin
                end

            endcase

        end

    end

endmodule
