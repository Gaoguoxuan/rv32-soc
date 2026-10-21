module tb_soc_rtthread_demo;
    localparam logic [31:0] RAM_BASE = 32'h1000_0000, UART_TX = 32'h2000_0000;
    localparam logic [31:0] TIMER = 32'h3000_0000, MRET = 32'h3020_0073;
    localparam integer TRAP = 0, DISPATCH = 1, RESTORE = 2, SWITCH_TO = 3, SWITCH = 4,
        IRQ_SWITCH = 5, TICK_INIT = 6, REARM = 7, ENTER = 8, LEAVE = 9, INCREASE = 10,
        TICK = 11, CONSUMER = 12, PRODUCER = 13, HEARTBEAT = 14, EXIT = 15,
        LOCATIONS = 16, MUTEX_LOCATIONS = 17, LOCK = 18, STACK_A = 19, STACK_B = 20,
        STACK_CHECK = 21, PRODUCED = 22, CONSUMED = 23, HEARTBEATS = 24, SLOT = 25,
        SEM_LOCATIONS = 26, EMPTY = 27, FULL = 28, IDLE_HITS = 29, COOKIE = 30,
        GUARD = 31, BOTTOM = 32, TOP = 33, CURRENT = 34, NEST = 35, FROM = 36,
        TO = 37, FLAG = 38, IDLE_ENTRY = 39, IDLE_STACK = 40, HOOK = 41,
        PRINT = 42, SEM_INIT = 43, TAKE = 44, RELEASE = 45, MUTEX_INIT = 46,
        LOCK_TAKE = 47, LOCK_RELEASE = 48, DELAY = 49, TIMEOUT = 50, FAIL = 51,
        OUTPUT = 52, SUSPEND = 53, RESUME = 54;
    logic clk = 1'b0, rst = 1'b1;
    logic [31:0] pc;
    logic uart_tx_valid;
    logic [7:0] uart_tx_data;
    logic [31:0] symbols [0:54];
    // Expected runnable threads are driven by API calls and expiry events.
    logic ready [1:4];
    integer priorities [1:4], base_priority [1:4];
    logic [31:0] golden [1:4][0:35], frames [1:4], min_sp [0:4];
    logic active = 1'b0, restoring = 1'b0, c_called, c_returned, stack_live = 1'b0;
    logic expected_irq, is_mret, old_irq, compare_write;
    logic [2:1] take_pending = '0, release_pending = '0;
    logic [3:1] lock_take_pending = '0, lock_release_pending = '0, lock_waiters = '0;
    logic [3:1] delay_pending = '0, delay_expired = '0;
    logic [3:1] block_requested = '0;
    logic [31:0] take_return [1:2], release_return [1:2];
    logic [31:0] lock_take_return [1:3], lock_release_return [1:3];
    logic [31:0] delay_return [1:3], delay_deadline [1:3], delay_pointer [1:3];
    logic [31:0] dispatch_return, interrupted_pc, boot_gp, boot_tp, address, store_value, compare_high;
    logic [31:0] enter_return = 0, leave_return = 0, increase_return = 0, request_return = 0;
    logic [31:0] print_return;
    logic print_active = 1'b0, boot_ready = 1'b0, version_seen = 1'b0;
    logic empty_owned = 1'b0, full_owned = 1'b0, slot_available = 1'b0;
    logic [63:0] old_time, old_compare, last_sample = 0, deadline = 0, compare_value;
    integer owner = 0, source_id = 0, target_id = 0, kind = 0, lock_owner = 0;
    integer tokens [0:1], waiters [0:1], sem_takes [1:2], sem_releases [1:2];
    integer take_returns [1:2], release_returns [1:2], lock_takes [1:3], lock_releases [1:3];
    integer delay_calls [1:3], delay_returns [1:3], entries [1:4];
    integer irqs = 0, irq_returns = 0, same_returns = 0, irq_switches = 0;
    integer switches = 0, restores = 0, kernel_resumes = 0, hook_calls = 0, pending_mrets = 0;
    integer dispatches = 0, dispatch_returns = 0, enters = 0, leaves = 0, increases = 0, rearms = 0;
    integer requests = 0, request_returns = 0, timeout_calls = 0, irq_timeouts = 0, expected_timeouts;
    integer irq_current, irq_requests = 0, shared_expiries = 0, shared_requests = 0;
    integer sem_inits = 0, mutex_inits = 0, tick_inits = 0;
    integer compare_phase = 0, compare_sequences = 0, periodic_compares = 0, irq_rises = 0, irq_falls = 0;
    integer published = 0, received = 0, sequence_stores = 0, value_stores = 0;
    integer sample_lines = 0, heartbeat_lines = 0, print_owner, callback_id, sem_id, next_owner;
    integer unsigned run_ticks = 205, expected_samples, expected_heartbeats;
    logic [31:0] line_sequence, line_value, line_tick, line_produced, line_consumed, line_idle;
    string image_path = "build/rtthread_demo/rtthread_demo.hex";
    string symbol_path = "build/rtthread_demo/rtthread_demo.symbols.hex";
    string wave_path, uart_line = "";

    rv32_soc #(.ROM_BYTES(65536), .RAM_BYTES(65536)) dut (
        .clk (clk), .rst (rst), .pc (pc),
        .uart_tx_valid (uart_tx_valid), .uart_tx_data (uart_tx_data),
        .uart_rx_valid (1'b0),
        .uart_rx_data  (8'b0),
        .uart_rx_ready ()
    );
    initial forever #50 clk = ~clk; // 10 MHz.

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
    function automatic logic [31:0] mutex_field(input integer index);
        return ram32(symbols[MUTEX_LOCATIONS] + 32'(index * 4));
    endfunction
    function automatic logic [31:0] mutex_value();
        logic [31:0] addr;
        addr = mutex_field(0);
        return (ram32(addr & ~32'h3) >> (8 * int'(addr[1:0]))) & 32'hffff;
    endfunction
    function automatic logic [31:0] priority_of(input integer id);
        return ram8(field(id, 8));
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
                   name, actual, expected, pc, owner, irqs, sem_takes[1] + sem_takes[2], sem_releases[1] + sem_releases[2]);
    endtask
    task automatic queue_check(input integer waiter);
        logic [31:0] head, node;
        head = mutex_field(4);
        node = waiter == 0 ? head : field(waiter, 5);
        check32("mutex wait-list next", ram32(head), node);
        check32("mutex wait-list previous", ram32(head + 4), node);
        if (waiter != 0) begin
            check32("waiter next", ram32(node), head);
            check32("waiter previous", ram32(node + 4), head);
        end
    endtask
    task automatic lock_check(input integer holder, input logic [31:0] value,
                              input logic [31:0] hold_count, input logic [31:0] original);
        check32("mutex owner", ram32(mutex_field(1)), holder == 0 ? 0 : field(holder, 1));
        check32("mutex value", mutex_value(), value);
        check32("recursive hold count", ram8(mutex_field(2)), hold_count);
        check32("saved owner priority", ram8(mutex_field(3)), original);
    endtask
    task automatic priority_check(input integer id, input logic [31:0] priority_value);
        check32("thread priority", priority_of(id), priority_value);
        check32("priority mask", ram32(field(id, 9)), 32'h1 << priority_value);
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
    function automatic logic [31:0] sem_field(input integer number, input integer index);
        return ram32(symbols[SEM_LOCATIONS] + 32'((number * 4 + index) * 4));
    endfunction
    function automatic logic [31:0] sem_value(input integer number);
        logic [31:0] addr;
        addr = sem_field(number, 0);
        return (ram32(addr & ~32'h3) >> (8 * int'(addr[1:0]))) & 32'hffff;
    endfunction
    function automatic integer thread_id(input logic [31:0] thread_addr);
        for (integer id = 1; id <= 4; id++) if (thread_addr == field(id, 1)) return id;
        $fatal(1, "Unknown thread pointer %08x", thread_addr);
        return 0;
    endfunction
    function automatic integer best_ready();
        integer best;
        best = 4;
        for (integer id = 1; id <= 3; id++)
            if (ready[id] && priorities[id] < priorities[best]) best = id;
        return best;
    endfunction
    function automatic logic contains(input string line_text, input string fragment);
        for (integer i = 0; i + fragment.len() <= line_text.len(); i++)
            if (line_text.substr(i, i + fragment.len() - 1) == fragment) return 1'b1;
        return 1'b0;
    endfunction
    task automatic sem_queue_check(input integer number, input integer waiter);
        logic [31:0] head, node;
        head = sem_field(number, 1); node = waiter == 0 ? head : field(waiter, 5);
        check32("semaphore next", ram32(head), node); check32("semaphore previous", ram32(head + 4), node);
        if (waiter != 0) begin
            check32("waiter next", ram32(node), head); check32("waiter previous", ram32(node + 4), head);
        end
    endtask
    task automatic kernel_matches_model();
        for (integer id = 1; id <= 4; id++) begin
            priority_check(id, 32'(priorities[id]));
            check32("modeled runnable state", state(id), ready[id] ? (id == target_id ? 3 : 1) : 2);
        end
        check32("selected current thread", ram32(symbols[CURRENT]), field(target_id, 1));
    endtask
    task automatic lock_matches_model();
        lock_check(lock_owner, lock_owner == 0 ? 1 : 0, lock_owner == 0 ? 0 : 1,
                   lock_owner == 0 ? 255 : 32'(base_priority[lock_owner]));
    endtask
    initial begin
        if ($value$plusargs("image=%s", image_path)) begin end
        if ($value$plusargs("symbols=%s", symbol_path)) begin end
        if ($value$plusargs("ticks=%d", run_ticks)) begin end
        if (run_ticks < 55 || run_ticks > 10005 || run_ticks % 50 != 5)
            $fatal(1, "ticks must be 55..10005 and end five ticks after a 50-tick boundary");
        expected_samples = (run_ticks - 5) / 10;
        expected_heartbeats = (run_ticks - 5) / 25;
        // Wave recording is optional so the normal sustained test stays small.
        if ($value$plusargs("wave=%s", wave_path)) begin
            $dumpfile(wave_path); $dumpvars(0, tb_soc_rtthread_demo);
        end
        for (integer i = 0; i < 16384; i++) dut.u_ram.mem[i] = 32'hfeed_0000 ^ 32'(i);
        for (integer id = 1; id <= 4; id++) begin
            ready[id] = 1'b1; entries[id] = 0;
            base_priority[id] = id == 4 ? 31 : id + 9; priorities[id] = base_priority[id];
        end
        for (integer id = 1; id <= 3; id++) begin
            lock_takes[id] = 0; lock_releases[id] = 0; delay_calls[id] = 0; delay_returns[id] = 0;
        end
        for (integer id = 1; id <= 2; id++) begin
            sem_takes[id] = 0; sem_releases[id] = 0; take_returns[id] = 0; release_returns[id] = 0;
        end
        tokens[0] = 1; tokens[1] = 0; waiters[0] = 0; waiters[1] = 0;
        #1;
        $readmemh(image_path, dut.u_rom.mem); $readmemh(symbol_path, symbols);
        $display("[RUN] %s for %0d ticks", image_path, run_ticks);
        check32("consumer stack placement", symbols[STACK_A], 32'h1000_8000);
        check32("producer stack placement", symbols[STACK_B], 32'h1000_9000);
        check32("heartbeat stack placement", symbols[STACK_CHECK], 32'h1000_a000);
        for (integer id = 0; id < 5; id++) min_sp[id] = stack_top(id);
        repeat (2) @(posedge clk);
        @(negedge clk); rst = 1'b0; #1;

        for (integer cycle = 0; cycle < (int'(run_ticks) + 20) * 10000 + 100000; cycle++) begin
            address = dut.mem_addr; store_value = dut.mem_wdata;
            old_time = dut.u_timer.mtime; old_compare = dut.u_timer.mtimecmp; old_irq = dut.timer_irq;
            expected_irq = old_irq && dut.u_cpu.mstatus[3] && dut.u_cpu.mie[7];
            is_mret = dut.instr == MRET;
            compare_write = dut.mem_we && (address == TIMER + 8 || address == TIMER + 12);
            if (pc[1:0] != 0 || pc >= 32'h10000) $fatal(1, "Invalid PC");
            check32("MTIP follows hardware timer", dut.u_cpu.mip, old_irq ? 32'h80 : 0);
            check32("only enabled timer traps", {31'b0, dut.u_cpu.trap_enter}, {31'b0, expected_irq});
            if (dut.mem_we && !(address >= RAM_BASE && address < RAM_BASE + 32'h10000) && address != UART_TX && !compare_write)
                $fatal(1, "Unexpected store or mtime reset");
            if (!expected_irq && pc == symbols[FAIL]) $fatal(1, "Firmware check failed at demo.c:%0d", gpr(10));
            if (!expected_irq && pc == symbols[EXIT]) $fatal(1, "A continuous thread returned");
            if (!expected_irq && pc == symbols[TICK_INIT]) begin check32("tick init on main", 32'(owner), 0); tick_inits++; end
            if (!expected_irq && pc == symbols[SEM_INIT]) begin
                check32("semaphore init on main", 32'(owner), 0);
                check32("initial semaphore object", gpr(10), symbols[sem_inits == 0 ? EMPTY : FULL]);
                check32("initial token count", gpr(12), sem_inits == 0 ? 1 : 0);
                check32("priority queue", gpr(13), 1); sem_inits++;
            end
            if (!expected_irq && pc == symbols[MUTEX_INIT]) begin
                check32("mutex init on main", 32'(owner), 0); check32("application mutex", gpr(10), symbols[LOCK]);
                check32("mutex priority queue", gpr(12), 1); mutex_inits++;
            end
            if (!expected_irq && pc == symbols[HOOK]) begin check32("idle hook owner", 32'(owner), 4); hook_calls++; end

            for (integer id = 1; id <= 2; id++) begin
                if (!expected_irq && take_pending[id] && owner == id && pc == take_return[id]) begin
                    check32("semaphore take status", gpr(10), 0); check32("take MIE restored", dut.u_cpu.mstatus, 32'h1888);
                    timer_removed(id);
                    if (id == 2) begin
                        if (empty_owned || full_owned || slot_available) $fatal(1, "Producer overwrote an occupied slot");
                        empty_owned = 1'b1;
                    end else begin
                        if (!slot_available || full_owned || empty_owned) $fatal(1, "Consumer read an unpublished slot");
                        check32("published sequence", ram32(symbols[SLOT]), 32'(received + 1));
                        check32("published payload", ram32(symbols[SLOT] + 4), 32'((received + 1) * 3 + 1));
                        slot_available = 1'b0; full_owned = 1'b1;
                    end
                    take_pending[id] = 1'b0; take_returns[id]++;
                end
                if (!expected_irq && release_pending[id] && owner == id && pc == release_return[id]) begin
                    check32("semaphore release status", gpr(10), 0);
                    check32("release MIE restored", dut.u_cpu.mstatus, 32'h1888);
                    release_pending[id] = 1'b0; release_returns[id]++;
                end
            end
            if (!expected_irq && pc == symbols[TAKE]) begin
                if (owner < 1 || owner > 2 || take_pending[owner] || active) $fatal(1, "Unexpected semaphore take");
                sem_id = owner == 2 ? 0 : 1;
                check32("take object", gpr(10), symbols[sem_id == 0 ? EMPTY : FULL]);
                check32("infinite semaphore wait", gpr(11), 32'hffff_ffff);
                if (lock_owner == owner) $fatal(1, "Waited for semaphore while holding app_lock");
                check32("modeled token count", sem_value(sem_id), 32'(tokens[sem_id]));
                sem_queue_check(sem_id, waiters[sem_id]);
                if (tokens[sem_id] != 0) tokens[sem_id]--;
                else begin
                    if (waiters[sem_id] != 0) $fatal(1, "Unexpected second semaphore waiter");
                    block_requested[owner] = 1'b1; waiters[sem_id] = owner;
                end
                take_return[owner] = gpr(1); take_pending[owner] = 1'b1; sem_takes[owner]++;
            end
            if (!expected_irq && pc == symbols[RELEASE]) begin
                if (owner < 1 || owner > 2 || release_pending[owner] || active) $fatal(1, "Unexpected semaphore release");
                sem_id = owner == 2 ? 1 : 0;
                check32("release object", gpr(10), symbols[sem_id == 0 ? EMPTY : FULL]);
                if (lock_owner == owner) $fatal(1, "Publication still holds app_lock");
                check32("release token count", sem_value(sem_id), 32'(tokens[sem_id]));
                sem_queue_check(sem_id, waiters[sem_id]);
                if (owner == 2) begin
                    if (!empty_owned || full_owned || slot_available) $fatal(1, "Invalid publication ownership");
                    published++;
                    check32("producer sequence", ram32(symbols[PRODUCED]), 32'(published));
                    check32("slot sequence", ram32(symbols[SLOT]), 32'(published));
                    check32("slot value", ram32(symbols[SLOT] + 4), 32'(published * 3 + 1));
                    check32("previous sample consumed", ram32(symbols[CONSUMED]), 32'(published - 1));
                    empty_owned = 1'b0; slot_available = 1'b1;
                end else begin
                    if (!full_owned || empty_owned || slot_available) $fatal(1, "Invalid consumption ownership");
                    received++;
                    check32("consumer sequence", ram32(symbols[CONSUMED]), 32'(received));
                    check32("sample line already printed", 32'(sample_lines), 32'(received));
                    full_owned = 1'b0;
                end
                if (waiters[sem_id] == 0) begin tokens[sem_id]++; if (tokens[sem_id] > 1) $fatal(1, "Single-slot token overflow"); end
                release_return[owner] = gpr(1); release_pending[owner] = 1'b1; sem_releases[owner]++;
            end
            for (integer id = 1; id <= 3; id++) begin
                if (!expected_irq && lock_take_pending[id] && owner == id && pc == lock_take_return[id]) begin
                    check32("mutex take result", gpr(10), 0); check32("lock acquired by caller", 32'(lock_owner), 32'(id));
                    lock_matches_model(); lock_take_pending[id] = 1'b0;
                end
                if (!expected_irq && lock_release_pending[id] && owner == id && pc == lock_release_return[id]) begin
                    check32("mutex release result", gpr(10), 0); lock_matches_model(); lock_release_pending[id] = 1'b0;
                end
                if (!expected_irq && delay_pending[id] && owner == id && pc == delay_return[id]) begin
                    if (!delay_expired[id] || ram32(symbols[TICK]) < delay_deadline[id]) $fatal(1, "Periodic delay returned early");
                    check32("periodic delay result", gpr(10), 0);
                    check32("next planned wakeup", ram32(delay_pointer[id]), delay_deadline[id]);
                    check32("delay MIE restored", dut.u_cpu.mstatus, 32'h1888); timer_removed(id);
                    delay_pending[id] = 1'b0; delay_returns[id]++;
                end
            end
            if (!expected_irq && pc == symbols[LOCK_TAKE]) begin
                if (owner < 1 || owner > 3 || lock_take_pending[owner] || active) $fatal(1, "Unexpected mutex take");
                check32("mutex take object", gpr(10), symbols[LOCK]); check32("mutex wait mode", gpr(11), 32'hffff_ffff);
                lock_matches_model();
                if (lock_owner == 0) lock_owner = owner;
                else begin
                    if (lock_owner == owner) $fatal(1, "Unexpected recursive demo lock");
                    lock_waiters[owner] = 1'b1; block_requested[owner] = 1'b1;
                    if (priorities[owner] < priorities[lock_owner]) priorities[lock_owner] = priorities[owner];
                end
                lock_take_return[owner] = gpr(1); lock_take_pending[owner] = 1'b1; lock_takes[owner]++;
            end
            if (!expected_irq && pc == symbols[LOCK_RELEASE]) begin
                if (owner < 1 || owner > 3 || lock_release_pending[owner] || lock_owner != owner || active)
                    $fatal(1, "Unexpected mutex release");
                check32("mutex release object", gpr(10), symbols[LOCK]); lock_matches_model();
                priorities[owner] = base_priority[owner]; next_owner = 0;
                for (integer id = 1; id <= 3; id++)
                    if (lock_waiters[id] && (next_owner == 0 || priorities[id] < priorities[next_owner])) next_owner = id;
                lock_owner = next_owner;
                lock_release_return[owner] = gpr(1); lock_release_pending[owner] = 1'b1; lock_releases[owner]++;
            end
            if (!expected_irq && pc == symbols[DELAY]) begin
                if ((owner != 2 && owner != 3) || delay_pending[owner] || active) $fatal(1, "Unexpected periodic delay");
                check32("periodic interval", gpr(11), owner == 2 ? 10 : 25);
                check32("previous planned wakeup", ram32(gpr(10)), 32'(delay_calls[owner] * (owner == 2 ? 10 : 25)));
                if (lock_owner == owner) $fatal(1, "Sleeping while holding the console lock");
                delay_pointer[owner] = gpr(10); delay_deadline[owner] = ram32(gpr(10)) + gpr(11);
                if (ram32(symbols[TICK]) >= delay_deadline[owner]) $fatal(1, "Periodic work overran its interval");
                delay_return[owner] = gpr(1); delay_pending[owner] = 1'b1; delay_expired[owner] = 1'b0;
                block_requested[owner] = 1'b1; delay_calls[owner]++;
            end
            if (!expected_irq && pc == symbols[SUSPEND] && owner != 0) begin
                if (owner > 3 || active || !block_requested[owner]) $fatal(1, "Unrequested thread suspension");
                check32("suspends the current thread", gpr(10), field(owner, 1));
                check32("suspension is inside a critical section", {31'b0, dut.u_cpu.mstatus[3]}, 0);
                ready[owner] = 1'b0; block_requested[owner] = 1'b0;
            end
            if (!expected_irq && pc == symbols[RESUME] && owner != 0) begin
                callback_id = thread_id(gpr(10));
                if (active || callback_id > 3 || ready[callback_id]) $fatal(1, "Unrequested thread resume");
                check32("resume is inside a critical section", {31'b0, dut.u_cpu.mstatus[3]}, 0);
                check32("resume target suspended", state(callback_id), 2);
                if (waiters[0] == callback_id) waiters[0] = 0;
                else if (waiters[1] == callback_id) waiters[1] = 0;
                else if (lock_waiters[callback_id]) lock_waiters[callback_id] = 1'b0;
                else $fatal(1, "Resume target has no IPC wait");
                ready[callback_id] = 1'b1;
            end
            if (!expected_irq && pc == symbols[PRINT]) begin
                if (print_active || (owner != 0 && lock_owner != owner)) $fatal(1, "Unserialized rt_kprintf");
                print_owner = owner; print_return = gpr(1); print_active = 1'b1;
            end
            if (!expected_irq && print_active && owner == print_owner && pc == print_return) print_active = 1'b0;
            if (!expected_irq && pc == symbols[OUTPUT] && (!print_active || owner != print_owner))
                $fatal(1, "Console output outside a tracked print");

            if (owner != 0 && dut.mem_we && !expected_irq && (address == symbols[SLOT] || address == symbols[SLOT] + 4)) begin
                check32("slot writer", 32'(owner), 2); check32("slot write lock", 32'(lock_owner), 2);
                check32("slot word strobe", {28'b0, dut.mem_wstrb}, 15);
                if (!empty_owned || full_owned || slot_available) $fatal(1, "Slot write without empty token");
                if (address == symbols[SLOT]) begin
                    check32("slot sequence write", store_value, 32'(published + 1));
                    check32("previous payload completed", 32'(sequence_stores), 32'(value_stores)); sequence_stores++;
                end else begin
                    check32("slot payload write", store_value, 32'((published + 1) * 3 + 1));
                    check32("sequence precedes payload", 32'(sequence_stores), 32'(value_stores + 1)); value_stores++;
                end
            end

            if (expected_irq) begin
                if (owner == 0) $fatal(1, "Timer enabled before first thread");
                check32("pre-trap status", dut.u_cpu.mstatus, 32'h1888);
                check32("trap cancels writes", {29'b0, dut.u_cpu.rf_we, dut.u_cpu.csr_we, dut.mem_we}, 0);
                begin_transition(2); irqs++; interrupted_pc = pc; target_id = owner;
                irq_timeouts = 0; expected_timeouts = 0; irq_current = owner; irq_requests = 0;
                for (integer id = 2; id <= 3; id++)
                    if (delay_pending[id] && !delay_expired[id] && delay_deadline[id] == 32'(irqs)) expected_timeouts++;
                if (32'(irqs) > run_ticks) $fatal(1, "Test did not settle before the next tick");
                check32("no stale IRQ request", ram32(symbols[FLAG]), 0);
            end
            if (!expected_irq && (pc == symbols[SWITCH_TO] || pc == symbols[SWITCH])) begin
                begin_transition(pc == symbols[SWITCH_TO] ? 0 : 1);
                target_id = best_ready();
                if (kind == 0) begin
                    check32("scheduler starts on main", 32'(owner), 0);
                    if (!boot_ready || !version_seen) $fatal(1, "Missing boot/version output");
                    check32("semaphore initializations", 32'(sem_inits), 2); check32("mutex initializations", 32'(mutex_inits), 1);
                    for (integer number = 0; number <= 1; number++) begin
                        check32("initial semaphore type", ram8(sem_field(number, 2)), 32'h82);
                        check32("initial semaphore flags", ram8(sem_field(number, 3)), 1);
                        check32("initial tokens", sem_value(number), 32'(tokens[number])); sem_queue_check(number, 0);
                    end
                    check32("initial mutex type", ram8(mutex_field(5)), 32'h83);
                    check32("initial mutex flags", ram8(mutex_field(6)), 1); lock_matches_model(); queue_check(0);
                    boot_gp = gpr(3); boot_tp = gpr(4);
                    for (integer id = 1; id <= 4; id++) begin
                        frames[id] = stack_top(id) - 144;
                        for (integer i = 0; i < 36; i++) golden[id][i] = 0;
                        golden[id][0] = symbols[EXIT]; golden[id][1] = stack_top(id);
                        golden[id][2] = boot_gp; golden[id][3] = boot_tp;
                        golden[id][9] = id == 4 ? 0 : field(id, 1);
                        golden[id][31] = id == 1 ? symbols[CONSUMER] : (id == 2 ? symbols[PRODUCER] : (id == 3 ? symbols[HEARTBEAT] : symbols[IDLE_ENTRY]));
                        golden[id][32] = 32'h1880;
                    end
                    check32("first context pointer", gpr(10), field(target_id, 0));
                end else begin
                    if (target_id == owner) $fatal(1, "Spurious software context switch");
                    check32("software switch source", gpr(10), field(owner, 0));
                    check32("software switch target", gpr(11), field(target_id, 0)); switches++;
                end
                kernel_matches_model();
            end
            if (active && !expected_irq) check32("MIE clear during switch/ISR", {31'b0, dut.u_cpu.mstatus[3]}, 0);
            if (pc == symbols[DISPATCH]) begin
                if (!active || kind != 2 || c_called) $fatal(1, "Unexpected dispatcher");
                check_frame(source_id); check32("dispatcher frame", gpr(10), frames[source_id]);
                check32("dispatcher cause", gpr(11), 32'h8000_0007); check32("dispatcher tval", gpr(12), 0);
                dispatch_return = gpr(1); c_called = 1'b1; dispatches++;
            end
            if (active && kind == 2) begin
                if (pc == symbols[ENTER]) begin check32("nest before enter", nest_value(), 0); enter_return = gpr(1); end
                if (pc == enter_return) begin check32("nest after enter", nest_value(), 1); enter_return = 0; enters++; end
                if (pc == symbols[LEAVE]) begin check32("nest before leave", nest_value(), 1); leave_return = gpr(1); end
                if (pc == leave_return) begin check32("nest after leave", nest_value(), 0); leave_return = 0; leaves++; end
                if (pc == symbols[INCREASE]) begin check32("tick before", ram32(symbols[TICK]), 32'(irqs - 1)); increase_return = gpr(1); end
                if (pc == increase_return) begin check32("tick after", ram32(symbols[TICK]), 32'(irqs)); increase_return = 0; increases++; end
                if (pc == symbols[REARM]) begin check32("rearm nesting", nest_value(), 1); rearms++; end
                if (pc == symbols[TIMEOUT]) begin
                    callback_id = thread_id(gpr(10));
                    if ((callback_id != 2 && callback_id != 3) || !delay_pending[callback_id] || delay_expired[callback_id] || ready[callback_id])
                        $fatal(1, "Unexpected periodic timeout");
                    check32("timeout deadline", delay_deadline[callback_id], 32'(irqs));
                    check32("kernel deadline", ram32(field(callback_id, 3)), 32'(irqs));
                    check32("timeout source suspended", state(callback_id), 2);
                    delay_expired[callback_id] = 1'b1; ready[callback_id] = 1'b1; timeout_calls++; irq_timeouts++;
                end
                if (pc == symbols[IRQ_SWITCH]) begin
                    target_id = best_ready();
                    check32("IRQ source follows kernel selection", gpr(10), field(irq_current, 0));
                    check32("IRQ target", gpr(11), field(target_id, 0));
                    if (irq_current == target_id) $fatal(1, "Redundant IRQ switch request");
                    irq_current = target_id; irq_requests++;
                    request_return = gpr(1); requests++;
                end
                if (request_return != 0 && pc == request_return) begin
                    check32("IRQ request flag", ram32(symbols[FLAG]), 1);
                    check32("first interrupted source retained", ram32(symbols[FROM]), field(source_id, 0));
                    check32("latest target retained", ram32(symbols[TO]), field(target_id, 0));
                    request_return = 0; request_returns++;
                end
                if (c_called && !c_returned && pc == dispatch_return) begin
                    // A suspended caller can still be between interrupt-enable
                    // and rt_schedule. With no IRQ request it resumes that call.
                    target_id = irq_current;
                    check32("periodic callbacks this IRQ", 32'(irq_timeouts), 32'(expected_timeouts));
                    if (expected_timeouts == 2) shared_expiries++;
                    if (irq_requests == 2) shared_requests++;
                    check32("returned target frame", gpr(10), frames[target_id]);
                    check32("C source stack balanced", gpr(2), frames[source_id]);
                    check32("IRQ flag consumed", ram32(symbols[FLAG]), 0); check32("IRQ nesting cleared", nest_value(), 0);
                    if (target_id != source_id) check32("interrupted SP persisted", ram32(field(source_id, 0)), frames[source_id]);
                    kernel_matches_model(); c_returned = 1'b1; dispatch_returns++;
                end
            end
            if (pc == symbols[RESTORE]) begin
                if (!active || (kind == 2 && !c_returned)) $fatal(1, "Early restore");
                if (kind == 1) begin check_frame(source_id); check32("source SP saved", ram32(field(source_id, 0)), frames[source_id]); end
                check_frame(target_id); check32("restore target SP", gpr(2), frames[target_id]); restoring = 1'b1;
            end
            if (is_mret) begin
                if (!active || !restoring) $fatal(1, "Untracked MRET");
                for (integer n = 1; n < 32; n++) check32($sformatf("restored x%0d", n), gpr(n), golden[target_id][n - 1]);
                check32("restored mepc", dut.u_cpu.mepc, golden[target_id][31]);
                check32("restored mstatus", dut.u_cpu.mstatus, golden[target_id][32] & ~32'h8);
                if (kind == 2) check32("ISR rearmed timer before MRET", {31'b0, dut.timer_irq}, 0);
                else if (dut.timer_irq) pending_mrets++;
            end
            if (!expected_irq && (pc == symbols[CONSUMER] || pc == symbols[PRODUCER] || pc == symbols[HEARTBEAT] || pc == symbols[IDLE_ENTRY])) begin
                if (owner == 0 || entries[owner] != 0) $fatal(1, "Unexpected C entry");
                check32("entry PC", pc, symbols[owner == 1 ? CONSUMER : (owner == 2 ? PRODUCER : (owner == 3 ? HEARTBEAT : IDLE_ENTRY))]);
                check32("entry stack", gpr(2), stack_top(owner)); check32("entry parameter", gpr(10), owner == 4 ? 0 : field(owner, 1)); entries[owner]++;
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
                    if (!boot_ready) begin
                        check32("boot print on main", 32'(owner), 0);
                        if (contains(uart_line, "4.1.1")) version_seen = 1'b1;
                        if (uart_line == "KERNEL READY") boot_ready = 1'b1;
                    end else begin
                        if (!print_active || lock_owner != owner || print_owner != owner) $fatal(1, "UART line lacks mutex protection");
                        if ($sscanf(uart_line, "SAMPLE seq=%d value=%d tick=%d", line_sequence, line_value, line_tick) == 3) begin
                            check32("sample print thread", 32'(owner), 1); sample_lines++;
                            check32("sample sequence", line_sequence, 32'(sample_lines)); check32("sample arithmetic", line_value, line_sequence * 3 + 1);
                            check32("sample consumed", ram32(symbols[CONSUMED]), line_sequence);
                            if (line_tick < line_sequence * 10 || line_tick > ram32(symbols[TICK])) $fatal(1, "Sample timestamp invalid");
                            if (uart_line != $sformatf("SAMPLE seq=%0d value=%0d tick=%0d", line_sequence, line_value, line_tick)) $fatal(1, "Mixed/truncated sample line");
                        end else if ($sscanf(uart_line, "HB tick=%d produced=%d consumed=%d idle=%d", line_tick, line_produced, line_consumed, line_idle) == 4) begin
                            check32("heartbeat print thread", 32'(owner), 3); heartbeat_lines++;
                            check32("heartbeat counter", ram32(symbols[HEARTBEATS]), 32'(heartbeat_lines));
                            check32("heartbeat producer snapshot", ram32(symbols[PRODUCED]), line_produced);
                            check32("heartbeat consumer snapshot", ram32(symbols[CONSUMED]), line_consumed);
                            check32("heartbeat idle snapshot", ram32(symbols[IDLE_HITS]), line_idle);
                            if (line_tick < 32'(heartbeat_lines * 25) || line_tick > ram32(symbols[TICK]) || line_produced - line_consumed > 1 || line_idle == 0)
                                $fatal(1, "Heartbeat snapshot invalid");
                            if (uart_line != $sformatf("HB tick=%0d produced=%0d consumed=%0d idle=%0d", line_tick, line_produced, line_consumed, line_idle)) $fatal(1, "Mixed/truncated heartbeat line");
                        end else $fatal(1, "Unexpected runtime UART line: %s", uart_line);
                    end
                    uart_line = "";
                end else uart_line = {uart_line, $sformatf("%c", uart_tx_data)};
            end
            if (32'(irqs) == run_ticks && !active && owner == 4) begin
                check32("timer interrupts", 32'(irq_returns), run_ticks);
                check32("dispatch calls", 32'(dispatches), run_ticks); check32("dispatch returns", 32'(dispatch_returns), run_ticks);
                check32("interrupt enters", 32'(enters), run_ticks); check32("interrupt leaves", 32'(leaves), run_ticks);
                check32("kernel ticks", 32'(increases), run_ticks); check32("timer rearms", 32'(rearms), run_ticks);
                check32("all transitions restored", 32'(restores), 32'(switches + irqs + 1));
                check32("all IRQ paths restored", 32'(same_returns + irq_switches), run_ticks);
                check32("IRQ requests returned", 32'(request_returns), 32'(requests));
                check32("expiry callbacks", 32'(timeout_calls), expected_samples + expected_heartbeats);
                check32("simultaneous periodic expiries", 32'(shared_expiries), (run_ticks - 5) / 50);
                if (shared_requests == 0) $fatal(1, "No repeated IRQ selection was exercised");
                check32("published count", 32'(published), expected_samples); check32("received count", 32'(received), expected_samples);
                check32("sample lines", 32'(sample_lines), expected_samples); check32("heartbeat lines", 32'(heartbeat_lines), expected_heartbeats);
                check32("sample sequence writes", 32'(sequence_stores), expected_samples); check32("sample payload writes", 32'(value_stores), expected_samples);
                for (integer id = 1; id <= 2; id++) begin
                    check32("semaphore take calls", 32'(sem_takes[id]), expected_samples + (id == 1 ? 1 : 0));
                    check32("semaphore take returns", 32'(take_returns[id]), expected_samples);
                    check32("semaphore release calls", 32'(sem_releases[id]), expected_samples);
                    check32("semaphore release returns", 32'(release_returns[id]), expected_samples);
                end
                for (integer id = 1; id <= 3; id++) begin
                    check32("mutex takes", 32'(lock_takes[id]), id == 3 ? expected_heartbeats : expected_samples);
                    check32("mutex releases", 32'(lock_releases[id]), id == 3 ? expected_heartbeats : expected_samples);
                end
                for (integer id = 2; id <= 3; id++) begin
                    check32("periodic delay calls", 32'(delay_calls[id]), (id == 2 ? expected_samples : expected_heartbeats) + 1);
                    check32("periodic delay returns", 32'(delay_returns[id]), id == 2 ? expected_samples : expected_heartbeats);
                    check32("next period still armed", timer_active(id), 1);
                    check32("next expiry", ram32(field(id, 3)), 32'((delay_calls[id]) * (id == 2 ? 10 : 25)));
                end
                check32("producer count", ram32(symbols[PRODUCED]), expected_samples); check32("consumer count", ram32(symbols[CONSUMED]), expected_samples);
                check32("heartbeat count", ram32(symbols[HEARTBEATS]), expected_heartbeats);
                check32("slot final sequence", ram32(symbols[SLOT]), expected_samples); check32("slot final payload", ram32(symbols[SLOT] + 4), expected_samples * 3 + 1);
                check32("empty token remains available", sem_value(0), 1); check32("full token remains empty", sem_value(1), 0);
                sem_queue_check(0, 0); sem_queue_check(1, 1); timer_removed(1); lock_matches_model(); queue_check(0);
                for (integer id = 1; id <= 4; id++) begin
                    check32("thread entered once", 32'(entries[id]), 1);
                    check32("static thread remains attached", ram8(field(id, 4)), 32'h81);
                end
                target_id = 4; kernel_matches_model();
                check32("tick kept running", ram32(symbols[TICK]), run_ticks);
                check32("MTIE kept enabled", dut.u_cpu.mie, 32'h80); check32("MIE kept enabled", dut.u_cpu.mstatus, 32'h1888);
                check32("nesting balanced", nest_value(), 0); check32("IRQ request consumed", ram32(symbols[FLAG]), 0);
                check32("safe compare sequences", 32'(compare_sequences), run_ticks + 2); check32("periodic compares", 32'(periodic_compares), run_ticks + 1);
                check32("IRQ rises", 32'(irq_rises), run_ticks); check32("IRQ falls", 32'(irq_falls), run_ticks);
                check32("data initialized", ram32(symbols[COOKIE]), 32'h1357_9bdf); check32("tick init once", 32'(tick_inits), 1);
                if (take_pending != 2'b01 || delay_pending != 3'b110 || block_requested != 0 || release_pending != 0 || lock_take_pending != 0 || lock_release_pending != 0 || lock_waiters != 0 || print_active || uart_line != "")
                    $fatal(1, "Continuous threads did not settle into their expected waits");
                if (empty_owned || full_owned || slot_available || lock_owner != 0 || hook_calls == 0 || ram32(symbols[IDLE_HITS]) == 0 || compare_phase != 0)
                    $fatal(1, "Outstanding slot, lock, timer write or idle starvation");
                if (dut.u_timer.mtimecmp != deadline || deadline <= dut.u_timer.mtime || deadline == 64'hffff_ffff_ffff_ffff)
                    $fatal(1, "Timer was stopped or missed its next deadline");
                for (integer i = 0; i < 4; i++) begin
                    for (integer id = 1; id <= 3; id++) check32("thread guard", ram32(symbols[STACK_A + id - 1] + 32'(i * 4)), 32'ha55a_0000 | 32'(id));
                    check32("main guard", ram32(symbols[GUARD] + 32'(i * 4)), 32'hc0de_cafe);
                    check32("idle bottom unused", ram32(symbols[IDLE_STACK] + 32'(i * 4)), 32'h2323_2323);
                end
                for (integer id = 0; id < 5; id++) $display("[PASS] stack %0d observed use: %0d bytes", id, stack_top(id) - min_sp[id]);
                $display("[PASS] %0d consecutive samples, %0d heartbeats, single-slot ownership and serialized console", received, heartbeat_lines);
                $display("[PASS] %0d real IRQs, %0d full context restores, %0d kernel resumes, %0d IRQ requests", irqs, restores, kernel_resumes, requests);
                $display("[PASS] %0d software restores with a pending timer IRQ", pending_mrets);
                $display("[PASS] all threads remain live, tick/MTIE/MIE remain enabled, simulation alone ends observation");
                $display(" M11.8 SOC RT-THREAD DEMO PASS"); $finish;
            end
            @(negedge clk); #1;
        end
        $fatal(1, "Demo timeout: pc=%08x tick=%0d owner=%0d", pc, irqs, owner);
    end
endmodule
