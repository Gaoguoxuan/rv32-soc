module tb_soc_rtthread_tick;
    localparam logic [31:0] RAM_BASE = 32'h1000_0000, UART_TX = 32'h2000_0000;
    localparam logic [31:0] TIMER = 32'h3000_0000, MRET = 32'h3020_0073;
    localparam integer TRAP = 0, DISPATCH = 1, RESTORE = 2, SWITCH_TO = 3, SWITCH = 4,
        IRQ_SWITCH = 5, TICK_INIT = 6, REARM = 7, ENTER = 8, LEAVE = 9, INCREASE = 10,
        TICK = 11, ENTRY = 12, FINISH = 13, EXIT = 14, LOCATIONS = 15,
        STACK_A = 16, STACK_B = 17, STACK_CHECK = 18, ARGUMENTS = 19,
        PROGRESS = 20, SUMS = 21, RETURNS = 22, STOPPED = 23, COOKIE = 24,
        GUARD = 25, BOTTOM = 26, TOP = 27, CURRENT = 28, NEST = 29,
        FROM = 30, TO = 31, FLAG = 32, INIT = 33, STARTUP = 34;
    logic clk = 1'b0, rst = 1'b1;
    logic [31:0] pc;
    logic uart_tx_valid;
    logic [7:0] uart_tx_data;
    logic [31:0] symbols [0:34];
    // x1..x31, return PC, saved mstatus, three reserved words.
    logic [31:0] golden [1:3][0:35];
    logic [31:0] frames [1:3], min_sp [0:3];
    logic [35:0] save_mask;
    logic [32:0] load_mask;
    logic active = 1'b0, restoring = 1'b0, c_called, c_returned, pointer_saved;
    logic target_loaded, epc_restored, status_restored, stack_live = 1'b0;
    logic done = 1'b0, wrapped = 1'b0, expected_irq, is_mret, compare_write;
    logic write_time_low, write_time_high;
    logic [31:0] dispatch_return, enter_return = 0, leave_return = 0;
    logic [31:0] increase_return = 0, from_location, to_location, target_frame;
    logic [31:0] address, store_value, sp_value, interrupted_pc;
    logic [31:0] boot_gp, boot_tp, compare_high;
    logic [63:0] old_time, old_compare, last_sample = 0, deadline = 0, compare_value;
    logic old_irq;
    integer kind = 0; // 0: first start, 1: thread call, 2: timer interrupt
    integer owner = 0, source_id = 0, target_id = 0, irqs = 0, irq_returns = 0;
    integer same_returns = 0, irq_switches = 0, software_switches = 0;
    integer restores = 0, entries = 0, exits = 0, dispatches = 0, c_returns = 0;
    integer enters = 0, leaves = 0, increases = 0, rearms = 0, requests = 0;
    integer init_calls = 0, startup_calls = 0, compare_phase = 0, compare_sequences = 0;
    integer periodic_compares = 0, irq_rises = 0, irq_falls = 0, time_writes = 0;
    integer uart_lines = 0, slot;
    string image_path = "build/rtthread_tick/rtthread_tick.hex";
    string symbol_path = "build/rtthread_tick/rtthread_tick.symbols.hex";
    string wave_path = "build/rtthread_tick/rtthread_tick.vcd";
    string uart_line = "";

    rv32_soc #(.ROM_BYTES(65536), .RAM_BYTES(65536)) dut (
        .clk (clk), .rst (rst), .pc (pc),
        .uart_tx_valid (uart_tx_valid), .uart_tx_data (uart_tx_data)
    );
    // Make supplies a 1 ns timescale: 100 ns period = 10 MHz.
    initial forever #50 clk = ~clk;

    function automatic logic [31:0] ram32(input logic [31:0] addr);
        if (addr < RAM_BASE || addr >= RAM_BASE + 32'h10000 || addr[1:0] != 0)
            $fatal(1, "Invalid monitored RAM address: %08x", addr);
        return dut.u_ram.mem[(addr - RAM_BASE) >> 2];
    endfunction
    function automatic logic [31:0] rom32(input logic [31:0] addr);
        if (addr >= 32'h10000 || addr[1:0] != 0) $fatal(1, "Invalid ROM address");
        return dut.u_rom.mem[addr >> 2];
    endfunction
    function automatic logic [31:0] nest_value();
        return (ram32(symbols[NEST] & ~32'h3) >> (8 * int'(symbols[NEST][1:0]))) & 32'hff;
    endfunction
    function automatic logic [31:0] sp_location(input integer id);
        return rom32(symbols[LOCATIONS] + 32'((id - 1) * 4));
    endfunction
    function automatic logic [31:0] thread_address(input integer id);
        return rom32(symbols[LOCATIONS] + 32'((id + 2) * 4));
    endfunction
    function automatic logic [31:0] stack_top(input integer id);
        return id == 0 ? symbols[TOP] : symbols[STACK_A + id - 1] + 32'd2048;
    endfunction
    function automatic logic stack_valid(input logic [31:0] value, input integer id);
        logic [31:0] bottom;
        bottom = id == 0 ? symbols[BOTTOM] : symbols[STACK_A + id - 1] + 32'd16;
        return value >= bottom && value <= stack_top(id) && value[3:0] == 0;
    endfunction
    task automatic check32(input string name, input logic [31:0] actual, input logic [31:0] expected);
        if (actual !== expected)
            $fatal(1, "%s: got=%08x expected=%08x pc=%08x owner=%0d irq=%0d",
                   name, actual, expected, pc, owner, irqs);
    endtask
    task automatic check_frame(input integer id);
        for (integer i = 0; i < 36; i++)
            check32($sformatf("thread %0d frame field %0d", id, i),
                    ram32(frames[id] + 32'(i * 4)), golden[id][i]);
    endtask
    task automatic prepare_initial(input integer id);
        frames[id] = stack_top(id) - 32'd144;
        for (integer i = 0; i < 36; i++) golden[id][i] = 0;
        golden[id][0] = symbols[EXIT];
        golden[id][1] = stack_top(id);
        golden[id][2] = boot_gp;
        golden[id][3] = boot_tp;
        golden[id][9] = id == 3 ? thread_address(3) : symbols[ARGUMENTS] + 32'((id - 1) * 8);
        golden[id][31] = id == 3 ? symbols[FINISH] : symbols[ENTRY];
        golden[id][32] = 32'h1880;
    endtask
    task automatic snapshot_source();
        frames[source_id] = dut.u_cpu.u_regfile.regs[2] - 32'd144;
        if (!stack_valid(frames[source_id], source_id)) $fatal(1, "Frame outside source stack");
        for (integer reg_num = 1; reg_num < 32; reg_num++)
            golden[source_id][reg_num - 1] = dut.u_cpu.u_regfile.regs[reg_num];
        golden[source_id][31] = kind == 2 ? pc : dut.u_cpu.u_regfile.regs[1];
        golden[source_id][32] = kind == 2 ? 32'h1880 : dut.u_cpu.mstatus & ~32'h88;
        for (integer i = 33; i < 36; i++) golden[source_id][i] = 0;
    endtask
    task automatic begin_transition();
        if (active) $fatal(1, "Nested transition");
        active = 1'b1;
        restoring = 1'b0;
        c_called = 1'b0;
        c_returned = 1'b0;
        pointer_saved = 1'b0;
        target_loaded = 1'b0;
        epc_restored = 1'b0;
        status_restored = 1'b0;
        save_mask = '0;
        load_mask = '0;
        source_id = owner;
    endtask
    task automatic check_line(input string expected, input integer expected_owner);
        if (uart_line != expected)
            $fatal(1, "UART line %0d: got='%s' expected='%s'", uart_lines, uart_line, expected);
        check32("UART owner", 32'(owner), 32'(expected_owner));
    endtask

    initial begin
        if ($value$plusargs("image=%s", image_path)) begin end
        if ($value$plusargs("symbols=%s", symbol_path)) begin end
        if ($value$plusargs("wave=%s", wave_path)) begin end
        $dumpfile(wave_path);
        $dumpvars(0, tb_soc_rtthread_tick);
        for (integer i = 0; i < 16384; i++) dut.u_ram.mem[i] = 32'hfeed_0000 ^ 32'(i);
        #1;
        $readmemh(image_path, dut.u_rom.mem);
        $readmemh(symbol_path, symbols);
        $display("[RUN] %s", image_path);
        check32("A stack", symbols[STACK_A], 32'h1000_8000);
        check32("B stack", symbols[STACK_B], 32'h1000_9000);
        check32("check stack", symbols[STACK_CHECK], 32'h1000_a000);
        for (integer id = 0; id < 4; id++) min_sp[id] = stack_top(id);
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        #1;

        for (integer cycle = 0; cycle < 500000; cycle++) begin
            address = dut.mem_addr;
            store_value = dut.mem_wdata;
            old_time = dut.u_timer.mtime;
            old_compare = dut.u_timer.mtimecmp;
            old_irq = dut.timer_irq;
            expected_irq = old_irq && dut.u_cpu.mstatus[3] && dut.u_cpu.mie[7];
            is_mret = dut.instr == MRET;
            compare_write = dut.mem_we && (address == TIMER + 8 || address == TIMER + 12);
            write_time_low = dut.mem_we && address == TIMER;
            write_time_high = dut.mem_we && address == TIMER + 4;
            if (pc[1:0] != 0 || pc >= 32'h10000) $fatal(1, "Invalid PC: %08x", pc);
            check32("MTIP follows timer", dut.u_cpu.mip, old_irq ? 32'h80 : 0);
            check32("only a real enabled timer enters trap", {31'b0, dut.u_cpu.trap_enter}, {31'b0, expected_irq});
            if (dut.mem_we && !(address >= RAM_BASE && address < RAM_BASE + 32'h10000) &&
                address != UART_TX && !(address >= TIMER && address < TIMER + 16))
                $fatal(1, "Unexpected store: %08x", address);
            if (pc == symbols[INIT]) init_calls++;
            if (pc == symbols[STARTUP]) startup_calls++;
            if (pc == symbols[TICK_INIT]) check32("tick init on main", 32'(owner), 0);

            if (expected_irq) begin
                begin_transition();
                kind = 2;
                irqs++;
                if (irqs > 12 || owner < 1 || owner > 2) $fatal(1, "Unexpected IRQ");
                check32("interrupted thread order", 32'(owner), 32'(((irqs - 1) / 2) % 2 + 1));
                check32("pre-trap status", dut.u_cpu.mstatus, 32'h1888);
                check32("trap cancels writes", {29'b0, dut.u_cpu.rf_we, dut.u_cpu.csr_we, dut.mem_we}, 0);
                check32("IRQ starts outside kernel interrupt", nest_value(), 0);
                check32("no stale switch request", ram32(symbols[FLAG]), 0);
                interrupted_pc = pc;
                snapshot_source();
                target_id = (irqs / 2) % 2 + 1;
            end
            if (pc == symbols[SWITCH_TO] || pc == symbols[SWITCH]) begin
                begin_transition();
                kind = pc == symbols[SWITCH_TO] ? 0 : 1;
                if (kind == 0) begin
                    check32("first switch on main", 32'(owner), 0);
                    boot_gp = dut.u_cpu.u_regfile.regs[3];
                    boot_tp = dut.u_cpu.u_regfile.regs[4];
                    target_id = 1;
                    for (integer id = 1; id <= 3; id++) prepare_initial(id);
                    to_location = dut.u_cpu.u_regfile.regs[10];
                end else begin
                    if (software_switches >= 2) $fatal(1, "Unexpected voluntary switch");
                    check32("thread-call source", 32'(owner), 32'(software_switches + 1));
                    target_id = software_switches == 0 ? 2 : 3;
                    from_location = dut.u_cpu.u_regfile.regs[10];
                    to_location = dut.u_cpu.u_regfile.regs[11];
                    check32("source sp field", from_location, sp_location(source_id));
                    snapshot_source();
                    software_switches++;
                end
                check32("switch entry MIE", {31'b0, dut.u_cpu.mstatus[3]}, 0);
                check32("target sp field", to_location, sp_location(target_id));
                check32("kernel selected target", ram32(symbols[CURRENT]), thread_address(target_id));
                target_frame = ram32(to_location);
                check32("target saved pointer", target_frame, frames[target_id]);
                check_frame(target_id);
            end

            if (pc == symbols[RESTORE]) begin
                if (!active || !target_loaded || (kind == 2 && !c_returned)) $fatal(1, "Early restore");
                check32("restore uses selected frame", dut.u_cpu.u_regfile.regs[2], target_frame);
                restoring = 1'b1;
            end
            if (active && !expected_irq) begin
                check32("MIE clear through handler/restore", {31'b0, dut.u_cpu.mstatus[3]}, 0);
                if (dut.mem_we && !restoring && (kind == 1 || (kind == 2 && !c_called))) begin
                    if (kind == 1 && address == from_location) begin
                        if (save_mask !== 36'hf_ffff_ffff || pointer_saved) $fatal(1, "Early sp writeback");
                        check32("source sp writeback", store_value, frames[source_id]);
                        pointer_saved = 1'b1;
                    end else begin
                        if (pointer_saved || address < frames[source_id] || address >= frames[source_id] + 144 || address[1:0] != 0)
                            $fatal(1, "Save outside source frame: %08x", address);
                        slot = int'((address - frames[source_id]) >> 2);
                        check32("saved architectural value", store_value, golden[source_id][slot]);
                        save_mask[slot] = 1'b1;
                    end
                end
                if (kind != 2 && !restoring && dut.instr[6:0] == 7'h03) begin
                    if (target_loaded) $fatal(1, "Unexpected extra pointer load");
                    check32("load selected sp field", address, to_location);
                    check32("pointer destination", {27'b0, dut.instr[11:7]}, 2);
                    check32("selected frame", dut.mem_rdata, target_frame);
                    if (kind == 1) begin
                        if (!pointer_saved) $fatal(1, "Missing source sp writeback");
                        check_frame(source_id);
                    end
                    target_loaded = 1'b1;
                end
            end
            if (pc == symbols[TRAP] && !(active && kind == 2 && !c_called)) $fatal(1, "Unexpected trap entry");
            if (pc == symbols[DISPATCH]) begin
                if (!active || kind != 2 || c_called || save_mask !== 36'hf_ffff_ffff)
                    $fatal(1, "Incomplete IRQ save before C");
                check_frame(source_id);
                check32("C frame parameter", dut.u_cpu.u_regfile.regs[10], frames[source_id]);
                check32("C cause parameter", dut.u_cpu.u_regfile.regs[11], 32'h8000_0007);
                check32("C tval parameter", dut.u_cpu.u_regfile.regs[12], 0);
                dispatch_return = dut.u_cpu.u_regfile.regs[1];
                c_called = 1'b1;
                dispatches++;
            end
            if (active && kind == 2) begin
                if (pc == symbols[ENTER]) begin
                    check32("nest before enter", nest_value(), 0);
                    enter_return = dut.u_cpu.u_regfile.regs[1];
                end
                if (pc == enter_return) begin
                    check32("nest after enter", nest_value(), 1);
                    enter_return = 0;
                    enters++;
                end
                if (pc == symbols[LEAVE]) begin
                    check32("nest before leave", nest_value(), 1);
                    leave_return = dut.u_cpu.u_regfile.regs[1];
                end
                if (pc == leave_return) begin
                    check32("nest after leave", nest_value(), 0);
                    leave_return = 0;
                    leaves++;
                end
                if (pc == symbols[REARM]) begin
                    check32("rearm in interrupt context", nest_value(), 1);
                    rearms++;
                end
                if (pc == symbols[INCREASE]) begin
                    check32("tick in interrupt context", nest_value(), 1);
                    check32("old kernel tick", ram32(symbols[TICK]), 32'(irqs - 1));
                    increase_return = dut.u_cpu.u_regfile.regs[1];
                end
                if (pc == increase_return) begin
                    check32("tick increases exactly once", ram32(symbols[TICK]), 32'(irqs));
                    increase_return = 0;
                    increases++;
                end
                if (pc == symbols[IRQ_SWITCH]) begin
                    if (irqs[0]) $fatal(1, "Switch before two-tick slice expired");
                    check32("request in interrupt context", nest_value(), 1);
                    check32("request source", dut.u_cpu.u_regfile.regs[10], sp_location(source_id));
                    check32("request target", dut.u_cpu.u_regfile.regs[11], sp_location(target_id));
                    requests++;
                end
                if (c_called && !c_returned && pc == dispatch_return) begin
                    check32("C return frame", dut.u_cpu.u_regfile.regs[10], frames[target_id]);
                    check32("C returns on source stack", dut.u_cpu.u_regfile.regs[2], frames[source_id]);
                    check32("nest clear before switching stacks", nest_value(), 0);
                    check32("request consumed", ram32(symbols[FLAG]), 0);
                    check32("kernel current target", ram32(symbols[CURRENT]), thread_address(target_id));
                    if (target_id != source_id) begin
                        check32("saved interrupted sp", ram32(sp_location(source_id)), frames[source_id]);
                        check32("recorded first source", ram32(symbols[FROM]), sp_location(source_id));
                        check32("recorded final target", ram32(symbols[TO]), sp_location(target_id));
                    end
                    check_frame(target_id);
                    target_frame = frames[target_id];
                    c_returned = 1'b1;
                    target_loaded = 1'b1;
                    c_returns++;
                end
            end
            if (restoring) begin
                if (dut.mem_we) $fatal(1, "Store during restore");
                if (dut.instr[6:0] == 7'h03) begin
                    if (address < target_frame || address >= target_frame + 132 || address[1:0] != 0)
                        $fatal(1, "Restore outside frame");
                    slot = int'((address - target_frame) >> 2);
                    check32("restore destination", {27'b0, dut.instr[11:7]}, slot >= 31 ? 5 : 32'(slot + 1));
                    check32("restore data", dut.mem_rdata, golden[target_id][slot]);
                    load_mask[slot] = 1'b1;
                end
                if (dut.u_cpu.csr_we) begin
                    case (dut.instr[31:20])
                        12'h300: begin
                            check32("restore mstatus", dut.u_cpu.csr_wdata, golden[target_id][32] & ~32'h8);
                            status_restored = 1'b1;
                        end
                        12'h341: begin
                            check32("restore mepc", dut.u_cpu.csr_wdata, golden[target_id][31]);
                            epc_restored = 1'b1;
                        end
                        default: $fatal(1, "Unexpected CSR restore");
                    endcase
                end
            end
            if (is_mret) begin
                if (!active || !restoring || !epc_restored || !status_restored || load_mask !== 33'h1_ffff_ffff)
                    $fatal(1, "Incomplete restore before MRET");
                for (integer reg_num = 1; reg_num < 32; reg_num++)
                    check32($sformatf("restored x%0d", reg_num), dut.u_cpu.u_regfile.regs[reg_num], golden[target_id][reg_num - 1]);
                check32("MRET mepc", dut.u_cpu.mepc, golden[target_id][31]);
                check32("MRET status", dut.u_cpu.mstatus, golden[target_id][32] & ~32'h8);
                check32("timer deasserted before MRET", {31'b0, dut.timer_irq}, 0);
            end
            if (pc == symbols[ENTRY] || pc == symbols[FINISH]) begin
                check32("thread C entry order", 32'(owner), 32'(entries + 1));
                check32("entry SP", dut.u_cpu.u_regfile.regs[2], stack_top(owner));
                check32("entry status", dut.u_cpu.mstatus, 32'h1888);
                check32("entry parameter", dut.u_cpu.u_regfile.regs[10], golden[owner][9]);
                entries++;
            end
            if (pc == symbols[EXIT]) begin
                check32("normal C exit order", 32'(owner), 32'(exits + 1));
                check32("normal C return balances stack", dut.u_cpu.u_regfile.regs[2], stack_top(owner));
                check32("completed C bodies", ram32(symbols[RETURNS]), 32'(owner));
                exits++;
            end

            if (!expected_irq && dut.instr[6:0] == 7'h03 && address == TIMER) last_sample = old_time;
            if (compare_write) begin
                check32("word compare write", {28'b0, dut.mem_wstrb}, 15);
                case (compare_phase)
                    0: begin
                        check32("safe compare starts at low", address, TIMER + 8);
                        check32("safe compare low=-1", store_value, 32'hffff_ffff);
                        compare_phase = 1;
                    end
                    1: begin
                        check32("safe compare high", address, TIMER + 12);
                        compare_high = store_value;
                        compare_phase = 2;
                    end
                    2: begin
                        check32("safe compare final low", address, TIMER + 8);
                        compare_value = {compare_high, store_value};
                        if (compare_value != 64'hffff_ffff_ffff_ffff) begin
                            if (compare_value !== (periodic_compares == 0 ? last_sample + 64'd10000 : deadline + 64'd10000))
                                $fatal(1, "Deadline drift/carry: got=%016x previous=%016x sample=%016x", compare_value, deadline, last_sample);
                            if (compare_value <= old_time || compare_value[63:32] != 1) $fatal(1, "Invalid future deadline");
                            deadline = compare_value;
                            periodic_compares++;
                        end
                        compare_sequences++;
                        compare_phase = 0;
                    end
                    default: $fatal(1, "Invalid compare phase");
                endcase
            end
            if (dut.mem_we && (address == TIMER || address == TIMER + 4)) begin
                check32("time seed on main", 32'(owner), 0);
                check32("time seed with interrupts masked", dut.u_cpu.mie, 0);
                time_writes++;
            end

            @(posedge clk);
            #1;
            if (write_time_low) begin
                if (dut.u_timer.mtime !== {old_time[63:32], store_value}) $fatal(1, "mtime low write/count");
            end else if (write_time_high) begin
                if (dut.u_timer.mtime !== {store_value, old_time[31:0]}) $fatal(1, "mtime high write/count");
            end else if (dut.u_timer.mtime !== old_time + 1) $fatal(1, "mtime did not advance");
            if (dut.u_timer.mtimecmp !== (compare_write ?
                    (address == TIMER + 8 ? {old_compare[63:32], store_value} : {store_value, old_compare[31:0]}) :
                    old_compare)) $fatal(1, "mtimecmp write/hold mismatch");
            if (old_time[31:0] == 32'hffff_ffff && dut.u_timer.mtime == old_time + 1) wrapped = 1'b1;
            if (!old_irq && dut.timer_irq) begin
                if (compare_write) $fatal(1, "Spurious IRQ while programming compare");
                irq_rises++;
            end
            if (old_irq && !dut.timer_irq) begin
                if (!compare_write) $fatal(1, "IRQ deasserted without compare write");
                irq_falls++;
            end
            if (expected_irq) begin
                check32("direct trap vector", pc, symbols[TRAP]);
                check32("precise interrupted PC", dut.u_cpu.mepc, interrupted_pc);
                check32("timer cause", dut.u_cpu.mcause, 32'h8000_0007);
                check32("timer tval", dut.u_cpu.mtval, 0);
                check32("trap status", dut.u_cpu.mstatus, 32'h1880);
            end
            if (is_mret) begin
                check32("MRET destination", pc, golden[target_id][31]);
                check32("MRET target status", dut.u_cpu.mstatus,
                        (golden[target_id][32] & ~32'h88) | 32'h80 | (golden[target_id][32][7] ? 32'h8 : 0));
                if (kind == 2) begin
                    irq_returns++;
                    if (source_id == target_id) same_returns++;
                    else irq_switches++;
                    $display("[PASS] tick %0d: thread %0d -> %0d, 31 GPRs and precise PC restored", irqs, source_id, target_id);
                end
                owner = target_id;
                active = 1'b0;
                restoring = 1'b0;
                restores++;
            end
            sp_value = dut.u_cpu.u_regfile.regs[2];
            if (sp_value == symbols[TOP]) stack_live = 1'b1;
            if (stack_live) begin
                if (!(active ? (stack_valid(sp_value, source_id) || stack_valid(sp_value, target_id)) : stack_valid(sp_value, owner)))
                    $fatal(1, "Stack ownership/alignment: sp=%08x owner=%0d", sp_value, owner);
                for (integer id = 0; id < 4; id++)
                    if (stack_valid(sp_value, id) && sp_value < min_sp[id]) min_sp[id] = sp_value;
            end
            if (uart_tx_valid) begin
                $write("%c", uart_tx_data);
                if (uart_tx_data == 8'h0a) begin
                    case (uart_lines)
                        0: check_line("M11.4 START", 0);
                        1: check_line("KERNEL READY", 0);
                        2: check_line("THREAD A RETURN", 1);
                        3: check_line("THREAD B RETURN", 2);
                        4: check_line("TICK PREEMPT PASS", 3);
                        5: check_line("IRQ NEST PASS", 3);
                        6: check_line("STACK GUARD PASS", 3);
                        7: begin check_line("M11.4 PASS", 3); done = 1'b1; end
                        default: $fatal(1, "Unexpected UART line");
                    endcase
                    uart_lines++;
                    uart_line = "";
                end else uart_line = {uart_line, $sformatf("%c", uart_tx_data)};
            end
            if (done) begin
                check32("hardware interrupts", 32'(irqs), 12);
                check32("IRQ returns", 32'(irq_returns), 12);
                check32("same-thread returns", 32'(same_returns), 6);
                check32("IRQ thread switches", 32'(irq_switches), 6);
                check32("software exit switches", 32'(software_switches), 2);
                check32("total restores", 32'(restores), 15);
                check32("C entries", 32'(entries), 3);
                check32("normal kernel exits", 32'(exits), 2);
                check32("C dispatches", 32'(dispatches), 12);
                check32("C returns", 32'(c_returns), 12);
                check32("enter pairs", 32'(enters), 12);
                check32("leave pairs", 32'(leaves), 12);
                check32("kernel tick calls", 32'(increases), 12);
                check32("rearm calls", 32'(rearms), 12);
                check32("deferred requests", 32'(requests), 6);
                check32("thread initializations", 32'(init_calls), 4);
                check32("thread startups", 32'(startup_calls), 4);
                check32("periodic compare values", 32'(periodic_compares), 13);
                check32("safe compare sequences", 32'(compare_sequences), 16);
                check32("IRQ rises", 32'(irq_rises), 12);
                check32("IRQ falls", 32'(irq_falls), 12);
                check32("time seed writes", 32'(time_writes), 2);
                if (!wrapped || compare_phase != 0 || active) $fatal(1, "Missing carry or incomplete transition");
                check32("final tick", ram32(symbols[TICK]), 12);
                check32("stopped tick", ram32(symbols[STOPPED]), 12);
                check32("completed C returns", ram32(symbols[RETURNS]), 2);
                check32("final interrupt nesting", nest_value(), 0);
                check32("no pending switch", ram32(symbols[FLAG]), 0);
                check32("final timer masked", dut.u_cpu.mie, 0);
                check32("final MIE clear", {31'b0, dut.u_cpu.mstatus[3]}, 0);
                check32("data initialized", ram32(symbols[COOKIE]), 32'h1357_9bdf);
                if (dut.u_timer.mtimecmp != 64'hffff_ffff_ffff_ffff) $fatal(1, "Timer not stopped");
                for (integer id = 1; id <= 2; id++) begin
                    if (ram32(symbols[PROGRESS] + 32'((id - 1) * 4)) == 0) $fatal(1, "Worker made no progress");
                    check32("worker checksum", ram32(symbols[SUMS] + 32'((id - 1) * 4)),
                            rom32(symbols[ARGUMENTS] + 32'((id - 1) * 8 + 4)) +
                            ram32(symbols[PROGRESS] + 32'((id - 1) * 4)) +
                            (ram32(symbols[PROGRESS] + 32'((id - 1) * 4)) << (id == 1 ? 1 : 2)));
                end
                for (integer i = 0; i < 4; i++) begin
                    for (integer id = 1; id <= 3; id++)
                        check32("thread guard", ram32(symbols[STACK_A + id - 1] + 32'(i * 4)), 32'ha55a_0000 | 32'(id));
                    check32("main guard", ram32(symbols[GUARD] + 32'(i * 4)), 32'hc0de_cafe);
                end
                for (integer id = 0; id < 4; id++)
                    $display("[PASS] stack %0d observed use: %0d bytes", id, stack_top(id) - min_sp[id]);
                $display("[PASS] 12 real timer IRQs, 6 same-thread returns, 6 preemptions, 64-bit deadline carry");
                $display(" M11.4 SOC RT-THREAD TICK PASS");
                $finish;
            end
            @(negedge clk);
            #1;
        end
        $fatal(1, "Tick timeout: pc=%08x owner=%0d IRQs=%0d", pc, owner, irqs);
    end
endmodule
