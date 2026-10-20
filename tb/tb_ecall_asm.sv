module tb_ecall_asm;

    logic clk;
    logic rst;

    logic [31:0] pc;
    logic [31:0] instr;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic        mem_we;
    logic [3:0]  mem_wstrb;

    logic [31:0] imem [0:255];

    localparam logic [31:0] NOP   = 32'h0000_0013;
    localparam logic [31:0] ECALL = 32'h0000_0073;
    localparam logic [31:0] MRET  = 32'h3020_0073;

    integer trap_count = 0;
    integer mret_count = 0;

    logic [31:0] saved_pc;
    logic [31:0] saved_mstatus;
    logic [31:0] saved_mtvec;
    logic [31:0] saved_mepc;
    logic [31:0] saved_mcause;
    logic [31:0] saved_mtval;

    cpu_core dut (
        .clk       (clk),
        .rst       (rst),
        .timer_irq (1'b0),
        .instr     (instr),
        .pc        (pc),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_rdata (32'b0),
        .mem_we    (mem_we),
        .mem_wstrb (mem_wstrb)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_comb begin
        if (pc < 32'd1024)
            instr = imem[pc[9:2]];
        else
            instr = NOP;
    end

    task automatic check_value(
        input string       name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        if (actual !== expected)
            $fatal(1, "%s: got=%08x expected=%08x", name, actual, expected);

        $display("[PASS] %-24s = %08x", name, actual);
    endtask

    // At the edge, pc/instr still describe the instruction being executed.
    // Sample its state before the nonblocking register updates, then check
    // the resulting state after #1. Do not sample instr after it has changed.
    always @(posedge clk) begin
        if (!rst) begin
            if (instr == ECALL) begin
                saved_pc      = pc;
                saved_mstatus = dut.mstatus;
                saved_mtvec   = dut.mtvec;
                check_value("ECALL prior mtval", dut.mtval,
                            trap_count == 0 ? 32'h89ab_cdef : 32'h1357_9bdf);
                trap_count++;

                check_value("ECALL normal writes",
                            {29'b0, dut.rf_we, dut.csr_we, mem_we}, 32'b0);

                #1;

                $display("ECALL #%0d: old MIE=%0d", trap_count, saved_mstatus[3]);
                check_value("ECALL target PC", pc,
                            {saved_mtvec[31:2], 2'b00});
                check_value("ECALL mepc", dut.mepc, saved_pc);
                check_value("ECALL mcause", dut.mcause, 32'd11);
                check_value("ECALL clears mtval", dut.mtval, 32'b0);
                check_value("ECALL MIE", {31'b0, dut.mstatus[3]}, 32'd0);
                check_value("ECALL MPIE", {31'b0, dut.mstatus[7]},
                            {31'b0, saved_mstatus[3]});
                check_value("ECALL MPP", {30'b0, dut.mstatus[12:11]}, 32'd3);
            end
            else if (instr == MRET) begin
                saved_mstatus = dut.mstatus;
                saved_mepc    = dut.mepc;
                saved_mcause  = dut.mcause;
                saved_mtval   = dut.mtval;
                mret_count++;

                check_value("MRET normal writes",
                            {29'b0, dut.rf_we, dut.csr_we, mem_we}, 32'b0);

                #1;

                $display("MRET #%0d: return to %08x", mret_count, saved_mepc);
                check_value("MRET target PC", pc, saved_mepc);
                check_value("MRET MIE", {31'b0, dut.mstatus[3]},
                            {31'b0, saved_mstatus[7]});
                check_value("MRET MPIE", {31'b0, dut.mstatus[7]}, 32'd1);
                check_value("MRET MPP (M-only)",
                            {30'b0, dut.mstatus[12:11]}, 32'd3);
                check_value("MRET preserves mepc", dut.mepc, saved_mepc);
                check_value("MRET preserves mcause", dut.mcause, saved_mcause);
                check_value("MRET preserves mtval", dut.mtval, saved_mtval);
            end
        end
    end

    initial begin
        rst = 1'b1;

        for (integer i = 0; i < 256; i++)
            imem[i] = NOP;

        $readmemh("build/ecall/ecall.hex", imem);
        $dumpfile("build/ecall/ecall.vcd");
        $dumpvars(0, tb_ecall_asm);

        repeat (2) @(posedge clk);
        #1;
        check_value("mtval reset", dut.mtval, 32'b0);
        @(negedge clk);
        rst = 1'b0;

        // Wait until after both the CPU updates and the #1 monitor checks.
        for (integer cycle = 0; cycle < 500; cycle++) begin
            @(posedge clk);
            #2;

            if (pc[1:0] !== 2'b00 || pc >= 32'd1024)
                $fatal(1, "Invalid instruction address: pc=%08x", pc);

            if (dut.u_regfile.regs[31] === 32'hffff_ffff)
                $fatal(1, "Assembly self-check failed: pc=%08x mepc=%08x mcause=%08x mstatus=%08x",
                       pc, dut.mepc, dut.mcause, dut.mstatus);

            if (dut.u_regfile.regs[31] === 32'd1) begin
                check_value("ECALL count", trap_count, 32'd2);
                check_value("MRET count", mret_count, 32'd2);
                check_value("Handler entries (s0)", dut.u_regfile.regs[8], 32'd2);
                check_value("Successful returns (s1)", dut.u_regfile.regs[9], 32'd2);
                $display("==============================");
                $display("     M8.1 ECALL/MRET PASS");
                $display("  M8.3 MTVAL ECALL CHECKS PASS");
                $display("==============================");
                $finish;
            end
        end

        $fatal(1, "ECALL/MRET timeout: pc=%08x x31=%08x traps=%0d returns=%0d",
               pc, dut.u_regfile.regs[31], trap_count, mret_count);
    end

endmodule
