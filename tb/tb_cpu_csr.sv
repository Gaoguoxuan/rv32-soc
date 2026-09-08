module tb_cpu_csr;

    logic clk;
    logic rst;

    logic [31:0]    instr;
    logic [31:0]    pc;
    logic [31:0]    mem_addr;
    logic [31:0]    mem_wdata;
    logic [31:0]    mem_rdata;
    logic           mem_we;
    logic [3:0]     mem_wstrb;

    logic [31:0]    imem [0:63];

    integer errors = 0;
    integer i;

    localparam logic [31:0] NOP = 32'h00000013;

    cpu_core dut (
    .clk            (clk),
    .rst            (rst),

    .instr          (instr),
    .pc             (pc),

    .mem_addr       (mem_addr),
    .mem_wdata      (mem_wdata),
    .mem_rdata      (mem_rdata),
    .mem_we         (mem_we),
    .mem_wstrb      (mem_wstrb)
    );

    initial begin

        clk = 1'b0;

        forever #5 clk = ~clk;

    end

    always_comb begin

        if (pc < 32'd256)
            instr = imem[pc[7:2]];
        else
            instr = NOP;

    end

    always_comb begin
        mem_rdata = 32'b0;
    end

    // ============================================================
    // CSR instruction encoder
    //
    // CSR instruction format:
    //
    // 31            20 19    15 14  12 11    7 6       0
    // ┌───────────────┬────────┬──────┬────────┬─────────┐
    // │  CSR address  │rs1/zimm│funct3│   rd   │ 1110011 │
    // └───────────────┴────────┴──────┴────────┴─────────┘
    //
    // ============================================================

    function automatic logic [31:0] enc_csr (
        input logic [11:0] csr,
        input logic [4:0]  rs1_zimm,
        input logic [2:0]  funct3,
        input logic [4:0]  rd
    );

        enc_csr = {
            csr,
            rs1_zimm,
            funct3,
            rd,
            7'b1110011
        };

endfunction

    // ============================================================
    // Register checker
    // ============================================================

    task automatic check_reg (
        input integer      reg_num,
        input logic [31:0] expected,
        input string       name
    );

        logic [31:0] actual;

        begin

            actual = dut.u_regfile.regs[reg_num];

            if (actual === expected) begin

                $display(
                    "[PASS] %-16s x%0d = %08x",
                    name,
                    reg_num,
                    actual
                );

            end

            else begin

                $display(
                    "[FAIL] %-16s x%0d = %08x expected=%08x",
                    name,
                    reg_num,
                    actual,
                    expected
                );

                errors++;

            end

        end

    endtask

    // ============================================================
    // Main test
    // ============================================================

    initial begin

        rst = 1'b1;


        // --------------------------------------------------------
        // Initialize instruction memory with NOP
        // --------------------------------------------------------

        for (i = 0; i < 64; i = i + 1)
            imem[i] = NOP;


        // ========================================================
        // Program
        // ========================================================


        // --------------------------------------------------------
        // 0x00
        //
        // addi x1, x0, 0x55
        //
        // x1 = 0x55
        // --------------------------------------------------------

        imem[0] = 32'h05500093;


        // --------------------------------------------------------
        // 0x04
        //
        // CSRRW x2, mscratch, x1
        //
        // Before:
        //
        // mscratch = 0
        // x1       = 0x55
        //
        // After:
        //
        // x2       = 0
        // mscratch = 0x55
        //
        // funct3 = 001
        // --------------------------------------------------------

        imem[1] = enc_csr(
            12'h340,       // mscratch
            5'd1,          // rs1 = x1
            3'b001,        // CSRRW
            5'd2           // rd = x2
        );


        // --------------------------------------------------------
        // 0x08
        //
        // addi x3, x0, 0x0F
        // --------------------------------------------------------

        imem[2] = 32'h00F00193;


        // --------------------------------------------------------
        // 0x0C
        //
        // CSRRS x4, mscratch, x3
        //
        // Before:
        //
        // mscratch = 0x55
        // x3       = 0x0F
        //
        // After:
        //
        // x4       = 0x55
        //
        // mscratch =
        //
        //     0x55 | 0x0F
        //   = 0x5F
        //
        // funct3 = 010
        // --------------------------------------------------------

        imem[3] = enc_csr(
            12'h340,
            5'd3,
            3'b010,
            5'd4
        );


        // --------------------------------------------------------
        // 0x10
        //
        // addi x5, x0, 0x0C
        // --------------------------------------------------------

        imem[4] = 32'h00C00293;


        // --------------------------------------------------------
        // 0x14
        //
        // CSRRC x6, mscratch, x5
        //
        // Before:
        //
        // mscratch = 0x5F
        // x5       = 0x0C
        //
        // After:
        //
        // x6 = 0x5F
        //
        // mscratch =
        //
        //     0x5F & ~0x0C
        //   = 0x53
        //
        // funct3 = 011
        // --------------------------------------------------------

        imem[5] = enc_csr(
            12'h340,
            5'd5,
            3'b011,
            5'd6
        );


        // --------------------------------------------------------
        // 0x18
        //
        // CSRRWI x7, mscratch, 3
        //
        // Before:
        //
        // mscratch = 0x53
        //
        // After:
        //
        // x7       = 0x53
        // mscratch = 3
        //
        // funct3 = 101
        // --------------------------------------------------------

        imem[6] = enc_csr(
            12'h340,
            5'd3,          // zimm = 3
            3'b101,
            5'd7
        );


        // --------------------------------------------------------
        // 0x1C
        //
        // CSRRSI x8, mscratch, 4
        //
        // Before:
        //
        // mscratch = 3
        //
        // After:
        //
        // x8 = 3
        //
        // mscratch =
        //
        //     3 | 4
        //   = 7
        //
        // funct3 = 110
        // --------------------------------------------------------

        imem[7] = enc_csr(
            12'h340,
            5'd4,          // zimm = 4
            3'b110,
            5'd8
        );


        // --------------------------------------------------------
        // 0x20
        //
        // CSRRCI x9, mscratch, 1
        //
        // Before:
        //
        // mscratch = 7
        //
        // After:
        //
        // x9 = 7
        //
        // mscratch =
        //
        //     7 & ~1
        //   = 6
        //
        // funct3 = 111
        // --------------------------------------------------------

        imem[8] = enc_csr(
            12'h340,
            5'd1,          // zimm = 1
            3'b111,
            5'd9
        );


        // --------------------------------------------------------
        // 0x24
        //
        // CSRRS x10, mscratch, x0
        //
        // 这是一个很重要的特殊情况。
        //
        // rs1 = x0
        //
        // 意味着：
        //
        // 只读，不写 CSR。
        //
        // Before:
        //
        // mscratch = 6
        //
        // After:
        //
        // x10      = 6
        // mscratch = 6
        //
        // --------------------------------------------------------

        imem[9] = enc_csr(
            12'h340,
            5'd0,
            3'b010,
            5'd10
        );


        // --------------------------------------------------------
        // 0x28
        //
        // CSRRWI x0, mscratch, 9
        //
        // 又一个非常重要的特殊情况：
        //
        // rd = x0
        //
        // 不保存 CSR 旧值，
        // 但是 CSR 写操作仍然必须执行！
        //
        // After:
        //
        // mscratch = 9
        //
        // --------------------------------------------------------

        imem[10] = enc_csr(
            12'h340,
            5'd9,          // zimm = 9
            3'b101,
            5'd0           // rd = x0
        );


        // --------------------------------------------------------
        // 0x2C
        //
        // CSRRSI x11, mscratch, 0
        //
        // zimm = 0
        //
        // 意味着：
        //
        // 只读 CSR，不写。
        //
        // x11      = 9
        // mscratch = 9
        //
        // --------------------------------------------------------

        imem[11] = enc_csr(
            12'h340,
            5'd0,
            3'b110,
            5'd11
        );


        // ========================================================
        // Waveform
        // ========================================================

        $dumpfile(
            "build/cpu_csr.vcd"
        );

        $dumpvars(
            0,
            tb_cpu_csr
        );


        // ========================================================
        // Reset
        // ========================================================

        repeat (2)
            @(posedge clk);


        @(negedge clk);

        rst = 1'b0;


        // ========================================================
        // Execute
        //
        // 一共 12 条有效指令。
        // 多给几个周期跑到后面的 NOP。
        // ========================================================

        repeat (15)
            @(posedge clk);


        #1;


        // ========================================================
        // Results
        // ========================================================

        $display("");
        $display("================================");
        $display("       ZICSR REGRESSION");
        $display("================================");


        // CSRRW
        check_reg(
            2,
            32'h00000000,
            "CSRRW old value"
        );


        // CSRRS
        check_reg(
            4,
            32'h00000055,
            "CSRRS old value"
        );


        // CSRRC
        check_reg(
            6,
            32'h0000005F,
            "CSRRC old value"
        );


        // CSRRWI
        check_reg(
            7,
            32'h00000053,
            "CSRRWI old value"
        );


        // CSRRSI
        check_reg(
            8,
            32'h00000003,
            "CSRRSI old value"
        );


        // CSRRCI
        check_reg(
            9,
            32'h00000007,
            "CSRRCI old value"
        );


        // CSRRS x0 source:
        //
        // pure read
        check_reg(
            10,
            32'h00000006,
            "CSRRS read-only"
        );


        // CSRRSI zimm=0:
        //
        // pure read
        check_reg(
            11,
            32'h00000009,
            "CSRRSI read-only"
        );


        // x0 must still be zero
        check_reg(
            0,
            32'h00000000,
            "x0 protection"
        );


        // Final CSR value
        if (
            dut.u_csr_file.mscratch
            === 32'h00000009
        ) begin

            $display(
                "[PASS] final mscratch = %08x",
                dut.u_csr_file.mscratch
            );

        end

        else begin

            $display(
                "[FAIL] final mscratch = %08x expected=00000009",
                dut.u_csr_file.mscratch
            );

            errors++;

        end


        // ========================================================
        // Summary
        // ========================================================

        if (errors == 0) begin

            $display("");
            $display("==============================");
            $display("       M7.2 ZICSR PASS");
            $display("==============================");

        end

        else begin

            $display("");
            $display("==============================");
            $display("       M7.2 ZICSR FAILED");
            $display("==============================");

            $fatal(
                1,
                "%0d test(s) failed",
                errors
            );

        end


        $finish;

    end



endmodule
