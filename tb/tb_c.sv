module tb_c;

    logic clk;
    logic rst;

    logic [31:0] pc;
    logic [31:0] instr;

    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;

    logic        mem_we;
    logic [3:0]  mem_wstrb;


    logic [31:0] imem [0:1023];
    logic [31:0] dmem [0:255];



    // ============================================================
    // DUT
    // ============================================================

    cpu_core dut (
        .clk       (clk),
        .rst       (rst),

        .timer_irq (1'b0),

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

        forever #5
            clk = ~clk;

    end


    // ============================================================
    // Instruction memory
    // ============================================================

    always_comb begin

        if (pc < 32'd1024)
            instr = imem[pc[11:2]];
        else
            instr = 32'h00000013;

    end


    // ============================================================
    // Data memory read
    // ============================================================

    always_comb begin

        if (mem_addr < 32'h00000400)
            mem_rdata = dmem[mem_addr[9:2]];
        else
            mem_rdata = 32'b0;

    end


    // ============================================================
    // Data memory write
    // ============================================================

    always_ff @(posedge clk) begin

        if (
            !rst &&
            mem_we &&
            mem_addr < 32'h00000400
        ) begin

            if (mem_wstrb[0])
                dmem[mem_addr[9:2]][7:0]
                    <= mem_wdata[7:0];

            if (mem_wstrb[1])
                dmem[mem_addr[9:2]][15:8]
                    <= mem_wdata[15:8];

            if (mem_wstrb[2])
                dmem[mem_addr[9:2]][23:16]
                    <= mem_wdata[23:16];

            if (mem_wstrb[3])
                dmem[mem_addr[9:2]][31:24]
                    <= mem_wdata[31:24];

        end

    end


    // ============================================================
    // Test
    // ============================================================

    integer i;

    initial begin

        rst = 1'b1;

        for (i = 0; i < 1024; i = i + 1)
            imem[i] = 32'h00000013;

        for (i = 0; i < 256; i = i + 1)
            dmem[i] = 32'b0;

        $readmemh(
            "build/c/c_smoke.hex",
            imem
        );

        $dumpfile(
            "build/c/c_smoke.vcd"
        );

        $dumpvars(
            0,
            tb_c
        );


        repeat (2)
            @(posedge clk);

        @(negedge clk);

        rst = 1'b0;


        // GCC generated code is longer than our hand-written ASM.
        repeat (150)
            @(posedge clk);

        #1;


        $display("");
        $display("==============================");
        $display("         C PROGRAM TEST");
        $display("==============================");

        $display(
            "a0/x10 = %08x",
            dut.u_regfile.regs[10]
        );

        $display(
            "sp/x2  = %08x",
            dut.u_regfile.regs[2]
        );

        $display(
            "ra/x1  = %08x",
            dut.u_regfile.regs[1]
        );

        $display(
            "x31    = %08x",
            dut.u_regfile.regs[31]
        );


        if (
            dut.u_regfile.regs[10] === 32'd42 &&
            dut.u_regfile.regs[31] === 32'd1
        ) begin

            $display("");
            $display("==============================");
            $display("       C PROGRAM PASS");
            $display("==============================");

        end

        else begin

            $display("");
            $display("==============================");
            $display("       C PROGRAM FAILED");
            $display("==============================");

            $fatal(
                1,
                "C program failed"
            );

        end


        $finish;

    end


endmodule
