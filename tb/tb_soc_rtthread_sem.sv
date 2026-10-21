module tb_soc_rtthread_sem;
    localparam logic [31:0] RAM_BASE = 32'h1000_0000, UART_TX = 32'h2000_0000;
    localparam logic [31:0] TIMER = 32'h3000_0000, MRET = 32'h3020_0073;
    localparam integer TRAP = 0, DISPATCH = 1, RESTORE = 2, SWITCH_TO = 3, SWITCH = 4,
        IRQ_SWITCH = 5, TICK_INIT = 6, REARM = 7, ENTER = 8, LEAVE = 9, INCREASE = 10,
        TICK = 11, CONSUMER = 12, PRODUCER = 13, FINISH = 14, EXIT = 15,
        LOCATIONS = 16, SEM_LOCATIONS = 17, SEM = 18, STACK_A = 19, STACK_B = 20,
        STACK_CHECK = 21, PRODUCED = 22, CONSUMED = 23, RELEASED = 24,
        TIMEOUT_OK = 25, CREDIT_OK = 26, RETURNS = 27, CLEANUP_MASK = 28,
        IDLE_HITS = 29, COOKIE = 30, GUARD = 31, BOTTOM = 32, TOP = 33,
        CURRENT = 34, NEST = 35, FROM = 36, TO = 37, FLAG = 38,
        IDLE_ENTRY = 39, IDLE_STACK = 40, HOOK = 41, CLEANUP = 42,
        SEM_INIT = 43, TAKE = 44, RELEASE = 45, DETACH = 46, DELAY = 47, TIMEOUT = 48;
    logic clk = 1'b0, rst = 1'b1;
    logic [31:0] pc;
    logic uart_tx_valid;
    logic [7:0] uart_tx_data;
    logic [31:0] symbols [0:48];
    // Independent architectural snapshots, not copies read back from saved RAM.
    logic [31:0] golden [1:4][0:35], frames [1:4], min_sp [0:4];
    logic active = 1'b0, restoring = 1'b0, c_called, c_returned;
    logic stack_live = 1'b0, done = 1'b0, expected_irq, is_mret, old_irq, compare_write;
    logic take_pending = 1'b0, take_suspended = 1'b0, release_pending = 1'b0;
    logic [3:2] delay_pending = '0, delay_suspended = '0;
    logic detach_pending = 1'b0;
    logic [31:0] take_return, release_return, detach_return, dispatch_return;
    logic [31:0] enter_return = 0, leave_return = 0, increase_return = 0, request_return = 0;
    logic [31:0] delay_return [2:3], delay_deadline [2:3];
    logic [31:0] interrupted_pc, address, store_value, boot_gp, boot_tp, compare_high;
    logic [63:0] old_time, old_compare, last_sample = 0, deadline = 0, compare_value;
    integer owner = 0, source_id = 0, target_id = 0, kind = 0;
    integer irqs = 0, irq_returns = 0, same_returns = 0, irq_switches = 0;
    integer switches = 0, restores = 0, entries = 0, exits = 0, kernel_resumes = 0;
    integer blocked_takes = 0, blocked_delays = 0, release_preemptions = 0;
    integer take_calls = 0, take_returns = 0, take_successes = 0, take_timeouts = 0;
    integer cancel_checks = 0, release_calls = 0, release_returns = 0;
    integer delay_calls [2:3], delay_returns = 0, detach_calls = 0;
    integer dispatches = 0, dispatch_returns = 0, enters = 0, leaves = 0;
    integer increases = 0, rearms = 0, requests = 0, request_returns = 0;
    integer timeout_calls = 0, irq_timeouts = 0, init_calls = 0;
    integer hook_calls = 0, cleanup_calls = 0, cleanup_seen = 0, callback_id;
    integer compare_phase = 0, compare_sequences = 0, periodic_compares = 0;
    integer irq_rises = 0, irq_falls = 0, uart_lines = 0;
    string image_path = "build/rtthread_sem/rtthread_sem.hex";
    string symbol_path = "build/rtthread_sem/rtthread_sem.symbols.hex";
    string wave_path = "build/rtthread_sem/rtthread_sem.vcd";
    string uart_line = "";

    rv32_soc #(.ROM_BYTES(65536), .RAM_BYTES(65536)) dut (
        .clk (clk), .rst (rst), .pc (pc),
        .uart_tx_valid (uart_tx_valid), .uart_tx_data (uart_tx_data)
    );
    initial forever #50 clk = ~clk; // 10 MHz with Make's 1 ns timescale.

    function automatic logic [31:0] gpr(input integer index);
        if (index < 0 || index > 31) $fatal(1, "Invalid architectural register index");
        return dut.u_cpu.u_regfile.regs[index];
    endfunction
    function automatic logic [31:0] ram32(input logic [31:0] addr);
        if (addr < RAM_BASE || addr >= RAM_BASE + 32'h10000 || addr[1:0] != 0)
            $fatal(1, "Invalid monitored RAM address: %08x", addr);
        return dut.u_ram.mem[(addr - RAM_BASE) >> 2];
    endfunction
    function automatic logic [31:0] ram8(input logic [31:0] addr);
        return (ram32(addr & ~32'h3) >> (8 * int'(addr[1:0]))) & 32'hff;
    endfunction
    function automatic logic [31:0] field(input integer id, input integer group);
        return ram32(symbols[LOCATIONS] + 32'((group * 4 + id - 1) * 4));
    endfunction
    function automatic logic [31:0] state(input integer id);
        return ram8(field(id, 2)) & 7;
    endfunction
    function automatic logic [31:0] timer_active(input integer id);
        return ram8(field(id, 6)) & 1;
    endfunction
    function automatic logic [31:0] nest_value();
        return ram8(symbols[NEST]);
    endfunction
    function automatic logic [31:0] sem_value();
        logic [31:0] addr;
        addr = ram32(symbols[SEM_LOCATIONS]);
        return (ram32(addr & ~32'h3) >> (8 * int'(addr[1:0]))) & 32'hffff;
    endfunction
    function automatic integer wake_target(input integer tick_number);
        case (tick_number)
            2, 4, 6: return 2;
            8: return 1;
            12: return 3;
            default: return 4;
        endcase
    endfunction
    function automatic logic [31:0] take_wait(input integer number);
        case (number)
            2: return 32'hffff_ffff;
            3, 4: return 5;
            5: return 2;
            default: return 0;
        endcase
    endfunction
    function automatic logic [31:0] take_start(input integer number);
        if (number <= 2) return 0;
        if (number <= 5) return 32'((number - 2) * 2);
        return 8;
    endfunction
    function automatic logic [31:0] take_end(input integer number);
        return number <= 5 ? 32'((number - 1) * 2) : 8;
    endfunction
    function automatic logic [31:0] stack_top(input integer id);
        if (id == 0) return symbols[TOP];
        if (id == 4) return symbols[IDLE_STACK] + 32'd1024;
        return symbols[STACK_A + id - 1] + 32'd2048;
    endfunction
    function automatic logic stack_valid(input logic [31:0] value, input integer id);
        logic [31:0] bottom;
        bottom = id == 0 ? symbols[BOTTOM] : (id == 4 ? symbols[IDLE_STACK] : symbols[STACK_A + id - 1]) + 16;
        return value >= bottom && value <= stack_top(id) && value[3:0] == 0;
    endfunction
    task automatic check32(input string name, input logic [31:0] actual, input logic [31:0] expected);
        if (actual !== expected)
            $fatal(1, "%s: got=%08x expected=%08x pc=%08x owner=%0d tick=%0d take=%0d release=%0d",
                   name, actual, expected, pc, owner, irqs, take_calls, release_calls);
    endtask
    task automatic queue_check(input integer waiter);
        logic [31:0] head, node;
        head = ram32(symbols[SEM_LOCATIONS] + 4);
        node = waiter == 0 ? head : field(waiter, 5);
        check32("semaphore wait-list next", ram32(head), node);
        check32("semaphore wait-list previous", ram32(head + 4), node);
        if (waiter != 0) begin
            check32("waiter next", ram32(node), head);
            check32("waiter previous", ram32(node + 4), head);
        end
    endtask
    task automatic timer_removed(input integer id);
        check32("timer inactive", timer_active(id), 0);
        check32("timer row unlinked next", ram32(field(id, 7)), field(id, 7));
        check32("timer row unlinked previous", ram32(field(id, 7) + 4), field(id, 7));
    endtask
    task automatic check_frame(input integer id);
        for (integer i = 0; i < 36; i++)
            check32($sformatf("thread %0d frame field %0d", id, i), ram32(frames[id] + 32'(i * 4)), golden[id][i]);
    endtask
    task automatic begin_transition(input integer transition_kind);
        if (active) $fatal(1, "Nested context transition");
        active = 1'b1;
        restoring = 1'b0;
        c_called = 1'b0;
        c_returned = 1'b0;
        kind = transition_kind;
        source_id = owner;
        if (kind != 0) begin
            frames[owner] = gpr(2) - 144;
            if (!stack_valid(frames[owner], owner)) $fatal(1, "Frame exceeds source stack");
            for (integer reg_num = 1; reg_num < 32; reg_num++) golden[owner][reg_num - 1] = gpr(reg_num);
            golden[owner][31] = kind == 2 ? pc : gpr(1);
            golden[owner][32] = kind == 2 ? 32'h1880 : dut.u_cpu.mstatus & ~32'h88;
            for (integer i = 33; i < 36; i++) golden[owner][i] = 0;
        end
    endtask
    task automatic check_line(input string expected, input integer expected_owner);
        if (uart_line != expected) $fatal(1, "UART line %0d: got='%s' expected='%s'", uart_lines, uart_line, expected);
        check32("UART thread", 32'(owner), 32'(expected_owner));
    endtask

    initial begin
        if ($value$plusargs("image=%s", image_path)) begin end
        if ($value$plusargs("symbols=%s", symbol_path)) begin end
        if ($value$plusargs("wave=%s", wave_path)) begin end
        $dumpfile(wave_path);
        $dumpvars(0, tb_soc_rtthread_sem);
        for (integer i = 0; i < 16384; i++) dut.u_ram.mem[i] = 32'hfeed_0000 ^ 32'(i);
        #1;
        $readmemh(image_path, dut.u_rom.mem);
        $readmemh(symbol_path, symbols);
        $display("[RUN] %s", image_path);
        check32("consumer stack placement", symbols[STACK_A], 32'h1000_8000);
        check32("producer stack placement", symbols[STACK_B], 32'h1000_9000);
        check32("checker stack placement", symbols[STACK_CHECK], 32'h1000_a000);
        for (integer id = 0; id < 5; id++) min_sp[id] = stack_top(id);
        for (integer id = 2; id <= 3; id++) begin delay_calls[id] = 0; delay_return[id] = 0; end
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
            if (pc[1:0] != 0 || pc >= 32'h10000) $fatal(1, "Invalid PC");
            check32("MTIP follows hardware timer", dut.u_cpu.mip, old_irq ? 32'h80 : 0);
            check32("only real enabled timer traps", {31'b0, dut.u_cpu.trap_enter}, {31'b0, expected_irq});
            if (dut.mem_we && !(address >= RAM_BASE && address < RAM_BASE + 32'h10000) && address != UART_TX && !compare_write)
                $fatal(1, "Unexpected store or mtime reset: %08x", address);
            if (!expected_irq && pc == symbols[TICK_INIT]) check32("tick initialization on main", 32'(owner), 0);

            if (!expected_irq && pc == symbols[SEM_INIT]) begin
                check32("static semaphore initialization on main", 32'(owner), 0);
                check32("init semaphore address", gpr(10), symbols[SEM]);
                check32("initial count zero", gpr(12), 0);
                check32("priority wait policy", gpr(13), 1);
                init_calls++;
            end
            if (!expected_irq && take_pending && pc == take_return) begin
                check32("take returns on consumer", 32'(owner), 1);
                check32("take return status", gpr(10), (take_calls == 1 || take_calls == 5 || take_calls == 7) ? 32'hffff_fffe : 0);
                check32("take return tick", ram32(symbols[TICK]), take_end(take_calls));
                check32("take restored MIE", dut.u_cpu.mstatus, 32'h1888);
                if (take_suspended != (take_wait(take_calls) != 0)) $fatal(1, "Wrong blocking behavior");
                queue_check(0);
                check32("take consumes notification", sem_value(), 0);
                timer_removed(1);
                if (take_calls >= 2 && take_calls <= 4) begin
                    if (!release_pending) $fatal(1, "Producer release returned before consumer ran");
                    check32("produced before handoff", ram32(symbols[PRODUCED]), 32'(take_calls - 1));
                    check32("release still pending", ram32(symbols[RELEASED]), 32'(take_calls - 2));
                    if (take_calls >= 3) cancel_checks++;
                end
                if (take_calls == 1 || take_calls == 5 || take_calls == 7) take_timeouts++;
                else take_successes++;
                take_pending = 1'b0;
                take_returns++;
            end
            if (!expected_irq && pc == symbols[TAKE]) begin
                if (active || take_pending || take_calls >= 7) $fatal(1, "Unexpected semaphore take");
                take_calls++;
                check32("take caller", 32'(owner), 1);
                check32("take object", gpr(10), symbols[SEM]);
                check32("take wait mode", gpr(11), take_wait(take_calls));
                check32("take starts on expected tick", ram32(symbols[TICK]), take_start(take_calls));
                check32("take initial count", sem_value(), take_calls == 6 ? 1 : 0);
                queue_check(0);
                take_pending = 1'b1;
                take_suspended = 1'b0;
                take_return = gpr(1);
            end
            if (!expected_irq && release_pending && pc == release_return) begin
                check32("release result", gpr(10), 0);
                check32("release return MIE", dut.u_cpu.mstatus, 32'h1888);
                if (release_calls <= 3) begin
                    check32("release returns to producer", 32'(owner), 2);
                    check32("consumer already consumed", ram32(symbols[CONSUMED]), 32'(release_calls));
                    check32("producer counter not yet updated", ram32(symbols[RELEASED]), 32'(release_calls - 1));
                    if (!take_pending || !take_suspended) $fatal(1, "Consumer did not block again before producer resumed");
                    queue_check(1);
                    check32("handoff leaves count zero", sem_value(), 0);
                end else begin
                    check32("credit release caller", 32'(owner), 1);
                    queue_check(0);
                    check32("release without waiter saves one credit", sem_value(), 1);
                end
                release_pending = 1'b0;
                release_returns++;
            end
            if (!expected_irq && pc == symbols[RELEASE]) begin
                if (active || release_pending || release_calls >= 4) $fatal(1, "Unexpected semaphore release");
                release_calls++;
                check32("release caller", 32'(owner), release_calls <= 3 ? 2 : 1);
                check32("release object", gpr(10), symbols[SEM]);
                check32("release tick", ram32(symbols[TICK]), release_calls <= 3 ? 32'(release_calls * 2) : 8);
                check32("release starts with zero count", sem_value(), 0);
                queue_check(release_calls <= 3 ? 1 : 0);
                if (release_calls <= 3) check32("finite wait timer armed", timer_active(1), release_calls == 1 ? 0 : 1);
                release_pending = 1'b1;
                release_return = gpr(1);
            end
            for (integer id = 2; id <= 3; id++) begin
                if (!expected_irq && delay_pending[id] && owner == id && pc == delay_return[id]) begin
                    if (!delay_suspended[id]) $fatal(1, "Delay returned without blocking");
                    check32("delay result", gpr(10), 0);
                    check32("delay wake tick", ram32(symbols[TICK]), delay_deadline[id]);
                    check32("delay restored MIE", dut.u_cpu.mstatus, 32'h1888);
                    timer_removed(id);
                    delay_pending[id] = 1'b0;
                    delay_returns++;
                end
            end
            if (!expected_irq && pc == symbols[DELAY]) begin
                if (owner < 2 || owner > 3 || delay_pending[owner] || active) $fatal(1, "Unexpected delay");
                check32("delay period", gpr(10), owner == 2 ? 2 : 12);
                check32("delay start", ram32(symbols[TICK]), owner == 2 ? 32'(delay_calls[2] * 2) : 0);
                delay_return[owner] = gpr(1);
                delay_deadline[owner] = ram32(symbols[TICK]) + gpr(10);
                delay_pending[owner] = 1'b1;
                delay_suspended[owner] = 1'b0;
                delay_calls[owner]++;
            end
            if (!expected_irq && pc == symbols[DETACH]) begin
                check32("detach by checker", 32'(owner), 3);
                check32("detach object", gpr(10), symbols[SEM]);
                queue_check(0);
                check32("detach starts with static semaphore", ram8(ram32(symbols[SEM_LOCATIONS] + 8)), 32'h82);
                detach_return = gpr(1);
                detach_pending = 1'b1;
                detach_calls++;
            end
            if (detach_pending && pc == detach_return) begin
                check32("detach result", gpr(10), 0);
                check32("detach clears object type", ram8(ram32(symbols[SEM_LOCATIONS] + 8)), 0);
                detach_pending = 1'b0;
            end
            if (!expected_irq && pc == symbols[HOOK]) begin
                check32("hook on idle", 32'(owner), 4);
                hook_calls++;
            end
            if (!expected_irq && pc == symbols[CLEANUP]) begin
                callback_id = cleanup_calls == 0 ? 2 : 1;
                check32("cleanup by idle", 32'(owner), 4);
                check32("cleanup thread", gpr(10), field(callback_id, 1));
                check32("closed thread", state(callback_id), 4);
                check32("detached thread object", ram8(field(callback_id, 4)), 0);
                cleanup_seen |= 1 << (callback_id - 1);
                cleanup_calls++;
            end

            if (expected_irq) begin
                check32("timer interrupts idle", 32'(owner), 4);
                check32("pre-trap status", dut.u_cpu.mstatus, 32'h1888);
                check32("trap cancels writes", {29'b0, dut.u_cpu.rf_we, dut.u_cpu.csr_we, dut.mem_we}, 0);
                begin_transition(2);
                irqs++;
                if (irqs > 12) $fatal(1, "Extra timer interrupt");
                irq_timeouts = 0;
                interrupted_pc = pc;
                target_id = wake_target(irqs);
                check32("no stale IRQ switch", ram32(symbols[FLAG]), 0);
            end
            if (!expected_irq && (pc == symbols[SWITCH_TO] || pc == symbols[SWITCH])) begin
                begin_transition(pc == symbols[SWITCH_TO] ? 0 : 1);
                if (kind == 0) begin
                    check32("start on main", 32'(owner), 0);
                    boot_gp = gpr(3); boot_tp = gpr(4);
                    for (integer id = 1; id <= 4; id++) begin
                        frames[id] = stack_top(id) - 144;
                        for (integer i = 0; i < 36; i++) golden[id][i] = 0;
                        golden[id][0] = symbols[EXIT]; golden[id][1] = stack_top(id);
                        golden[id][2] = boot_gp; golden[id][3] = boot_tp;
                        golden[id][9] = id == 4 ? 0 : field(id, 1);
                        golden[id][31] = id == 1 ? symbols[CONSUMER] : (id == 2 ? symbols[PRODUCER] : (id == 3 ? symbols[FINISH] : symbols[IDLE_ENTRY]));
                        golden[id][32] = 32'h1880;
                    end
                    target_id = 1;
                    check32("initial sp field", gpr(10), field(1, 0));
                end else begin
                    check32("from sp field", gpr(10), field(owner, 0));
                    if (state(owner) == 2) begin
                        if (owner == 1) begin
                            if (!take_pending || take_wait(take_calls) == 0) $fatal(1, "Consumer suspended outside a blocking take");
                            queue_check(1);
                            check32("wait timer mode", timer_active(1), take_calls == 2 ? 0 : 1);
                            if (take_calls != 2) check32("wait deadline", ram32(field(1, 3)), take_start(take_calls) + take_wait(take_calls));
                            take_suspended = 1'b1;
                            blocked_takes++;
                            target_id = 2;
                        end else begin
                            if (owner > 3 || !delay_pending[owner]) $fatal(1, "Suspend outside delay");
                            check32("sleep timer deadline", ram32(field(owner, 3)), delay_deadline[owner]);
                            delay_suspended[owner] = 1'b1;
                            blocked_delays++;
                            target_id = owner == 2 && irqs == 0 ? 3 : 4;
                        end
                    end else if (state(owner) == 1) begin
                        check32("producer preempted by release", 32'(owner), 2);
                        if (!release_pending) $fatal(1, "Preemption outside release");
                        queue_check(0);
                        timer_removed(1);
                        release_preemptions++;
                        target_id = 1;
                    end else begin
                        check32("exit source closed", state(owner), 4);
                        target_id = 4;
                    end
                    check32("to sp field", gpr(11), field(target_id, 0));
                    switches++;
                end
                check32("kernel selected target", ram32(symbols[CURRENT]), field(target_id, 1));
            end
            if (active && !expected_irq) check32("MIE clear during switch/ISR", {31'b0, dut.u_cpu.mstatus[3]}, 0);
            if (pc == symbols[DISPATCH]) begin
                if (!active || kind != 2 || c_called) $fatal(1, "Unexpected dispatcher");
                check_frame(source_id);
                check32("dispatcher frame", gpr(10), frames[source_id]);
                check32("dispatcher cause", gpr(11), 32'h8000_0007);
                check32("dispatcher tval", gpr(12), 0);
                dispatch_return = gpr(1);
                c_called = 1'b1;
                dispatches++;
            end
            if (active && kind == 2) begin
                if (pc == symbols[ENTER]) begin check32("nest before enter", nest_value(), 0); enter_return = gpr(1); end
                if (pc == enter_return) begin check32("nest after enter", nest_value(), 1); enter_return = 0; enters++; end
                if (pc == symbols[LEAVE]) begin check32("nest before leave", nest_value(), 1); leave_return = gpr(1); end
                if (pc == leave_return) begin check32("nest after leave", nest_value(), 0); leave_return = 0; leaves++; end
                if (pc == symbols[INCREASE]) begin
                    check32("kernel tick before", ram32(symbols[TICK]), 32'(irqs - 1));
                    increase_return = gpr(1);
                end
                if (pc == increase_return) begin check32("kernel tick after", ram32(symbols[TICK]), 32'(irqs)); increase_return = 0; increases++; end
                if (pc == symbols[REARM]) begin check32("rearm in IRQ", nest_value(), 1); rearms++; end
                if (pc == symbols[TIMEOUT]) begin
                    if (wake_target(irqs) == 4 || irq_timeouts != 0) $fatal(1, "Unexpected or stale timeout");
                    check32("timeout target", gpr(10), field(target_id, 1));
                    check32("timeout suspended thread", state(target_id), 2);
                    check32("timeout exact deadline", ram32(field(target_id, 3)), 32'(irqs));
                    if (target_id == 1) queue_check(1);
                    timeout_calls++; irq_timeouts++;
                end
                if (pc == symbols[IRQ_SWITCH]) begin
                    if (wake_target(irqs) == 4) $fatal(1, "Unexpected IRQ switch");
                    check32("IRQ request source", gpr(10), field(4, 0));
                    check32("IRQ request target", gpr(11), field(target_id, 0));
                    request_return = gpr(1); requests++;
                end
                if (request_return != 0 && pc == request_return) begin
                    check32("request flag set", ram32(symbols[FLAG]), 1);
                    check32("recorded source", ram32(symbols[FROM]), field(4, 0));
                    check32("recorded target", ram32(symbols[TO]), field(target_id, 0));
                    request_return = 0; request_returns++;
                end
                if (c_called && !c_returned && pc == dispatch_return) begin
                    check32("timeout callbacks per IRQ", 32'(irq_timeouts), target_id == 4 ? 0 : 1);
                    check32("selected frame returned", gpr(10), frames[target_id]);
                    check32("C returns on source stack", gpr(2), frames[source_id]);
                    check32("IRQ request consumed", ram32(symbols[FLAG]), 0);
                    check32("IRQ nesting clear", nest_value(), 0);
                    if (target_id != 4) check32("interrupted idle saved", ram32(field(4, 0)), frames[4]);
                    c_returned = 1'b1; dispatch_returns++;
                end
            end
            if (pc == symbols[RESTORE]) begin
                if (!active || (kind == 2 && !c_returned)) $fatal(1, "Early restore");
                if (kind == 1) begin check_frame(source_id); check32("source sp saved", ram32(field(source_id, 0)), frames[source_id]); end
                check_frame(target_id);
                check32("restore selected SP", gpr(2), frames[target_id]);
                restoring = 1'b1;
            end
            if (is_mret) begin
                if (!active || !restoring) $fatal(1, "Untracked MRET");
                for (integer n = 1; n < 32; n++) check32($sformatf("restored x%0d", n), gpr(n), golden[target_id][n - 1]);
                check32("restored mepc", dut.u_cpu.mepc, golden[target_id][31]);
                check32("restored mstatus", dut.u_cpu.mstatus, golden[target_id][32] & ~32'h8);
                check32("timer deasserted before MRET", {31'b0, dut.timer_irq}, 0);
            end
            if (!expected_irq && (pc == symbols[CONSUMER] || pc == symbols[PRODUCER] || pc == symbols[FINISH] || pc == symbols[IDLE_ENTRY])) begin
                check32("C entry order", 32'(owner), 32'(entries + 1));
                check32("C entry SP", gpr(2), stack_top(owner));
                check32("C entry parameter", gpr(10), owner == 4 ? 0 : field(owner, 1));
                entries++;
            end
            if (!expected_irq && pc == symbols[EXIT]) begin
                check32("worker exit order", 32'(owner), exits == 0 ? 2 : 1);
                check32("worker exit tick", ram32(symbols[TICK]), exits == 0 ? 6 : 8);
                check32("C return balances stack", gpr(2), stack_top(owner));
                check32("C completed", ram32(symbols[RETURNS]), 32'(exits + 1));
                exits++;
            end

            if (!expected_irq && dut.instr[6:0] == 7'h03 && address == TIMER) last_sample = old_time;
            if (compare_write) begin
                check32("compare word strobe", {28'b0, dut.mem_wstrb}, 15);
                if (compare_phase == 0) begin
                    check32("compare starts low", address, TIMER + 8); check32("safe low=-1", store_value, 32'hffff_ffff);
                end else if (compare_phase == 1) begin
                    check32("compare high", address, TIMER + 12); compare_high = store_value;
                end else begin
                    check32("compare final low", address, TIMER + 8); compare_value = {compare_high, store_value};
                    if (compare_value != 64'hffff_ffff_ffff_ffff) begin
                        if (compare_value !== (periodic_compares == 0 ? last_sample + 10000 : deadline + 10000) || compare_value <= old_time)
                            $fatal(1, "Timer deadline drift/overrun");
                        deadline = compare_value; periodic_compares++;
                    end
                    compare_sequences++;
                end
                compare_phase = (compare_phase + 1) % 3;
            end

            @(posedge clk);
            #1;
            if (dut.u_timer.mtime !== old_time + 1) $fatal(1, "mtime stopped or reset");
            if (dut.u_timer.mtimecmp !== (compare_write ? (address == TIMER + 8 ? {old_compare[63:32], store_value} : {store_value, old_compare[31:0]}) : old_compare))
                $fatal(1, "mtimecmp update/hold mismatch");
            if (!old_irq && dut.timer_irq) begin if (compare_write) $fatal(1, "Spurious IRQ"); irq_rises++; end
            if (old_irq && !dut.timer_irq) begin if (!compare_write) $fatal(1, "IRQ unexpectedly cleared"); irq_falls++; end
            if (expected_irq) begin
                check32("trap vector", pc, symbols[TRAP]); check32("precise trap PC", dut.u_cpu.mepc, interrupted_pc);
                check32("trap status", dut.u_cpu.mstatus, 32'h1880); check32("timer cause", dut.u_cpu.mcause, 32'h8000_0007);
                check32("timer tval", dut.u_cpu.mtval, 0);
            end
            if (is_mret) begin
                check32("MRET PC", pc, golden[target_id][31]);
                check32("MRET status", dut.u_cpu.mstatus, (golden[target_id][32] & ~32'h88) | 32'h80 | (golden[target_id][32][7] ? 32'h8 : 0));
                if (!golden[target_id][32][7]) kernel_resumes++;
                if (kind == 2) begin irq_returns++; if (source_id == target_id) same_returns++; else irq_switches++; end
                restores++; owner = target_id; active = 1'b0; restoring = 1'b0;
            end
            if (gpr(2) == symbols[TOP]) stack_live = 1'b1;
            if (stack_live) begin
                if (!(active ? (stack_valid(gpr(2), source_id) || stack_valid(gpr(2), target_id)) : stack_valid(gpr(2), owner)))
                    $fatal(1, "Stack ownership/alignment: %08x", gpr(2));
                for (integer id = 0; id < 5; id++) if (stack_valid(gpr(2), id) && gpr(2) < min_sp[id]) min_sp[id] = gpr(2);
            end
            if (uart_tx_valid) begin
                $write("%c", uart_tx_data);
                if (uart_tx_data == 8'h0a) begin
                    case (uart_lines)
                        0: check_line("M11.6 START", 0);
                        1: check_line("KERNEL READY", 0);
                        2: check_line("SEM EMPTY PASS", 1);
                        3, 5, 7: check_line($sformatf("CONSUME %0d", (uart_lines - 1) / 2), 1);
                        4, 6, 8: check_line($sformatf("RELEASE RETURN %0d", (uart_lines - 2) / 2), 2);
                        9: check_line("SEM TIMEOUT PASS", 1);
                        10: check_line("SEM COUNT PASS", 1);
                        11: check_line("SEM SYNC PASS", 3);
                        12: check_line("IDLE CLEANUP PASS", 3);
                        13: check_line("STACK GUARD PASS", 3);
                        14: begin check_line("M11.6 PASS", 3); done = 1'b1; end
                        default: $fatal(1, "Unexpected UART line");
                    endcase
                    uart_lines++; uart_line = "";
                end else uart_line = {uart_line, $sformatf("%c", uart_tx_data)};
            end
            if (done) begin
                check32("take calls", 32'(take_calls), 7); check32("take returns", 32'(take_returns), 7);
                check32("successful takes", 32'(take_successes), 4); check32("timeout results", 32'(take_timeouts), 3);
                check32("finite waits canceled", 32'(cancel_checks), 2); check32("blocking takes", 32'(blocked_takes), 4);
                check32("release calls", 32'(release_calls), 4); check32("release returns", 32'(release_returns), 4);
                check32("immediate release preemptions", 32'(release_preemptions), 3);
                check32("producer delays", 32'(delay_calls[2]), 3); check32("checker delay", 32'(delay_calls[3]), 1);
                check32("delay returns", 32'(delay_returns), 4); check32("blocked delays", 32'(blocked_delays), 4);
                check32("semaphore init", 32'(init_calls), 1); check32("semaphore detach", 32'(detach_calls), 1);
                check32("IRQs", 32'(irqs), 12); check32("IRQ returns", 32'(irq_returns), 12);
                check32("same-thread IRQ returns", 32'(same_returns), 7); check32("timeout switches", 32'(irq_switches), 5);
                check32("thread-mode switches", 32'(switches), 13); check32("all context restores", 32'(restores), 26);
                check32("kernel critical-section resumes", 32'(kernel_resumes), 11);
                check32("C entries", 32'(entries), 4); check32("worker exits", 32'(exits), 2);
                check32("dispatch calls", 32'(dispatches), 12); check32("dispatch returns", 32'(dispatch_returns), 12);
                check32("enter/leave pairs", 32'(enters), 12); check32("leave pairs", 32'(leaves), 12);
                check32("kernel tick calls", 32'(increases), 12); check32("rearms", 32'(rearms), 12);
                check32("timeout callbacks, no stale waits", 32'(timeout_calls), 5);
                check32("IRQ requests", 32'(requests), 5); check32("recorded IRQ requests", 32'(request_returns), 5);
                check32("cleanup callbacks", 32'(cleanup_calls), 2); check32("cleanup coverage", 32'(cleanup_seen), 3);
                check32("safe compare sequences", 32'(compare_sequences), 15); check32("periodic deadlines", 32'(periodic_compares), 13);
                check32("IRQ rises", 32'(irq_rises), 12); check32("IRQ falls", 32'(irq_falls), 12);
                check32("produced", ram32(symbols[PRODUCED]), 3); check32("consumed", ram32(symbols[CONSUMED]), 3);
                check32("release completions", ram32(symbols[RELEASED]), 3);
                check32("timeout check", ram32(symbols[TIMEOUT_OK]), 1); check32("credit check", ram32(symbols[CREDIT_OK]), 1);
                check32("worker returns", ram32(symbols[RETURNS]), 2); check32("C cleanup mask", ram32(symbols[CLEANUP_MASK]), 3);
                check32("final tick", ram32(symbols[TICK]), 12); check32("final nesting", nest_value(), 0);
                check32("final pending switch", ram32(symbols[FLAG]), 0); check32("final MTIE", dut.u_cpu.mie, 0);
                check32("final MIE", {31'b0, dut.u_cpu.mstatus[3]}, 0); check32("data initialized", ram32(symbols[COOKIE]), 32'h1357_9bdf);
                if (active || take_pending || release_pending || detach_pending || delay_pending != 0 || compare_phase != 0 || hook_calls == 0 || ram32(symbols[IDLE_HITS]) == 0)
                    $fatal(1, "Unfinished API/restore or idle never ran");
                if (dut.u_timer.mtimecmp != 64'hffff_ffff_ffff_ffff) $fatal(1, "Timer not stopped");
                for (integer i = 0; i < 4; i++) begin
                    for (integer id = 1; id <= 3; id++) check32("thread guard", ram32(symbols[STACK_A + id - 1] + 32'(i * 4)), 32'ha55a_0000 | 32'(id));
                    check32("main guard", ram32(symbols[GUARD] + 32'(i * 4)), 32'hc0de_cafe);
                    check32("idle bottom unused", ram32(symbols[IDLE_STACK] + 32'(i * 4)), 32'h2323_2323);
                end
                for (integer id = 0; id < 5; id++) $display("[PASS] stack %0d observed use: %0d bytes", id, stack_top(id) - min_sp[id]);
                $display("[PASS] 3 immediate handoffs, 2 canceled waits, real timeout, credit consumption and static detach");
                $display("[PASS] 12 real IRQs, 26 complete context restores, idle cleaned both workers");
                $display(" M11.6 SOC RT-THREAD SEMAPHORE PASS");
                $finish;
            end
            @(negedge clk);
            #1;
        end
        $fatal(1, "Semaphore timeout: pc=%08x tick=%0d owner=%0d", pc, irqs, owner);
    end
endmodule
