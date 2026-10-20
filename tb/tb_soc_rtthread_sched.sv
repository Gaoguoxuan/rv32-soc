module tb_soc_rtthread_sched;
    localparam logic [31:0] RAM_BASE = 32'h1000_0000;
    localparam logic [31:0] UART_TX = 32'h2000_0000;
    localparam logic [31:0] MRET = 32'h3020_0073;
    localparam integer SWITCH_TO = 0, SWITCH = 1, IRQ_SWITCH = 2, START = 3,
        YIELD = 4, ENTRY = 5, FINISH = 6, EXIT = 7, LOCATIONS = 8,
        STACK_A = 9, STACK_B = 10, STACK_CHECK = 11, ROUNDS = 12, RETURNS = 13,
        CRITICAL = 14, TRACE = 15, TRACE_COUNT = 16, COOKIE = 17, GUARD = 18,
        BOTTOM = 19, TOP = 20, CURRENT = 21, NEST = 22, FROM = 23, TO = 24,
        FLAG = 25, SCHEDULE = 26, INIT = 27, STARTUP = 28, ARGUMENTS = 29;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [31:0] pc;
    logic uart_tx_valid;
    logic [7:0] uart_tx_data;
    logic [31:0] symbols [0:29];
    // Architectural snapshots taken before any instruction in the switch routine.
    logic [31:0] golden [1:3][0:35];
    logic [31:0] frames [1:3];
    logic [31:0] min_sp [0:3];
    logic [35:0] save_mask;
    logic [32:0] load_mask;
    logic [3:1] started = '0;
    logic active = 1'b0;
    logic saving;
    logic pointer_saved;
    logic target_loaded;
    logic epc_restored;
    logic status_restored;
    logic stack_live = 1'b0;
    logic done = 1'b0;
    logic is_mret;
    logic [31:0] from_location;
    logic [31:0] to_location;
    logic [31:0] target_frame;
    logic [31:0] old_instr;
    logic [31:0] address;
    logic [31:0] sp_value;
    logic [63:0] old_time;
    integer owner = 0;
    integer source_id = 0;
    integer target_id = 0;
    integer switches = 0;
    integer restores = 0;
    integer fresh_starts = 0;
    integer resumes = 0;
    integer entries = 0;
    integer exits = 0;
    integer kernel_starts = 0;
    integer init_calls = 0;
    integer startup_calls = 0;
    integer schedule_calls = 0;
    integer irq_requests = 0;
    integer yield_calls [1:2];
    integer uart_lines = 0;
    integer slot;
    string image_path = "build/rtthread_sched/rtthread_sched.hex";
    string symbol_path = "build/rtthread_sched/rtthread_sched.symbols.hex";
    string wave_path = "build/rtthread_sched/rtthread_sched.vcd";
    string uart_line = "";

    rv32_soc #(.ROM_BYTES(65536), .RAM_BYTES(65536)) dut (
        .clk (clk), .rst (rst), .pc (pc),
        .uart_tx_valid (uart_tx_valid), .uart_tx_data (uart_tx_data)
    );

    initial forever #5 clk = ~clk;

    function automatic logic [31:0] ram32(input logic [31:0] addr);
        if (addr < RAM_BASE || addr >= RAM_BASE + 32'h10000 || addr[1:0] != 0)
            $fatal(1, "Invalid monitored RAM address: %08x", addr);
        return dut.u_ram.mem[(addr - RAM_BASE) >> 2];
    endfunction

    function automatic logic [31:0] rom32(input logic [31:0] addr);
        if (addr >= 32'h10000 || addr[1:0] != 0)
            $fatal(1, "Invalid monitored ROM address: %08x", addr);
        return dut.u_rom.mem[addr >> 2];
    endfunction

    function automatic logic [31:0] sp_location(input integer id);
        return rom32(symbols[LOCATIONS] + 32'((id - 1) * 4));
    endfunction

    function automatic logic [31:0] thread_address(input integer id);
        return rom32(symbols[LOCATIONS] + 32'((id + 2) * 4));
    endfunction

    function automatic logic [31:0] stack_top(input integer id);
        if (id == 0) return symbols[TOP];
        return symbols[STACK_A + id - 1] + 32'd2048;
    endfunction

    function automatic logic stack_valid(input logic [31:0] value, input integer id);
        logic [31:0] bottom;
        bottom = id == 0 ? symbols[BOTTOM] : symbols[STACK_A + id - 1] + 32'd16;
        return value >= bottom && value <= stack_top(id) && value[3:0] == 0;
    endfunction

    task automatic check32(input string name, input logic [31:0] actual,
                           input logic [31:0] expected);
        if (actual !== expected)
            $fatal(1, "%s: got=%08x expected=%08x pc=%08x owner=%0d switches=%0d",
                   name, actual, expected, pc, owner, switches);
    endtask

    task automatic check_frame(input integer id);
        for (integer i = 0; i < 36; i++)
            check32($sformatf("thread %0d saved field %0d", id, i),
                    ram32(frames[id] + 32'(i * 4)), golden[id][i]);
    endtask

    task automatic check_line(input string expected, input integer expected_owner);
        if (uart_line != expected)
            $fatal(1, "UART line %0d: got='%s' expected='%s'", uart_lines, uart_line, expected);
        check32("UART stack owner", 32'(owner), 32'(expected_owner));
    endtask

    initial begin
        if ($value$plusargs("image=%s", image_path)) begin end
        if ($value$plusargs("symbols=%s", symbol_path)) begin end
        if ($value$plusargs("wave=%s", wave_path)) begin end
        $dumpfile(wave_path);
        $dumpvars(0, tb_soc_rtthread_sched);
        for (integer i = 0; i < 16384; i++)
            dut.u_ram.mem[i] = 32'hfeed_0000 ^ 32'(i);
        #1;
        $readmemh(image_path, dut.u_rom.mem);
        $readmemh(symbol_path, symbols);
        $display("[RUN] %s", image_path);
        check32("A stack placement", symbols[STACK_A], 32'h1000_8000);
        check32("B stack placement", symbols[STACK_B], 32'h1000_9000);
        check32("checker stack placement", symbols[STACK_CHECK], 32'h1000_a000);
        for (integer id = 0; id < 4; id++) min_sp[id] = stack_top(id);
        for (integer id = 1; id <= 2; id++) yield_calls[id] = 0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        #1;

        for (integer cycle = 0; cycle < 1000000; cycle++) begin
            old_instr = dut.instr;
            address = dut.mem_addr;
            old_time = dut.u_timer.mtime;
            is_mret = old_instr == MRET;
            if (pc[1:0] != 0 || pc >= 32'h10000)
                $fatal(1, "Invalid PC: %08x", pc);
            if (dut.u_cpu.trap_enter)
                $fatal(1, "Unexpected trap: pc=%08x instr=%08x cause=%08x",
                       pc, old_instr, dut.u_cpu.trap_cause);
            check32("timer interrupt disabled", dut.u_cpu.mie, 0);
            check32("no pending timer", dut.u_cpu.mip, 0);
            if (dut.mem_we && !(address >= RAM_BASE && address < RAM_BASE + 32'h10000) &&
                address != UART_TX)
                $fatal(1, "Unexpected MMIO/ROM store: %08x", address);

            if (pc == symbols[START]) kernel_starts++;
            if (pc == symbols[INIT]) init_calls++;
            if (pc == symbols[STARTUP]) startup_calls++;
            if (pc == symbols[SCHEDULE]) schedule_calls++;
            if (pc == symbols[IRQ_SWITCH]) begin
                check32("request interface runs on main", 32'(owner), 0);
                check32("request recorded with MIE clear", {31'b0, dut.u_cpu.mstatus[3]}, 0);
                irq_requests++;
            end
            if (pc == symbols[YIELD]) begin
                if (owner < 1 || owner > 2 || yield_calls[owner] >= 3)
                    $fatal(1, "Unexpected yield");
                check32("yield entry MIE", {31'b0, dut.u_cpu.mstatus[3]},
                        yield_calls[owner] == 1 ? 0 : 1);
                yield_calls[owner]++;
            end

            if (pc == symbols[SWITCH] || pc == symbols[SWITCH_TO]) begin
                if (active) $fatal(1, "Nested switch routine");
                active = 1'b1;
                saving = pc == symbols[SWITCH];
                source_id = owner;
                from_location = dut.u_cpu.u_regfile.regs[10];
                to_location = dut.u_cpu.u_regfile.regs[saving ? 11 : 10];
                target_id = 0;
                for (integer id = 1; id <= 3; id++)
                    if (to_location == sp_location(id)) target_id = id;
                if (target_id == 0 || target_id == source_id)
                    $fatal(1, "Invalid target sp field: %08x", to_location);
                check32("kernel selected target thread", ram32(symbols[CURRENT]), thread_address(target_id));
                check32("switch entry MIE clear", {31'b0, dut.u_cpu.mstatus[3]}, 0);
                save_mask = '0;
                load_mask = '0;
                pointer_saved = 1'b0;
                target_loaded = 1'b0;
                epc_restored = 1'b0;
                status_restored = 1'b0;
                if (saving) begin
                    if (owner < 1 || owner > 2 || switches >= 8)
                        $fatal(1, "Unexpected thread-mode switch");
                    check32("from is source sp field", from_location, sp_location(owner));
                    check32("scheduler switch order", 32'(target_id),
                            switches == 7 ? 3 : (switches[0] ? 1 : 2));
                    frames[owner] = dut.u_cpu.u_regfile.regs[2] - 32'd144;
                    if (!stack_valid(frames[owner], owner)) $fatal(1, "Save frame outside source stack");
                    for (integer reg_num = 1; reg_num < 32; reg_num++)
                        golden[owner][reg_num - 1] = dut.u_cpu.u_regfile.regs[reg_num];
                    golden[owner][31] = dut.u_cpu.u_regfile.regs[1];
                    golden[owner][32] = dut.u_cpu.mstatus & ~32'h88;
                    for (integer i = 33; i < 36; i++) golden[owner][i] = 0;
                    switches++;
                end else begin
                    check32("initial switch starts on main", 32'(owner), 0);
                    check32("first kernel choice", 32'(target_id), 1);
                end
                target_frame = ram32(to_location);
                if (!started[target_id]) begin
                    frames[target_id] = stack_top(target_id) - 32'd144;
                    for (integer i = 0; i < 36; i++) golden[target_id][i] = 0;
                    golden[target_id][0] = symbols[EXIT];
                    golden[target_id][1] = stack_top(target_id);
                    golden[target_id][2] = dut.u_cpu.u_regfile.regs[3];
                    golden[target_id][3] = dut.u_cpu.u_regfile.regs[4];
                    golden[target_id][9] = target_id == 3 ? thread_address(3) :
                                                symbols[ARGUMENTS] + 32'((target_id - 1) * 8);
                    golden[target_id][31] = target_id == 3 ? symbols[FINISH] : symbols[ENTRY];
                    golden[target_id][32] = 32'h1880;
                end
                check32("target frame pointer", target_frame, frames[target_id]);
                check_frame(target_id);
            end

            if (active) begin
                check32("MIE stays clear during switch", {31'b0, dut.u_cpu.mstatus[3]}, 0);
                if (dut.mem_we) begin
                    if (!saving || target_loaded) $fatal(1, "Unexpected switch store");
                    if (address == from_location) begin
                        if (save_mask !== 36'hf_ffff_ffff || pointer_saved)
                            $fatal(1, "Pointer stored before complete frame");
                        check32("write back source sp", dut.mem_wdata, frames[source_id]);
                        pointer_saved = 1'b1;
                    end else begin
                        if (pointer_saved || address < frames[source_id] ||
                            address >= frames[source_id] + 32'd144 || address[1:0] != 0)
                            $fatal(1, "Save outside source frame: %08x", address);
                        slot = int'((address - frames[source_id]) >> 2);
                        check32($sformatf("save field %0d", slot), dut.mem_wdata, golden[source_id][slot]);
                        save_mask[slot] = 1'b1;
                    end
                end
                if (old_instr[6:0] == 7'h03) begin
                    if (!target_loaded) begin
                        check32("load through target sp field", address, to_location);
                        check32("target pointer loaded into sp", {27'b0, old_instr[11:7]}, 2);
                        check32("target pointer value", dut.mem_rdata, target_frame);
                        if (saving) begin
                            if (!pointer_saved) $fatal(1, "Target selected before source sp writeback");
                            check32("source sp persisted", ram32(from_location), frames[source_id]);
                            check_frame(source_id);
                        end
                        target_loaded = 1'b1;
                    end else begin
                        if (address < target_frame || address >= target_frame + 32'd132 || address[1:0] != 0)
                            $fatal(1, "Restore outside target fields: %08x", address);
                        slot = int'((address - target_frame) >> 2);
                        check32("restore register destination", {27'b0, old_instr[11:7]},
                                slot >= 31 ? 5 : 32'(slot + 1));
                        check32("restore value", dut.mem_rdata, golden[target_id][slot]);
                        load_mask[slot] = 1'b1;
                    end
                end
                if (dut.u_cpu.csr_we && target_loaded) begin
                    case (old_instr[31:20])
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
                if (!active || !target_loaded || !epc_restored || !status_restored ||
                    load_mask !== 33'h1_ffff_ffff)
                    $fatal(1, "Incomplete restore before MRET");
                for (integer reg_num = 1; reg_num < 32; reg_num++)
                    check32($sformatf("restored x%0d", reg_num), dut.u_cpu.u_regfile.regs[reg_num],
                            golden[target_id][reg_num - 1]);
                check32("MRET PC", dut.u_cpu.mepc, golden[target_id][31]);
                check32("MRET status", dut.u_cpu.mstatus, golden[target_id][32] & ~32'h8);
            end
            if (pc == symbols[ENTRY] || pc == symbols[FINISH]) begin
                if (owner < 1 || owner > 3) $fatal(1, "C entry without thread stack");
                check32("entry order", 32'(owner), 32'(entries + 1));
                check32("entry status", dut.u_cpu.mstatus, 32'h1888);
                check32("entry stack", dut.u_cpu.u_regfile.regs[2], stack_top(owner));
                check32("entry argument", dut.u_cpu.u_regfile.regs[10], golden[owner][9]);
                check32("entry RA is kernel exit", dut.u_cpu.u_regfile.regs[1], symbols[EXIT]);
                entries++;
            end
            if (pc == symbols[EXIT]) begin
                check32("kernel exit order", 32'(owner), 32'(exits + 1));
                check32("normal C return balances stack", dut.u_cpu.u_regfile.regs[2], stack_top(owner));
                check32("C body returned", ram32(symbols[RETURNS]), 32'(owner));
                check32("exit status", dut.u_cpu.mstatus, 32'h1888);
                exits++;
            end

            @(posedge clk);
            #1;
            if (dut.u_timer.mtime !== old_time + 64'd1) $fatal(1, "mtime did not advance");
            if (is_mret) begin
                check32("MRET destination", pc, golden[target_id][31]);
                check32("MRET target status", dut.u_cpu.mstatus,
                        (golden[target_id][32] & ~32'h88) | 32'h80 |
                        (golden[target_id][32][7] ? 32'h8 : 0));
                owner = target_id;
                active = 1'b0;
                restores++;
                if (started[target_id]) resumes++;
                else begin fresh_starts++; started[target_id] = 1'b1; end
                $display("[PASS] restore #%0d -> thread %0d: all 31 GPRs, MIE=%0d",
                         restores, target_id, dut.u_cpu.mstatus[3]);
            end
            sp_value = dut.u_cpu.u_regfile.regs[2];
            if (sp_value == symbols[TOP]) stack_live = 1'b1;
            if (stack_live) begin
                if (!(active ? (stack_valid(sp_value, source_id) || stack_valid(sp_value, target_id)) :
                               stack_valid(sp_value, owner)))
                    $fatal(1, "Stack ownership/alignment: sp=%08x owner=%0d", sp_value, owner);
                for (integer id = 0; id < 4; id++)
                    if (stack_valid(sp_value, id) && sp_value < min_sp[id]) min_sp[id] = sp_value;
            end
            if (uart_tx_valid) begin
                $write("%c", uart_tx_data);
                if (uart_tx_data == 8'h0a) begin
                    case (uart_lines)
                        0: check_line("M11.3 START", 0);
                        1: check_line("IRQ REQUEST PASS", 0);
                        2: check_line("KERNEL READY", 0);
                        3, 4, 5, 6, 7, 8: check_line(
                            $sformatf("THREAD %s ROUND %0d", uart_lines[0] ? "A" : "B", (uart_lines - 3) / 2 + 1),
                            uart_lines[0] ? 1 : 2);
                        9: check_line("THREAD A RETURN", 1);
                        10: check_line("THREAD B RETURN", 2);
                        11: check_line("SCHEDULER PASS", 3);
                        12: check_line("CRITICAL RESTORE PASS", 3);
                        13: check_line("STACK GUARD PASS", 3);
                        14: begin check_line("M11.3 PASS", 3); done = 1'b1; end
                        default: $fatal(1, "Unexpected UART line");
                    endcase
                    uart_lines++;
                    uart_line = "";
                end else uart_line = {uart_line, $sformatf("%c", uart_tx_data)};
            end
            if (done) begin
                check32("scheduler startup", 32'(kernel_starts), 1);
                check32("four kernel thread initializations", 32'(init_calls), 4);
                check32("four kernel thread startups", 32'(startup_calls), 4);
                check32("real kernel scheduler calls", 32'(schedule_calls), 8);
                check32("thread-mode saves", 32'(switches), 8);
                check32("MRET restores", 32'(restores), 9);
                check32("new thread starts", 32'(fresh_starts), 3);
                check32("saved thread resumes", 32'(resumes), 6);
                check32("C entries", 32'(entries), 3);
                check32("normal kernel exits", 32'(exits), 2);
                check32("deferred interface calls", 32'(irq_requests), 4);
                check32("completed C returns", ram32(symbols[RETURNS]), 2);
                check32("trace length", ram32(symbols[TRACE_COUNT]), 6);
                for (integer id = 1; id <= 2; id++) begin
                    check32("yield calls per worker", 32'(yield_calls[id]), 3);
                    check32("rounds per worker", ram32(symbols[ROUNDS] + 32'((id - 1) * 4)), 3);
                    check32("critical pass per worker", ram32(symbols[CRITICAL] + 32'((id - 1) * 4)), 1);
                end
                for (integer i = 0; i < 6; i++)
                    check32("execution trace", ram32(symbols[TRACE] + 32'(i * 4)),
                            (i[0] ? 32'h200 : 32'h100) | 32'(i / 2 + 1));
                for (integer i = 0; i < 4; i++) begin
                    for (integer id = 1; id <= 3; id++)
                        check32("thread bottom guard", ram32(symbols[STACK_A + id - 1] + 32'(i * 4)),
                                32'ha55a_0000 | 32'(id));
                    check32("main bottom guard", ram32(symbols[GUARD] + 32'(i * 4)), 32'hc0de_cafe);
                end
                check32("startup data cookie", ram32(symbols[COOKIE]), 32'h1357_9bdf);
                check32("request source reset", ram32(symbols[FROM]), 0);
                check32("request target reset", ram32(symbols[TO]), 0);
                check32("request flag reset", ram32(symbols[FLAG]), 0);
                check32("interrupt nesting stays zero",
                        (ram32(symbols[NEST] & ~32'h3) >> (8 * int'(symbols[NEST][1:0]))) & 32'hff, 0);
                check32("final MIE clear", {31'b0, dut.u_cpu.mstatus[3]}, 0);
                if (active) $fatal(1, "Unfinished context switch");
                for (integer id = 0; id < 4; id++) begin
                    if (min_sp[id] == stack_top(id)) $fatal(1, "Stack %0d unused", id);
                    $display("[PASS] stack %0d observed use: %0d bytes", id, stack_top(id) - min_sp[id]);
                end
                $display("[PASS] actual RT-Thread scheduler: 8 saves, 9 restores, 6 yields, 2 normal exits");
                $display(" M11.3 SOC RT-THREAD SCHEDULER PASS");
                $finish;
            end
            @(negedge clk);
            #1;
        end
        $fatal(1, "Scheduler timeout: pc=%08x owner=%0d switches=%0d", pc, owner, switches);
    end
endmodule
