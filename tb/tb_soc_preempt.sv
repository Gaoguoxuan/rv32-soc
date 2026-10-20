module tb_soc_preempt;
    localparam logic [31:0] RAM_BASE = 32'h1000_0000;
    localparam logic [31:0] TIMER_BASE = 32'h3000_0000;
    localparam logic [31:0] MRET = 32'h3020_0073;
    localparam logic [32:0] ALL_FIELDS = 33'h1_ffff_ffff;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [31:0] pc;
    logic uart_tx_valid;
    logic [7:0] uart_tx_data;
    // entry, dispatcher, C thread, exit, frames, threads, current, A/B/guard.
    logic [31:0] symbols [0:9];
    // Independent architectural snapshots: x1..x31, mepc, post-entry mstatus.
    logic [31:0] golden [0:2][0:32];
    logic [31:0] frame_ptr [0:2];
    logic [31:0] min_sp [0:2];
    logic [32:0] save_mask;
    logic [32:0] load_mask;
    logic in_handler = 1'b0;
    logic c_called = 1'b0;
    logic c_returned = 1'b0;
    logic status_restored;
    logic epc_restored;
    logic stack_live = 1'b0;
    logic done = 1'b0;
    logic expected_entry;
    logic is_mret;
    logic compare_write;
    logic compare_complete;
    logic old_irq;
    logic [31:0] old_pc;
    logic [31:0] old_instr;
    logic [31:0] address;
    logic [31:0] c_return_pc;
    logic [31:0] target_frame;
    logic [31:0] value;
    logic [31:0] expected_value;
    logic [63:0] old_time;
    logic [63:0] old_compare;
    logic [63:0] previous_deadline = 64'b0;
    integer owner = 0;
    integer source_id = 0;
    integer target_id = 0;
    integer entries = 0;
    integer returns = 0;
    integer c_calls = 0;
    integer c_returns = 0;
    integer switches = 0;
    integer same_returns = 0;
    integer starts = 0;
    integer exits = 0;
    integer irq_rises = 0;
    integer irq_falls = 0;
    integer compare_phase = 0;
    integer compare_sequences = 0;
    integer uart_lines = 0;
    integer slot;
    string image_path = "build/preempt/preempt.hex";
    string symbol_path = "build/preempt/preempt.symbols.hex";
    string wave_path = "build/preempt/preempt.vcd";
    string uart_line = "";

    rv32_soc #(.ROM_BYTES(65536), .RAM_BYTES(65536)) dut (
        .clk (clk), .rst (rst), .pc (pc),
        .uart_tx_valid (uart_tx_valid), .uart_tx_data (uart_tx_data)
    );

    initial begin
        forever #5 clk = ~clk;
    end

    function automatic logic [31:0] ram32(input logic [31:0] addr);
        if (addr < RAM_BASE || addr >= RAM_BASE + 32'h10000 || addr[1:0] != 0)
            $fatal(1, "Invalid monitored RAM address: %08x", addr);
        return dut.u_ram.mem[(addr - RAM_BASE) >> 2];
    endfunction

    function automatic logic [31:0] stack_bottom(input integer id);
        case (id)
            0: return symbols[9] + 32'd16;
            1: return symbols[7] + 32'd16;
            default: return symbols[8] + 32'd16;
        endcase
    endfunction

    function automatic logic [31:0] stack_top(input integer id);
        case (id)
            0: return 32'h1001_0000;
            1: return symbols[7] + 32'd1024;
            default: return symbols[8] + 32'd1024;
        endcase
    endfunction

    function automatic logic stack_valid(input logic [31:0] sp, input integer id);
        return sp >= stack_bottom(id) && sp <= stack_top(id) && sp[3:0] == 0;
    endfunction

    function automatic integer expected_source(input integer number);
        if (number < 2) return 0;
        return number[0] ? 2 : 1;
    endfunction

    function automatic integer expected_target(input integer number);
        if (number == 0 || number == 9) return 0;
        return number[0] ? 1 : 2;
    endfunction

    task automatic check32(input string name, input logic [31:0] actual,
                           input logic [31:0] expected);
        if (actual !== expected)
            $fatal(1, "%s: got=%08x expected=%08x pc=%08x owner=%0d irq=%0d",
                   name, actual, expected, pc, owner, entries);
    endtask

    task automatic check_frame(input integer id);
        for (integer i = 0; i < 33; i++)
            check32($sformatf("thread %0d frame field %0d", id, i),
                    ram32(frame_ptr[id] + 32'(i * 4)), golden[id][i]);
    endtask

    task automatic check_line(input string expected);
        if (uart_line != expected)
            $fatal(1, "UART line %0d: got='%s' expected='%s'", uart_lines, uart_line, expected);
        check32("UART runs on main", owner, 0);
    endtask

    initial begin
        if ($value$plusargs("image=%s", image_path)) begin end
        if ($value$plusargs("symbols=%s", symbol_path)) begin end
        if ($value$plusargs("wave=%s", wave_path)) begin end
        $dumpfile(wave_path);
        $dumpvars(0, tb_soc_preempt);
        for (integer i = 0; i < 16384; i++)
            dut.u_ram.mem[i] = 32'hfeed_0000 ^ 32'(i);
        #1;
        $readmemh(image_path, dut.u_rom.mem);
        $readmemh(symbol_path, symbols);
        $display("[RUN] %s", image_path);
        check32("A stack placement", symbols[7], 32'h1000_8000);
        check32("B stack placement", symbols[8], 32'h1000_9000);
        check32("main guard placement", symbols[9], 32'h1000_f800);
        for (integer id = 0; id < 3; id++)
            min_sp[id] = stack_top(id);
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        #1;

        for (integer cycle = 0; cycle < 300000; cycle++) begin
            old_pc = pc;
            old_instr = dut.instr;
            address = dut.mem_addr;
            old_irq = dut.timer_irq;
            old_time = dut.u_timer.mtime;
            old_compare = dut.u_timer.mtimecmp;
            expected_entry = old_irq && dut.u_cpu.mstatus[3] && dut.u_cpu.mie[7];
            is_mret = old_instr == MRET;
            compare_write = dut.mem_we && address >= TIMER_BASE + 32'd8 &&
                            address <= TIMER_BASE + 32'd15;
            compare_complete = 1'b0;

            if (pc[1:0] != 0 || pc >= 32'h10000)
                $fatal(1, "Invalid instruction PC: %08x", pc);
            check32("MTIP follows real timer", dut.u_cpu.mip, old_irq ? 32'h80 : 0);
            check32("only enabled real timer causes entry", {31'b0, dut.u_cpu.trap_enter},
                    {31'b0, expected_entry});
            if (in_handler && dut.u_cpu.mstatus[3])
                $fatal(1, "Interrupts enabled before the full restore/MRET");

            if (expected_entry) begin
                if (in_handler || entries >= 10)
                    $fatal(1, "Unexpected extra/nested interrupt");
                source_id = expected_source(entries);
                target_id = expected_target(entries);
                check32("interrupted owner", owner, source_id);
                check32("software current", ram32(symbols[6]), 32'(owner));
                for (integer reg_num = 1; reg_num < 32; reg_num++)
                    golden[owner][reg_num - 1] = dut.u_cpu.u_regfile.regs[reg_num];
                golden[owner][31] = old_pc;
                golden[owner][32] = (dut.u_cpu.mstatus & ~32'h1888) | 32'h1880;
                frame_ptr[owner] = golden[owner][1] - 32'd144;
                if (!stack_valid(frame_ptr[owner], owner))
                    $fatal(1, "No aligned room for full trap frame");
                check32("entry vector", dut.u_cpu.mtvec, symbols[0]);
                check32("entry cancels instruction writes",
                        {29'b0, dut.u_cpu.rf_we, dut.u_cpu.csr_we, dut.mem_we}, 0);
                check32("previous mtval", dut.u_cpu.mtval,
                        entries == 0 ? 32'h89ab_cdef : 0);
                save_mask = 0;
                load_mask = 0;
                c_called = 1'b0;
                c_returned = 1'b0;
                status_restored = 1'b0;
                epc_restored = 1'b0;
                in_handler = 1'b1;
                entries++;
            end

            if (in_handler && !expected_entry && !c_called && dut.mem_we) begin
                if (address < frame_ptr[owner] || address >= frame_ptr[owner] + 32'd132 ||
                    address[1:0] != 0)
                    $fatal(1, "Unexpected assembly save address: %08x", address);
                slot = int'((address - frame_ptr[owner]) >> 2);
                check32("frame save strobe", {28'b0, dut.mem_wstrb}, 32'hf);
                check32("frame save value", dut.mem_wdata, golden[owner][slot]);
                save_mask[slot] = 1'b1;
            end

            if (in_handler && !expected_entry && old_pc == symbols[1]) begin
                if (c_called || save_mask !== ALL_FIELDS)
                    $fatal(1, "Dispatcher entered before complete frame save");
                check_frame(owner);
                check32("dispatch frame argument", dut.u_cpu.u_regfile.regs[10], frame_ptr[owner]);
                check32("dispatch cause", dut.u_cpu.u_regfile.regs[11], 32'h8000_0007);
                check32("dispatch tval", dut.u_cpu.u_regfile.regs[12], 0);
                check32("C entry sp", dut.u_cpu.u_regfile.regs[2], frame_ptr[owner]);
                c_return_pc = dut.u_cpu.u_regfile.regs[1];
                c_called = 1'b1;
                c_calls++;
                if (entries == 1) begin
                    for (integer id = 1; id <= 2; id++) begin
                        frame_ptr[id] = ram32(symbols[4] + 32'(id * 4));
                        check32("initial frame placement", frame_ptr[id], stack_top(id) - 32'd144);
                        for (integer reg_num = 1; reg_num < 32; reg_num++) begin
                            case (reg_num)
                                1: expected_value = symbols[3];
                                2: expected_value = stack_top(id);
                                3, 4: expected_value = golden[0][reg_num - 1];
                                10: expected_value = symbols[5] + 32'((id - 1) * 20);
                                default: expected_value = 32'h5a00_0000 | (32'(id) << 16) | 32'(reg_num);
                            endcase
                            golden[id][reg_num - 1] = expected_value;
                        end
                        golden[id][31] = symbols[2];
                        golden[id][32] = 32'h1880;
                        check_frame(id);
                    end
                end
            end

            if (in_handler && c_called && !c_returned && old_pc == c_return_pc) begin
                check32("C return balances source stack", dut.u_cpu.u_regfile.regs[2], frame_ptr[owner]);
                check_frame(owner);
                check32("C publishes saved source frame", ram32(symbols[4] + 32'(owner * 4)), frame_ptr[owner]);
                target_frame = dut.u_cpu.u_regfile.regs[10];
                check32("dispatcher returns target frame", target_frame, frame_ptr[target_id]);
                check32("dispatcher updates current", ram32(symbols[6]), 32'(target_id));
                check_frame(target_id);
                c_returned = 1'b1;
                c_returns++;
            end

            if (in_handler && c_returned && dut.u_cpu.mem_load) begin
                if (address < target_frame || address >= target_frame + 32'd132 || address[1:0] != 0)
                    $fatal(1, "Restore reads outside target frame: %08x", address);
                slot = int'((address - target_frame) >> 2);
                check32("restore destination", {27'b0, old_instr[11:7]}, slot >= 31 ? 5 : 32'(slot + 1));
                check32("restore value", dut.mem_rdata, golden[target_id][slot]);
                check32("restore register write enabled", {31'b0, dut.u_cpu.rf_we}, 1);
                load_mask[slot] = 1'b1;
            end
            if (in_handler && c_returned && dut.u_cpu.csr_we) begin
                case (old_instr[31:20])
                    12'h300: begin
                        check32("restore mstatus CSR value", dut.u_cpu.csr_wdata,
                                golden[target_id][32] & ~32'h8);
                        status_restored = 1'b1;
                    end
                    12'h341: begin
                        check32("restore mepc CSR value", dut.u_cpu.csr_wdata, golden[target_id][31]);
                        epc_restored = 1'b1;
                    end
                    default: $fatal(1, "Unexpected CSR restore");
                endcase
            end

            if (is_mret) begin
                if (!in_handler || !c_returned || load_mask !== ALL_FIELDS ||
                    !epc_restored || !status_restored)
                    $fatal(1, "Incomplete context restore before MRET");
                for (integer reg_num = 1; reg_num < 32; reg_num++)
                    check32($sformatf("restored thread %0d x%0d", target_id, reg_num),
                            dut.u_cpu.u_regfile.regs[reg_num], golden[target_id][reg_num - 1]);
                check32("restored target mepc", dut.u_cpu.mepc, golden[target_id][31]);
                check32("MRET selected", {31'b0, dut.u_cpu.mret_enter}, 1);
                check32("target status before MRET", dut.u_cpu.mstatus, golden[target_id][32]);
                check32("timer pending cleared before return", dut.u_cpu.mip, 0);
                check32("MTIE at return", dut.u_cpu.mie, entries == 10 ? 0 : 32'h80);
            end
            if (!in_handler && !expected_entry && old_pc == symbols[2]) begin
                check32("fresh C entry argument", dut.u_cpu.u_regfile.regs[10], symbols[5] + 32'((owner - 1) * 20));
                check32("fresh C entry return address", dut.u_cpu.u_regfile.regs[1], symbols[3]);
                starts++;
            end
            if (!in_handler && !expected_entry && old_pc == symbols[3]) begin
                check32("thread exit order", 32'(owner), 32'(exits + 1));
                exits++;
            end

            if (dut.mem_we && address >= TIMER_BASE && address < TIMER_BASE + 32'd8)
                $fatal(1, "Firmware wrote mtime");
            if (compare_write) begin
                check32("compare strobe", {28'b0, dut.mem_wstrb}, 32'hf);
                case (compare_phase)
                    0: begin
                        check32("compare low first", address, TIMER_BASE + 32'd8);
                        check32("compare low=-1", dut.mem_wdata, 32'hffff_ffff);
                        compare_phase = 1;
                    end
                    1: begin
                        check32("compare high second", address, TIMER_BASE + 32'd12);
                        compare_phase = 2;
                    end
                    2: begin
                        check32("compare low last", address, TIMER_BASE + 32'd8);
                        compare_phase = 0;
                        compare_sequences++;
                        compare_complete = 1'b1;
                    end
                    default: $fatal(1, "Invalid compare phase");
                endcase
            end

            @(posedge clk);
            #1;
            if (dut.u_timer.mtime !== old_time + 64'd1)
                $fatal(1, "mtime did not increment");
            if (expected_entry) begin
                check32("entry PC", pc, symbols[0]);
                check32("entry mepc", dut.u_cpu.mepc, golden[source_id][31]);
                check32("entry mcause", dut.u_cpu.mcause, 32'h8000_0007);
                check32("entry mtval cleared", dut.u_cpu.mtval, 0);
                check32("entry status", dut.u_cpu.mstatus, golden[source_id][32]);
                for (integer reg_num = 1; reg_num < 32; reg_num++)
                    check32("entry preserves GPR", dut.u_cpu.u_regfile.regs[reg_num],
                            golden[source_id][reg_num - 1]);
            end
            if (!old_irq && dut.timer_irq) begin
                if (compare_write || dut.u_timer.mtimecmp !== old_compare ||
                    dut.u_timer.mtime !== old_compare)
                    $fatal(1, "IRQ did not arise at the real timer deadline");
                irq_rises++;
            end
            if (old_irq && !dut.timer_irq) begin
                if (!compare_write || dut.u_timer.mtimecmp <= dut.u_timer.mtime)
                    $fatal(1, "IRQ cleared without programming a future deadline");
                irq_falls++;
            end
            if (compare_complete) begin
                if (compare_sequences <= 10) begin
                    if (dut.u_timer.mtimecmp <= dut.u_timer.mtime ||
                        (compare_sequences > 1 && dut.u_timer.mtimecmp !== previous_deadline + 64'd8192))
                        $fatal(1, "Timer period/deadline mismatch");
                    previous_deadline = dut.u_timer.mtimecmp;
                end else if (compare_sequences != 11 || dut.u_timer.mtimecmp !== 64'hffff_ffff_ffff_ffff)
                    $fatal(1, "Final timer comparator was not disarmed");
            end
            if (is_mret) begin
                check32("MRET resumes exact target PC", pc, golden[target_id][31]);
                check32("MRET restores MIE from MPIE", dut.u_cpu.mstatus, 32'h1888);
                if (source_id == target_id) same_returns++;
                else switches++;
                owner = target_id;
                in_handler = 1'b0;
                returns++;
                $display("[PASS] IRQ #%0d: %0d -> %0d, 31 GPRs + mepc + mstatus, pc=%08x sp=%08x",
                         entries, source_id, target_id, pc, dut.u_cpu.u_regfile.regs[2]);
            end

            value = dut.u_cpu.u_regfile.regs[2];
            if (value == stack_top(0)) stack_live = 1'b1;
            if (stack_live) begin
                if (!(in_handler && c_returned ?
                      (stack_valid(value, source_id) || stack_valid(value, target_id)) :
                      stack_valid(value, owner)))
                    $fatal(1, "Stack owner/range/alignment: sp=%08x owner=%0d", value, owner);
                for (integer id = 0; id < 3; id++)
                    if (stack_valid(value, id) && value < min_sp[id]) min_sp[id] = value;
            end
            if (uart_tx_valid) begin
                $write("%c", uart_tx_data);
                if (uart_tx_data == 8'h0a) begin
                    case (uart_lines)
                        0: check_line("M10.3 START");
                        1: check_line("A COMPUTE PASS");
                        2: check_line("B COMPUTE PASS");
                        3: check_line("PREEMPT CONTEXT PASS");
                        4: begin check_line("M10.3 PASS"); done = 1'b1; end
                        default: $fatal(1, "Unexpected UART line");
                    endcase
                    uart_lines++;
                    uart_line = "";
                end else uart_line = {uart_line, $sformatf("%c", uart_tx_data)};
            end
            if (done) begin
                check32("timer entries", 32'(entries), 10);
                check32("MRET count", 32'(returns), 10);
                check32("C calls", 32'(c_calls), 10);
                check32("C returns", 32'(c_returns), 10);
                check32("real IRQ rises", 32'(irq_rises), 10);
                check32("real IRQ clears", 32'(irq_falls), 10);
                check32("cross-thread switches", 32'(switches), 9);
                check32("same-frame return", 32'(same_returns), 1);
                check32("fresh C thread entries", 32'(starts), 2);
                check32("normal C thread exits", 32'(exits), 2);
                check32("compare sequences", 32'(compare_sequences), 11);
                check32("compare phase", 32'(compare_phase), 0);
                check32("main resumed", 32'(owner), 0);
                check32("no active handler", {31'b0, in_handler}, 0);
                check32("final MTIE", dut.u_cpu.mie, 0);
                check32("final MIE", {31'b0, dut.u_cpu.mstatus[3]}, 0);
                check32("final pending", dut.u_cpu.mip, 0);
                for (integer i = 0; i < 4; i++) begin
                    check32("A guard", ram32(symbols[7] + 32'(i * 4)), 32'ha55a_0001);
                    check32("B guard", ram32(symbols[8] + 32'(i * 4)), 32'ha55a_0002);
                    check32("main guard", ram32(symbols[9] + 32'(i * 4)), 32'hc0de_cafe);
                end
                for (integer id = 0; id < 3; id++) begin
                    if (min_sp[id] == stack_top(id)) $fatal(1, "Unused stack %0d", id);
                    $display("[PASS] stack %0d observed use: %0d bytes", id, stack_top(id) - min_sp[id]);
                end
                $display(" M10.3 SOC PREEMPT PASS");
                $finish;
            end
            @(negedge clk);
            #1;
        end
        $fatal(1, "Preempt timeout: pc=%08x owner=%0d entries=%0d", pc, owner, entries);
    end
endmodule
