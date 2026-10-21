module tb_soc_irq;
    localparam logic [31:0] RAM_BASE = 32'h1000_0000;
    localparam logic [31:0] TIMER_BASE = 32'h3000_0000;
    localparam logic [31:0] MRET = 32'h3020_0073;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [31:0] pc;
    logic uart_tx_valid;
    logic [7:0] uart_tx_data;
    // entry, handler, phase, count, ISR result, protected value, guard, bounds.
    logic [31:0] symbols [0:8];
    logic [31:0] saved_regs [0:31];
    logic [31:0] saved_pc;
    logic [31:0] frame_base;
    logic [31:0] c_return_pc;
    logic [31:0] min_sp;
    logic [31:0] old_pc;
    logic [31:0] old_instr;
    logic [31:0] old_status;
    logic [31:0] address;
    logic [31:0] api_mask;
    logic [31:0] current_phase;
    logic [63:0] old_time;
    logic [63:0] old_compare;
    logic [7:0] matrix_coverage = 8'b0;
    logic in_handler = 1'b0;
    logic c_called = 1'b0;
    logic c_returned = 1'b0;
    logic stack_live = 1'b0;
    logic done = 1'b0;
    logic expected_entry;
    logic is_mret;
    logic old_irq;
    logic api_access;
    logic api_clear;
    logic compare_write;
    logic compare_complete;
    integer entries = 0;
    integer returns = 0;
    integer api_saves_on = 0;
    integer api_saves_off = 0;
    integer api_restores_on = 0;
    integer api_restores_off = 0;
    integer isr_saves = 0;
    integer isr_restores = 0;
    integer disabled_pending_cycles = 0;
    integer nested_pending_cycles = 0;
    integer pending_unmasks = 0;
    integer irq_rises = 0;
    integer irq_falls = 0;
    integer compare_phase = 0;
    integer compare_sequences = 0;
    integer uart_lines = 0;
    string image_path = "build/irq/irq.hex";
    string symbol_path = "build/irq/irq.symbols.hex";
    string wave_path = "build/irq/irq.vcd";
    string uart_line = "";

    rv32_soc #(.ROM_BYTES(65536), .RAM_BYTES(65536)) dut (
        .clk (clk), .rst (rst), .pc (pc),
        .uart_tx_valid (uart_tx_valid), .uart_tx_data (uart_tx_data),
        .uart_rx_valid (1'b0),
        .uart_rx_data  (8'b0),
        .uart_rx_ready ()
    );

    initial begin
        forever #5 clk = ~clk;
    end

    function automatic logic [31:0] ram32(input logic [31:0] addr);
        if (addr < RAM_BASE || addr >= RAM_BASE + 32'h10000 || addr[1:0] != 0)
            $fatal(1, "Invalid monitored RAM address: %08x", addr);
        return dut.u_ram.mem[(addr - RAM_BASE) >> 2];
    endfunction

    task automatic check32(input string name, input logic [31:0] actual,
                           input logic [31:0] expected);
        if (actual !== expected)
            $fatal(1, "%s: got=%08x expected=%08x pc=%08x phase=%0d",
                   name, actual, expected, pc, current_phase);
    endtask

    task automatic check_frame;
        for (integer reg_num = 1; reg_num < 32; reg_num++)
            check32($sformatf("saved x%0d", reg_num),
                    ram32(frame_base + 32'((reg_num - 1) * 4)), saved_regs[reg_num]);
        check32("saved mepc", ram32(frame_base + 32'd124), saved_pc);
    endtask

    task automatic check_line(input string expected);
        if (uart_line != expected)
            $fatal(1, "UART line %0d: got='%s' expected='%s'", uart_lines, uart_line, expected);
    endtask

    initial begin
        if ($value$plusargs("image=%s", image_path)) begin end
        if ($value$plusargs("symbols=%s", symbol_path)) begin end
        if ($value$plusargs("wave=%s", wave_path)) begin end
        $dumpfile(wave_path);
        $dumpvars(0, tb_soc_irq);
        for (integer i = 0; i < 16384; i++)
            dut.u_ram.mem[i] = 32'hfeed_0000 ^ 32'(i);
        #1;
        $readmemh(image_path, dut.u_rom.mem);
        $readmemh(symbol_path, symbols);
        min_sp = symbols[8];
        $display("[RUN] %s", image_path);
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        #1;

        for (integer cycle = 0; cycle < 200000; cycle++) begin
            old_pc = pc;
            old_instr = dut.instr;
            old_status = dut.u_cpu.mstatus;
            old_irq = dut.timer_irq;
            old_time = dut.u_timer.mtime;
            old_compare = dut.u_timer.mtimecmp;
            address = dut.mem_addr;
            current_phase = ram32(symbols[2]);
            expected_entry = old_irq && old_status[3] && dut.u_cpu.mie[7];
            is_mret = old_instr == MRET;
            compare_write = dut.mem_we && address >= TIMER_BASE + 32'd8 && address <= TIMER_BASE + 32'd15;
            compare_complete = 1'b0;
            api_mask = old_instr[14] ? {27'b0, old_instr[19:15]} :
                       dut.u_cpu.u_regfile.regs[old_instr[19:15]];
            api_clear = old_instr[13:12] == 2'b11;
            api_access = !expected_entry && dut.u_cpu.csr_we && old_instr[31:20] == 12'h300 &&
                         api_mask == 32'd8 && (api_clear || old_instr[13:12] == 2'b10);

            if (pc[1:0] != 0 || pc >= 32'h10000)
                $fatal(1, "Invalid program PC: %08x", pc);
            check32("real timer drives MTIP", dut.u_cpu.mip, old_irq ? 32'h80 : 0);
            check32("only enabled timer may enter", {31'b0, dut.u_cpu.trap_enter}, {31'b0, expected_entry});
            if (in_handler && old_status[3])
                $fatal(1, "ISR critical section enabled nested interrupts");

            if (old_irq && current_phase == 3) begin
                check32("originally disabled remains masked", old_status, 32'h1880);
                check32("disabled test keeps MTIE set", dut.u_cpu.mie, 32'h80);
                disabled_pending_cycles++;
            end
            if (old_irq && current_phase == 4) begin
                check32("inner restore keeps outer section masked", old_status, 32'h1880);
                check32("nested test keeps MTIE set", dut.u_cpu.mie, 32'h80);
                nested_pending_cycles++;
            end
            if (api_access) begin
                if (api_clear && old_instr[11:7] != 0) begin
                    if (old_status[3]) api_saves_on++;
                    else api_saves_off++;
                    if (current_phase == 1)
                        matrix_coverage[{dut.u_cpu.mie[7], old_status[7], old_status[3]}] = 1'b1;
                    if (in_handler) isr_saves++;
                end else if (old_instr[11:7] == 0) begin
                    if (api_clear) api_restores_off++;
                    else api_restores_on++;
                    if (in_handler) isr_restores++;
                    if (!api_clear && old_irq) begin
                        check32("only outer restore unmasks pending IRQ", current_phase, 5);
                        pending_unmasks++;
                    end
                end
            end

            if (expected_entry) begin
                if (in_handler || entries != 0)
                    $fatal(1, "Unexpected/nested interrupt");
                check32("entry waits for outer restore", current_phase, 5);
                check32("ordinary shared data published", ram32(symbols[5]), 32'h2468_ace0);
                check32("no earlier C handler", ram32(symbols[3]), 0);
                check32("entry vector", dut.u_cpu.mtvec, symbols[0]);
                check32("entry cancels ordinary writes",
                        {29'b0, dut.u_cpu.rf_we, dut.u_cpu.csr_we, dut.mem_we}, 0);
                check32("old mtval", dut.u_cpu.mtval, 32'h89ab_cdef);
                saved_pc = old_pc;
                for (integer i = 0; i < 32; i++)
                    saved_regs[i] = dut.u_cpu.u_regfile.regs[i];
                frame_base = saved_regs[2] - 32'd128;
                if (frame_base < symbols[7] || saved_regs[2][3:0] != 0)
                    $fatal(1, "No aligned room for trap frame");
                in_handler = 1'b1;
                entries++;
            end
            if (in_handler && !expected_entry && old_pc == symbols[1]) begin
                if (c_called) $fatal(1, "Repeated C handler entry");
                check_frame();
                check32("C handler cause", dut.u_cpu.u_regfile.regs[10], 32'h8000_0007);
                check32("C handler epc", dut.u_cpu.u_regfile.regs[11], saved_pc);
                check32("C handler tval", dut.u_cpu.u_regfile.regs[12], 0);
                check32("C handler aligned sp", dut.u_cpu.u_regfile.regs[2], frame_base);
                c_return_pc = dut.u_cpu.u_regfile.regs[1];
                c_called = 1'b1;
            end
            if (in_handler && c_called && !c_returned && old_pc == c_return_pc) begin
                check32("C handler balances stack", dut.u_cpu.u_regfile.regs[2], frame_base);
                check_frame();
                c_returned = 1'b1;
            end
            if (is_mret) begin
                if (!in_handler || !c_returned) $fatal(1, "MRET before C handler finished");
                for (integer i = 0; i < 32; i++)
                    check32($sformatf("restored x%0d", i), dut.u_cpu.u_regfile.regs[i], saved_regs[i]);
                check32("return mepc", dut.u_cpu.mepc, saved_pc);
                check32("ISR preserves MPIE/MPP and leaves MIE clear", old_status, 32'h1880);
                check32("return MTIP", dut.u_cpu.mip, 0);
                check32("return MTIE", dut.u_cpu.mie, 0);
                check32("MRET selected", {31'b0, dut.u_cpu.mret_enter}, 1);
            end

            if (dut.mem_we && address >= TIMER_BASE && address < TIMER_BASE + 32'd8)
                $fatal(1, "Firmware wrote mtime");
            if (compare_write) begin
                check32("compare strobe", {28'b0, dut.mem_wstrb}, 32'hf);
                case (compare_phase)
                    0: begin
                        check32("compare first low address", address, TIMER_BASE + 32'd8);
                        check32("compare first low=-1", dut.mem_wdata, 32'hffff_ffff);
                        compare_phase = 1;
                    end
                    1: begin
                        check32("compare high address", address, TIMER_BASE + 32'd12);
                        compare_phase = 2;
                    end
                    2: begin
                        check32("compare final low address", address, TIMER_BASE + 32'd8);
                        compare_phase = 0;
                        compare_sequences++;
                        compare_complete = 1'b1;
                    end
                    default: $fatal(1, "Invalid comparator phase");
                endcase
            end

            @(posedge clk);
            #1;
            if (dut.u_timer.mtime !== old_time + 64'd1)
                $fatal(1, "mtime stopped in a critical section");
            if (api_access) begin
                check32("API changes only MIE", dut.u_cpu.mstatus,
                        api_clear ? old_status & ~32'h8 : old_status | 32'h8);
                if (api_clear && old_instr[11:7] != 0)
                    check32("atomic save reads pre-clear status",
                            dut.u_cpu.u_regfile.regs[old_instr[11:7]], old_status);
            end
            if (expected_entry) begin
                check32("entry PC", pc, symbols[0]);
                check32("entry mepc", dut.u_cpu.mepc, saved_pc);
                check32("entry cause", dut.u_cpu.mcause, 32'h8000_0007);
                check32("entry clears mtval", dut.u_cpu.mtval, 0);
                check32("entry mstatus", dut.u_cpu.mstatus, 32'h1880);
                for (integer i = 0; i < 32; i++)
                    check32("entry preserves GPR", dut.u_cpu.u_regfile.regs[i], saved_regs[i]);
            end
            if (!old_irq && dut.timer_irq) begin
                if (compare_write || dut.u_timer.mtimecmp !== old_compare ||
                    dut.u_timer.mtime !== old_compare || (current_phase != 3 && current_phase != 4))
                    $fatal(1, "IRQ did not arise at the real deadline inside a critical section");
                irq_rises++;
            end
            if (old_irq && !dut.timer_irq) begin
                if (!compare_write || dut.u_timer.mtimecmp <= dut.u_timer.mtime)
                    $fatal(1, "IRQ cleared without future comparator");
                irq_falls++;
            end
            if (compare_complete) begin
                if (compare_sequences == 1 || compare_sequences == 3) begin
                    if (dut.u_timer.mtimecmp <= dut.u_timer.mtime)
                        $fatal(1, "Deadline already passed at arm time");
                end else if ((compare_sequences != 2 && compare_sequences != 4) ||
                             dut.u_timer.mtimecmp !== 64'hffff_ffff_ffff_ffff)
                    $fatal(1, "Comparator was not disarmed");
            end
            if (is_mret) begin
                check32("MRET resumes canceled instruction", pc, saved_pc);
                check32("MRET restores MIE", dut.u_cpu.mstatus, 32'h1888);
                in_handler = 1'b0;
                returns++;
            end
            if (dut.u_cpu.u_regfile.regs[2] == symbols[8]) stack_live = 1'b1;
            if (stack_live) begin
                if (dut.u_cpu.u_regfile.regs[2] < symbols[7] ||
                    dut.u_cpu.u_regfile.regs[2] > symbols[8] || dut.u_cpu.u_regfile.regs[2][3:0] != 0)
                    $fatal(1, "Stack range/alignment failed");
                if (dut.u_cpu.u_regfile.regs[2] < min_sp) min_sp = dut.u_cpu.u_regfile.regs[2];
            end
            if (uart_tx_valid) begin
                $write("%c", uart_tx_data);
                if (uart_tx_data == 8'h0a) begin
                    case (uart_lines)
                        0: check_line("M10.4 START");
                        1: check_line("STATE MATRIX PASS");
                        2: check_line("RESTORE MASK PASS");
                        3: check_line("DISABLED RESTORE PASS");
                        4: check_line("PENDING DEFER PASS");
                        5: check_line("ISR CRITICAL PASS");
                        6: begin check_line("M10.4 PASS"); done = 1'b1; end
                        default: $fatal(1, "Unexpected UART line");
                    endcase
                    uart_lines++;
                    uart_line = "";
                end else uart_line = {uart_line, $sformatf("%c", uart_tx_data)};
            end
            if (done) begin
                check32("all eight initial states exercised", {24'b0, matrix_coverage}, 32'hff);
                check32("timer IRQ rises", 32'(irq_rises), 2);
                check32("timer IRQ clears", 32'(irq_falls), 2);
                check32("interrupt entries", 32'(entries), 1);
                check32("MRET count", 32'(returns), 1);
                check32("pending outer unmask", 32'(pending_unmasks), 1);
                check32("ISR nested saves", 32'(isr_saves), 2);
                check32("ISR nested restores", 32'(isr_restores), 2);
                check32("comparator sequences", 32'(compare_sequences), 4);
                check32("comparator phase", 32'(compare_phase), 0);
                check32("final test phase", ram32(symbols[2]), 6);
                check32("C IRQ count", ram32(symbols[3]), 1);
                check32("C ISR checks", ram32(symbols[4]), 1);
                check32("ordinary shared memory", ram32(symbols[5]), 32'h2468_ace0);
                check32("final MIE", {31'b0, dut.u_cpu.mstatus[3]}, 0);
                check32("final MTIE", dut.u_cpu.mie, 0);
                check32("final MTIP", dut.u_cpu.mip, 0);
                if (in_handler || !stack_live || min_sp == symbols[8] ||
                    disabled_pending_cycles < 64 || nested_pending_cycles < 64 ||
                    api_saves_on == 0 || api_saves_off == 0 ||
                    api_restores_on == 0 || api_restores_off == 0)
                    $fatal(1, "Incomplete IRQ API/stack/deferred-interrupt coverage");
                for (integer i = 0; i < 4; i++)
                    check32("stack guard", ram32(symbols[6] + 32'(i * 4)), 32'hc0de_cafe);
                $display("[PASS] eight initial MIE/MPIE/MTIE states; all non-MIE bits preserved");
                $display("[PASS] save on/off=%0d/%0d, restore on/off=%0d/%0d",
                         api_saves_on, api_saves_off, api_restores_on, api_restores_off);
                $display("[PASS] MTIP held while masked: disabled=%0d nested=%0d cycles",
                         disabled_pending_cycles, nested_pending_cycles);
                $display("[PASS] one deferred IRQ; two ISR nested saves/restores; 31 GPRs restored");
                $display("[PASS] deepest observed stack use: %0d bytes", symbols[8] - min_sp);
                $display(" M10.4 SOC IRQ API PASS");
                $finish;
            end
            @(negedge clk);
            #1;
        end
        $fatal(1, "IRQ API timeout: pc=%08x phase=%0d entries=%0d", pc, current_phase, entries);
    end
endmodule
