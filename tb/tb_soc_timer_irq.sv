module tb_soc_timer_irq;

    localparam logic [31:0] RAM_BASE = 32'h1000_0000;
    localparam logic [31:0] STACK_BOTTOM = 32'h1000_0200;
    localparam logic [31:0] STACK_TOP = 32'h1000_0400;
    localparam logic [31:0] GUARD_VALUE = 32'hc0de_cafe;
    localparam logic [31:0] TIMER_BASE = 32'h3000_0000;
    localparam logic [31:0] MRET = 32'h3020_0073;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [31:0] pc;
    logic uart_tx_valid;
    logic [7:0] uart_tx_data;
    logic in_handler = 1'b0;
    logic c_called = 1'b0;
    logic c_returned = 1'b0;
    logic stack_live = 1'b0;
    logic done = 1'b0;
    logic expected_entry;
    logic is_mret;
    logic compare_write;
    logic compare_complete;
    logic old_irq;
    logic [31:0] old_pc;
    logic [31:0] old_instr;
    logic [31:0] bus_addr;
    logic [31:0] bus_wdata;
    logic [31:0] saved_pc;
    logic [31:0] saved_vector;
    logic [31:0] saved_regs [0:31];
    logic [31:0] frame_base;
    logic [31:0] c_return_pc;
    logic [31:0] save_mask = 32'b0;
    logic [31:0] restore_mask = 32'b0;
    logic [31:0] min_sp = STACK_TOP;
    logic [63:0] old_time;
    logic [63:0] old_compare;
    logic [63:0] previous_deadline = 64'b0;
    integer entries = 0;
    integer returns = 0;
    integer c_calls = 0;
    integer c_returns = 0;
    integer irq_rises = 0;
    integer irq_falls = 0;
    integer compare_phase = 0;
    integer compare_sequences = 0;
    integer uart_lines = 0;
    integer frame_slot;
    logic [7:0] frame_word;
    string uart_line = "";

    rv32_soc #(
        .ROM_HEX ("build/soc_timer_irq/soc_timer_irq.hex")
    ) dut (
        .clk (clk),
        .rst (rst),
        .pc (pc),
        .uart_tx_valid (uart_tx_valid),
        .uart_tx_data (uart_tx_data)
    );

    initial begin
        forever #5 clk = ~clk;
    end

    task automatic check32(
        input string name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        if (actual !== expected)
            $fatal(1, "%s: got=%08x expected=%08x pc=%08x instr=%08x",
                   name, actual, expected, pc, dut.instr);
    endtask

    task automatic check_line(input string expected);
        if (uart_line != expected)
            $fatal(1, "UART line %0d: got='%s' expected='%s'", uart_lines, uart_line, expected);
    endtask

    task automatic check_frame;
        integer word_index;
        word_index = int'((frame_base - RAM_BASE) >> 2);
        for (integer reg_num = 1; reg_num < 32; reg_num++)
            check32($sformatf("saved frame x%0d", reg_num),
                    dut.u_ram.mem[word_index + reg_num - 1], saved_regs[reg_num]);
        check32("saved frame mepc", dut.u_ram.mem[word_index + 31], saved_pc);
    endtask

    initial begin
        $dumpfile("build/soc_timer_irq/soc_timer_irq.vcd");
        $dumpvars(0, tb_soc_timer_irq);
        // Give RAM a nonzero initial image. Only software initializes data,
        // clears BSS, and writes the trap frames after reset is released.
        for (integer i = 0; i < 256; i++)
            dut.u_ram.mem[i] = 32'hfeed_0000 ^ 32'(i);
        repeat (2) @(posedge clk);
        #1;
        check32("reset PC", pc, 32'b0);
        check32("reset timer IRQ", {31'b0, dut.timer_irq}, 32'b0);
        if (dut.u_timer.mtimecmp !== 64'hffff_ffff_ffff_ffff)
            $fatal(1, "Unexpected reset comparator");
        @(negedge clk);
        rst = 1'b0;
        #1;

        for (integer cycle = 0; cycle < 200000; cycle++) begin
            old_pc = pc;
            old_instr = dut.instr;
            bus_addr = dut.mem_addr;
            bus_wdata = dut.mem_wdata;
            old_irq = dut.timer_irq;
            old_time = dut.u_timer.mtime;
            old_compare = dut.u_timer.mtimecmp;
            compare_write = dut.mem_we && bus_addr >= TIMER_BASE + 32'h8 &&
                            bus_addr <= TIMER_BASE + 32'hf;
            compare_complete = 1'b0;
            expected_entry = old_irq && dut.u_cpu.mstatus[3] && dut.u_cpu.mie[7];
            is_mret = old_instr == MRET;

            if (pc[1:0] != 2'b00 || pc >= 32'h1000)
                $fatal(1, "Invalid program address: %08x", pc);
            check32("real timer pending reaches CPU", dut.u_cpu.mip, old_irq ? 32'h80 : 32'b0);
            check32("CPU entry follows real enabled IRQ", {31'b0, dut.u_cpu.trap_enter},
                    {31'b0, expected_entry});

            if (in_handler && dut.u_cpu.mstatus[3])
                $fatal(1, "Handler enabled nested interrupts");

            if (expected_entry) begin
                if (in_handler || entries >= 3)
                    $fatal(1, "Unexpected extra/nested timer interrupt");
                saved_pc = old_pc;
                saved_vector = dut.u_cpu.mtvec;
                for (integer i = 0; i < 32; i++)
                    saved_regs[i] = dut.u_cpu.u_regfile.regs[i];
                if (saved_regs[2] < STACK_BOTTOM + 32'd128 || saved_regs[2] > STACK_TOP ||
                    saved_regs[2][3:0] != 4'b0)
                    $fatal(1, "Insufficient/aligned interrupt stack: %08x", saved_regs[2]);
                frame_base = saved_regs[2] - 32'd128;
                save_mask = 32'b0;
                restore_mask = 32'b0;
                c_called = 1'b0;
                c_returned = 1'b0;
                in_handler = 1'b1;
                entries++;
                check32("Direct vector mode", {30'b0, saved_vector[1:0]}, 32'b0);
                check32("entry cancels ordinary writes",
                        {29'b0, dut.u_cpu.rf_we, dut.u_cpu.csr_we, dut.mem_we}, 32'b0);
                check32("entry excludes MRET", {31'b0, dut.u_cpu.mret_enter}, 32'b0);
                check32("previous mtval", dut.u_cpu.mtval,
                        entries == 1 ? 32'h89ab_cdef : 32'b0);
            end

            if (in_handler && !expected_entry && c_called && !c_returned && old_pc == c_return_pc) begin
                c_returned = 1'b1;
                c_returns++;
                check32("C handler balances its stack", dut.u_cpu.u_regfile.regs[2], frame_base);
                check_frame();
            end

            // The unrelaxed assembly call uses AUIPC/JALR. This is the first
            // call after saving the frame; later C calls run below frame_base.
            if (in_handler && !expected_entry && !c_called && old_instr[6:0] == 7'h67 &&
                old_instr[11:7] == 5'd1) begin
                check32("all frame slots were written", save_mask, 32'hffff_ffff);
                check_frame();
                check32("C argument cause", dut.u_cpu.u_regfile.regs[10], 32'h8000_0007);
                check32("C argument mepc", dut.u_cpu.u_regfile.regs[11], saved_pc);
                check32("C argument mtval", dut.u_cpu.u_regfile.regs[12], 32'b0);
                check32("C call stack", dut.u_cpu.u_regfile.regs[2], frame_base);
                c_return_pc = old_pc + 32'd4;
                c_called = 1'b1;
                c_calls++;
            end

            if (in_handler && !expected_entry &&
                bus_addr >= frame_base && bus_addr < frame_base + 32'd128) begin
                frame_slot = int'((bus_addr - frame_base) >> 2);
                frame_word = bus_addr[9:2];
                if (!c_called && dut.mem_we) begin
                    check32("frame store alignment", {30'b0, bus_addr[1:0]}, 32'b0);
                    check32("frame store strobes", {28'b0, dut.mem_wstrb}, 32'hf);
                    check32("frame store value", bus_wdata,
                            frame_slot == 31 ? saved_pc : saved_regs[frame_slot + 1]);
                    save_mask[frame_slot] = 1'b1;
                end
                if (c_returned && dut.u_cpu.mem_load) begin
                    check32("frame restore alignment", {30'b0, bus_addr[1:0]}, 32'b0);
                    check32("frame restore enabled", {31'b0, dut.u_cpu.rf_we}, 32'd1);
                    check32("frame restore destination", {27'b0, old_instr[11:7]},
                            frame_slot == 31 ? 32'd5 : 32'(frame_slot + 1));
                    check32("frame restore data", dut.mem_rdata, dut.u_ram.mem[frame_word]);
                    restore_mask[frame_slot] = 1'b1;
                end
            end

            if (is_mret) begin
                if (!in_handler || !c_returned)
                    $fatal(1, "MRET without a completed C handler");
                check32("all frame slots were restored", restore_mask, 32'hffff_ffff);
                for (integer i = 0; i < 32; i++)
                    check32($sformatf("restored x%0d", i), dut.u_cpu.u_regfile.regs[i], saved_regs[i]);
                check32("mepc unchanged by software", dut.u_cpu.mepc, saved_pc);
                check32("return cause", dut.u_cpu.mcause, 32'h8000_0007);
                check32("return mtval", dut.u_cpu.mtval, 32'b0);
                check32("return status", dut.u_cpu.mstatus, 32'h1880);
                check32("return timer source cleared", dut.u_cpu.mip, 32'b0);
                check32("return MTIE", dut.u_cpu.mie, entries == 3 ? 32'b0 : 32'h80);
                check32("MRET selected", {31'b0, dut.u_cpu.mret_enter}, 32'd1);
                check32("MRET has no ordinary writes",
                        {29'b0, dut.u_cpu.rf_we, dut.u_cpu.csr_we, dut.mem_we}, 32'b0);
            end

            if (dut.mem_we && bus_addr >= TIMER_BASE && bus_addr < TIMER_BASE + 32'h8)
                $fatal(1, "Program unexpectedly wrote mtime");
            if (compare_write) begin
                check32("compare write strobe", {28'b0, dut.mem_wstrb}, 32'hf);
                case (compare_phase)
                    0: begin
                        check32("compare first address", bus_addr, TIMER_BASE + 32'h8);
                        check32("compare first low=-1", bus_wdata, 32'hffff_ffff);
                        compare_phase = 1;
                    end
                    1: begin
                        check32("compare high address", bus_addr, TIMER_BASE + 32'hc);
                        compare_phase = 2;
                    end
                    2: begin
                        check32("compare final low address", bus_addr, TIMER_BASE + 32'h8);
                        compare_phase = 0;
                        compare_sequences++;
                        compare_complete = 1'b1;
                    end
                    default: $fatal(1, "Invalid comparator write phase");
                endcase
            end

            @(posedge clk);
            #1;
            if (dut.u_timer.mtime !== old_time + 64'd1)
                $fatal(1, "mtime did not advance by one cycle");

            if (expected_entry) begin
                check32("entry PC", pc, saved_vector);
                check32("entry mepc", dut.u_cpu.mepc, saved_pc);
                check32("entry cause", dut.u_cpu.mcause, 32'h8000_0007);
                check32("entry mtval cleared", dut.u_cpu.mtval, 32'b0);
                check32("entry status", dut.u_cpu.mstatus, 32'h1880);
                for (integer i = 0; i < 32; i++)
                    check32($sformatf("entry preserves x%0d", i), dut.u_cpu.u_regfile.regs[i], saved_regs[i]);
            end

            if (!old_irq && dut.timer_irq) begin
                if (compare_write || dut.u_timer.mtimecmp !== old_compare ||
                    dut.u_timer.mtime !== old_compare || old_time + 64'd1 !== old_compare)
                    $fatal(1, "IRQ was not raised by reaching the programmed deadline");
                irq_rises++;
                $display("[PASS] real timer deadline #%0d at %016x", irq_rises, dut.u_timer.mtime);
            end
            if (old_irq && !dut.timer_irq) begin
                if (!compare_write || dut.u_timer.mtimecmp <= dut.u_timer.mtime)
                    $fatal(1, "IRQ cleared without a future comparator write");
                irq_falls++;
            end
            if (compare_complete) begin
                if (compare_sequences <= 3) begin
                    if (dut.u_timer.mtimecmp <= dut.u_timer.mtime ||
                        (compare_sequences > 1 && dut.u_timer.mtimecmp !== previous_deadline + 64'd4096))
                        $fatal(1, "Invalid periodic deadline: %016x", dut.u_timer.mtimecmp);
                    previous_deadline = dut.u_timer.mtimecmp;
                end
                else if (compare_sequences != 4 || dut.u_timer.mtimecmp !== 64'hffff_ffff_ffff_ffff)
                    $fatal(1, "Final comparator was not disarmed");
            end

            if (is_mret) begin
                returns++;
                check32("MRET resumes exact PC", pc, saved_pc);
                check32("MRET restores MIE", dut.u_cpu.mstatus, 32'h1888);
                in_handler = 1'b0;
                $display("[PASS] MRET #%0d restored all GPRs and sp=%08x, resumes pc=%08x",
                         returns, saved_regs[2], saved_pc);
            end

            if (dut.u_cpu.u_regfile.regs[2] == STACK_TOP)
                stack_live = 1'b1;
            if (stack_live) begin
                if (dut.u_cpu.u_regfile.regs[2] < STACK_BOTTOM ||
                    dut.u_cpu.u_regfile.regs[2] > STACK_TOP ||
                    dut.u_cpu.u_regfile.regs[2][3:0] != 4'b0)
                    $fatal(1, "Stack out of range/alignment: %08x", dut.u_cpu.u_regfile.regs[2]);
                if (dut.u_cpu.u_regfile.regs[2] < min_sp)
                    min_sp = dut.u_cpu.u_regfile.regs[2];
            end

            if (uart_tx_valid) begin
                $write("%c", uart_tx_data);
                if (uart_tx_data == 8'h0a) begin
                    case (uart_lines)
                        0: check_line("M9.3.3 START");
                        1: check_line("TICKS=3");
                        2: check_line("CONTEXT PASS");
                        3: begin check_line("M9.3.3 PASS"); done = 1'b1; end
                        default: $fatal(1, "Unexpected extra UART line");
                    endcase
                    uart_line = "";
                    uart_lines++;
                end
                else
                    uart_line = {uart_line, $sformatf("%c", uart_tx_data)};
            end

            if (done) begin
                check32("timer interrupt entries", entries, 32'd3);
                check32("MRET returns", returns, 32'd3);
                check32("C handler calls", c_calls, 32'd3);
                check32("C handler returns", c_returns, 32'd3);
                check32("real deadline count", irq_rises, 32'd3);
                check32("IRQ clear count", irq_falls, 32'd3);
                check32("complete comparator sequences", compare_sequences, 32'd4);
                check32("no unfinished comparator write", compare_phase, 32'b0);
                check32("stack guard", dut.u_ram.mem[127], GUARD_VALUE);
                check32("final MTIE", dut.u_cpu.mie, 32'b0);
                check32("final pending", dut.u_cpu.mip, 32'b0);
                check32("no unfinished handler", {31'b0, in_handler}, 32'b0);
                if (!stack_live || min_sp == STACK_TOP)
                    $fatal(1, "Stack was not exercised");
                $display("[PASS] deepest observed stack use: %0d / 512 bytes", STACK_TOP - min_sp);
                $display("==============================");
                $display(" M9.3.3 SOC TIMER IRQ PASS");
                $display("==============================");
                $finish;
            end
            @(negedge clk);
            #1;
        end
        $fatal(1, "SoC timer IRQ timeout: pc=%08x entries=%0d returns=%0d", pc, entries, returns);
    end

endmodule
