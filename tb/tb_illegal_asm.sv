module tb_illegal_asm;

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
    logic [31:0] dmem [0:15];

    localparam logic [31:0] NOP              = 32'h0000_0013;
    localparam logic [31:0] BAD_OPCODE       = 32'h0000_0000;
    localparam logic [31:0] BAD_SHORT        = 32'hdead_0002;
    localparam logic [31:0] UNSUPPORTED_MUL  = 32'h036a_8a33;
    localparam logic [31:0] BAD_LOAD         = 32'h0000_3a03;
    localparam logic [31:0] BAD_STORE        = 32'h0170_3023;
    localparam logic [31:0] BAD_CSR_READ     = 32'h7c00_2a73;
    localparam logic [31:0] BAD_CSR_WRITE    = 32'h7c0b_9a73;
    localparam logic [31:0] BAD_CSR_WRITE_X0 = 32'h7c0b_9073;
    localparam logic [31:0] ECALL            = 32'h0000_0073;
    localparam logic [31:0] MRET             = 32'h3020_0073;

    integer illegal_count = 0;
    integer ecall_count = 0;
    integer mret_count = 0;
    integer ram_write_count = 0;

    logic        sampled_trap;
    logic [31:0] saved_instr;
    logic [31:0] saved_pc;
    logic [31:0] saved_mstatus;
    logic [31:0] saved_mepc;
    logic [31:0] saved_mcause;
    logic [31:0] saved_mtvec;
    logic [31:0] saved_mie;
    logic [31:0] saved_mip;
    logic [31:0] saved_mscratch;
    logic [31:0] saved_mtval;
    logic [31:0] saved_regs [0:31];
    logic [31:0] saved_ram [0:15];

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

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_comb begin
        instr = (pc < 32'd1024) ? imem[pc[9:2]] : NOP;
        mem_rdata = (mem_addr < 32'd64) ? dmem[mem_addr[5:2]] : 32'b0;
    end

    // A real writable RAM model, so an accidental store cannot be hidden
    // by tying off the memory interface. The program makes one legal store.
    always_ff @(posedge clk) begin
        if (!rst && mem_we) begin
            if (mem_addr >= 32'd64 || mem_addr[1:0] != 2'b00)
                $fatal(1, "Unexpected RAM write address: %08x", mem_addr);

            for (integer lane = 0; lane < 4; lane++) begin
                if (mem_wstrb[lane])
                    dmem[mem_addr[5:2]][lane*8 +: 8] <= mem_wdata[lane*8 +: 8];
            end
            ram_write_count <= ram_write_count + 1;
        end
    end

    task automatic check_value(
        input string       name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        if (actual !== expected)
            $fatal(1, "%s: got=%08x expected=%08x", name, actual, expected);
    endtask

    initial begin
        rst = 1'b1;
        for (integer i = 0; i < 256; i++)
            imem[i] = NOP;
        for (integer i = 0; i < 16; i++)
            dmem[i] = 32'b0;

        $readmemh("build/illegal/illegal.hex", imem);
        $dumpfile("build/illegal/illegal.vcd");
        $dumpvars(0, tb_illegal_asm);

        repeat (2) @(posedge clk);
        #1;
        check_value("mtval reset", dut.mtval, 32'b0);
        @(negedge clk);
        rst = 1'b0;

        for (integer cycle = 0; cycle < 500; cycle++) begin
            // Observe a settled instruction before the active clock edge.
            saved_instr   = instr;
            saved_pc      = pc;
            saved_mstatus = dut.mstatus;
            saved_mepc    = dut.mepc;
            saved_mcause  = dut.mcause;
            saved_mtvec   = dut.mtvec;
            saved_mie     = dut.mie;
            saved_mip     = dut.mip;
            saved_mscratch = dut.mscratch;
            saved_mtval    = dut.mtval;

            // Match the test's instruction encodings, independently of the
            // DUT's trap_enter signal, so a missed exception fails the test.
            sampled_trap = saved_instr == BAD_OPCODE ||
                           saved_instr == BAD_SHORT ||
                           saved_instr == UNSUPPORTED_MUL ||
                           saved_instr == BAD_LOAD ||
                           saved_instr == BAD_STORE ||
                           saved_instr == BAD_CSR_READ ||
                           saved_instr == BAD_CSR_WRITE ||
                           saved_instr == BAD_CSR_WRITE_X0 ||
                           saved_instr == ECALL;

            if (sampled_trap || saved_instr == MRET)
                check_value("Fault/MRET normal write enables",
                            {29'b0, dut.rf_we, dut.csr_we, mem_we}, 32'b0);

            if (sampled_trap) begin
                if (saved_instr == ECALL)
                    check_value("ECALL prior illegal mtval", saved_mtval, BAD_CSR_WRITE_X0);

                for (integer r = 0; r < 32; r++)
                    saved_regs[r] = dut.u_regfile.regs[r];
                for (integer w = 0; w < 16; w++)
                    saved_ram[w] = dmem[w];
            end

            @(posedge clk);
            #1;  // Architectural state is now updated.

            if (sampled_trap) begin
                check_value("Trap PC", pc, {saved_mtvec[31:2], 2'b00});
                check_value("Trap mepc", dut.mepc, saved_pc);
                check_value("Trap cause", dut.mcause,
                            saved_instr == ECALL ? 32'd11 : 32'd2);
                case (saved_instr)
                    BAD_OPCODE, ECALL:
                        check_value("Trap mtval zero", dut.mtval, 32'b0);
                    BAD_SHORT:
                        check_value("16-bit mtval zero extension", dut.mtval, 32'h0000_0002);
                    default:
                        check_value("32-bit instruction in mtval", dut.mtval, saved_instr);
                endcase
                check_value("Trap MIE", {31'b0, dut.mstatus[3]}, 32'd0);
                check_value("Trap MPIE", {31'b0, dut.mstatus[7]},
                            {31'b0, saved_mstatus[3]});
                check_value("Trap MPP", {30'b0, dut.mstatus[12:11]}, 32'd3);

                check_value("Preserve mtvec", dut.mtvec, saved_mtvec);
                check_value("Preserve mie", dut.mie, saved_mie);
                check_value("Preserve mip", dut.mip, saved_mip);
                check_value("Preserve mscratch", dut.mscratch, saved_mscratch);
                for (integer r = 0; r < 32; r++)
                    check_value($sformatf("Preserve x%0d", r),
                                dut.u_regfile.regs[r], saved_regs[r]);
                for (integer w = 0; w < 16; w++)
                    check_value($sformatf("Preserve RAM[%0d]", w), dmem[w], saved_ram[w]);

                if (saved_instr == ECALL)
                    ecall_count++;
                else
                    illegal_count++;

                $display("[PASS] instr=%08x mepc=%08x mcause=%0d mtval=%08x -> PC=%08x; registers/CSR/RAM preserved",
                         saved_instr, dut.mepc, dut.mcause, dut.mtval, pc);
            end
            else if (saved_instr == MRET) begin
                mret_count++;
                check_value("MRET PC", pc, saved_mepc);
                check_value("MRET MIE", {31'b0, dut.mstatus[3]},
                            {31'b0, saved_mstatus[7]});
                check_value("MRET MPIE", {31'b0, dut.mstatus[7]}, 32'd1);
                check_value("MRET MPP", {30'b0, dut.mstatus[12:11]}, 32'd3);
                check_value("MRET mepc", dut.mepc, saved_mepc);
                check_value("MRET mcause", dut.mcause, saved_mcause);
                check_value("MRET preserves mtval", dut.mtval, saved_mtval);
                $display("[PASS] MRET #%0d preserves mtval=%08x", mret_count, dut.mtval);
            end

            if (pc[1:0] !== 2'b00 || pc >= 32'd1024)
                $fatal(1, "Invalid instruction address: %08x", pc);

            if (dut.u_regfile.regs[31] === 32'hffff_ffff)
                $fatal(1, "Assembly self-check failed: pc=%08x mepc=%08x mcause=%08x",
                       pc, dut.mepc, dut.mcause);

            if (dut.u_regfile.regs[31] === 32'd1) begin
                check_value("Illegal-instruction count", illegal_count, 32'd8);
                check_value("ECALL count", ecall_count, 32'd1);
                check_value("MRET count", mret_count, 32'd9);
                check_value("Handler entries", dut.u_regfile.regs[8], 32'd9);
                check_value("Successful returns", dut.u_regfile.regs[9], 32'd9);
                check_value("Legal RAM write count", ram_write_count, 32'd1);
                check_value("RAM sentinel", dmem[0], 32'h89ab_cdef);
                check_value("Destination sentinel", dut.u_regfile.regs[20], 32'h1357_9bdf);
                check_value("CSR sentinel", dut.mscratch, 32'h1234_5678);
                check_value("Final ECALL mtval", dut.mtval, 32'b0);
                $display("==============================");
                $display(" M8.2 ILLEGAL INSTRUCTION PASS");
                $display("  M8.3 MTVAL TRAP CHECKS PASS");
                $display("==============================");
                $finish;
            end

            @(negedge clk);
        end

        $fatal(1, "Illegal-instruction timeout: pc=%08x illegal=%0d ecall=%0d mret=%0d",
               pc, illegal_count, ecall_count, mret_count);
    end

endmodule
