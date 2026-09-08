module tb_zicsr_asm;

    logic clk;
    logic rst;

    logic [31:0] pc;
    logic [31:0] instr;

    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;

    logic        mem_we;
    logic [3:0]  mem_wstrb;


    logic [31:0] imem [0:255];

    integer i;


    localparam logic [31:0] NOP = 32'h00000013;


    // ============================================================
    // DUT
    // ============================================================

    cpu_core dut (
        .clk       (clk),
        .rst       (rst),

        .instr     (instr),
        .pc        (pc),

        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_rdata (mem_rdata),

        .mem_we    (mem_we),
        .mem_wstrb (mem_wstrb)
    );


    // ============================================================
    // Clock
    // ============================================================

    initial begin

        clk = 1'b0;

        forever #5 clk = ~clk;

    end


    // ============================================================
    // Instruction memory
    // ============================================================

    always_comb begin

        if (pc < 32'd1024)
            instr = imem[pc[9:2]];

        else
            instr = NOP;

    end


    // CSR test doesn't use data RAM
    always_comb begin
        mem_rdata = 32'b0;
    end


    // ============================================================
    // Test
    // ============================================================

    initial begin

        rst = 1'b1;


        for (i = 0; i < 256; i = i + 1)
            imem[i] = NOP;


        $readmemh(
            "build/zicsr/zicsr.hex",
            imem
        );


        $dumpfile(
            "build/zicsr/zicsr.vcd"
        );

        $dumpvars(
            0,
            tb_zicsr_asm
        );


        repeat (2)
            @(posedge clk);


        @(negedge clk);

        rst = 1'b0;


        // Give software enough time to reach pass/fail loop
        repeat (100)
            @(posedge clk);


        #1;


        $display("");
        $display("==============================");
        $display("       GNU ZICSR TEST");
        $display("==============================");

        $display(
            "x31      = %08x",
            dut.u_regfile.regs[31]
        );

        $display(
            "mscratch = %08x",
            dut.u_csr_file.mscratch
        );


        if (
            dut.u_regfile.regs[31]
                === 32'h00000001
            &&
            dut.u_csr_file.mscratch
                === 32'h00000009
        ) begin

            $display("");
            $display("==============================");
            $display("      GNU ZICSR TEST PASS");
            $display("==============================");

        end

        else begin

            $display("");
            $display("==============================");
            $display("      GNU ZICSR TEST FAIL");
            $display("==============================");

            $fatal(
                1,
                "GNU Zicsr program failed"
            );

        end


        $finish;

    end

endmodule