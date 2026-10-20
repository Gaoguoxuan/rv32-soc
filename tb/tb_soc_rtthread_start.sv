module tb_soc_rtthread_start;
    localparam logic [31:0] RAM_BASE = 32'h1000_0000;
    localparam logic [31:0] UART_TX = 32'h2000_0000;
    localparam logic [31:0] MRET = 32'h3020_0073;
    localparam logic [32:0] ALL_FIELDS = 33'h1_ffff_ffff;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [31:0] pc;
    logic uart_tx_valid;
    logic [7:0] uart_tx_data;
    // init, switch_to, entry, exit, probe, A/B stacks, args, current, entries,
    // exits, cookie, main guard, main stack bounds.
    logic [31:0] symbols [0:14];
    logic [31:0] initial_fields [0:35];
    logic [31:0] live_fields [1:2][0:35];
    logic [31:0] live_frames [1:2];
    logic [31:0] target_fields [0:32];
    logic [31:0] min_sp [0:2];
    logic [15:0] alignment_coverage = 16'b0;
    logic [32:0] load_mask;
    logic ctor_active = 1'b0;
    logic switching = 1'b0;
    logic indirect_loaded;
    logic epc_restored;
    logic status_restored;
    logic stack_live = 1'b0;
    logic done = 1'b0;
    logic [31:0] ctor_return_pc;
    logic [31:0] ctor_sp;
    logic [31:0] ctor_status;
    logic [31:0] ctor_top;
    logic [31:0] ctor_frame;
    logic [31:0] pointer_location;
    logic [31:0] frame_base;
    logic [31:0] old_pc;
    logic [31:0] old_instr;
    logic [31:0] address;
    logic [31:0] sp_value;
    logic [63:0] old_time;
    logic is_mret;
    integer owner = 0;
    integer source_id;
    integer target_id;
    integer ctors = 0;
    integer ctor_returns = 0;
    integer restores = 0;
    integer entries = 0;
    integer exits = 0;
    integer uart_lines = 0;
    integer slot;
    string image_path = "build/rtthread_start/rtthread_start.hex";
    string symbol_path = "build/rtthread_start/rtthread_start.symbols.hex";
    string wave_path = "build/rtthread_start/rtthread_start.vcd";
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

    function automatic logic [31:0] stack_top(input integer id);
        case (id)
            0: return symbols[14];
            1: return symbols[5] + 32'd1024;
            default: return symbols[6] + 32'd1008;
        endcase
    endfunction

    function automatic logic stack_valid(input logic [31:0] value, input integer id);
        logic [31:0] bottom;
        case (id)
            0: bottom = symbols[13];
            1: bottom = symbols[5] + 32'd16;
            default: bottom = symbols[6] + 32'd16;
        endcase
        return value >= bottom && value <= stack_top(id) && value[3:0] == 0;
    endfunction

    task automatic check32(input string name, input logic [31:0] actual,
                           input logic [31:0] expected);
        if (actual !== expected)
            $fatal(1, "%s: got=%08x expected=%08x pc=%08x owner=%0d",
                   name, actual, expected, pc, owner);
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
        $dumpvars(0, tb_soc_rtthread_start);
        for (integer i = 0; i < 16384; i++)
            dut.u_ram.mem[i] = 32'hfeed_0000 ^ 32'(i);
        #1;
        $readmemh(image_path, dut.u_rom.mem);
        $readmemh(symbol_path, symbols);
        $display("[RUN] %s", image_path);
        check32("A stack placement", symbols[5], 32'h1000_8000);
        check32("B stack placement", symbols[6], 32'h1000_9000);
        for (integer id = 0; id < 3; id++) min_sp[id] = stack_top(id);
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        #1;

        for (integer cycle = 0; cycle < 500000; cycle++) begin
            old_pc = pc;
            old_instr = dut.instr;
            old_time = dut.u_timer.mtime;
            address = dut.mem_addr;
            is_mret = old_instr == MRET;
            if (pc[1:0] != 0 || pc >= 32'h10000)
                $fatal(1, "Invalid PC: %08x", pc);
            if (dut.u_cpu.trap_enter)
                $fatal(1, "Unexpected trap: pc=%08x instr=%08x cause=%08x",
                       pc, old_instr, dut.u_cpu.trap_cause);
            check32("timer interrupt remains disabled", dut.u_cpu.mie, 0);
            check32("no pending timer", dut.u_cpu.mip, 0);
            if (dut.mem_we && !(address >= RAM_BASE && address < RAM_BASE + 32'h10000) &&
                address != UART_TX)
                $fatal(1, "Unexpected MMIO/ROM store: %08x", address);

            if (old_pc == symbols[0]) begin
                if (ctor_active || ctors >= 18 || owner != 0)
                    $fatal(1, "Unexpected stack constructor call");
                ctor_return_pc = dut.u_cpu.u_regfile.regs[1];
                ctor_sp = dut.u_cpu.u_regfile.regs[2];
                ctor_status = dut.u_cpu.mstatus;
                check32("constructor entry function", dut.u_cpu.u_regfile.regs[10], symbols[2]);
                check32("constructor exit function", dut.u_cpu.u_regfile.regs[13], symbols[3]);
                if (ctors < 16) begin
                    check32("probe end offset", dut.u_cpu.u_regfile.regs[12], symbols[4] + 32'd252 + 32'(ctors));
                    check32("probe argument", dut.u_cpu.u_regfile.regs[11], symbols[7] + (ctors[0] ? 32'd8 : 0));
                    ctor_top = symbols[4] + 32'd256;
                end else begin
                    target_id = ctors - 15;
                    ctor_top = stack_top(target_id);
                    check32("live stack address convention", dut.u_cpu.u_regfile.regs[12],
                            target_id == 1 ? symbols[5] + 32'd1020 : symbols[6] + 32'd1016);
                    check32("live argument", dut.u_cpu.u_regfile.regs[11], symbols[7] + 32'((target_id - 1) * 8));
                end
                ctor_frame = ctor_top - 32'd144;
                for (integer i = 0; i < 36; i++) initial_fields[i] = 0;
                initial_fields[0] = symbols[3];
                initial_fields[1] = ctor_top;
                initial_fields[2] = dut.u_cpu.u_regfile.regs[3];
                initial_fields[3] = dut.u_cpu.u_regfile.regs[4];
                initial_fields[9] = dut.u_cpu.u_regfile.regs[11];
                initial_fields[31] = symbols[2];
                initial_fields[32] = 32'h1880;
                ctor_active = 1'b1;
                ctors++;
            end
            if (ctor_active && old_pc == ctor_return_pc) begin
                check32("constructor returns frame pointer", dut.u_cpu.u_regfile.regs[10], ctor_frame);
                check32("constructor balances stack", dut.u_cpu.u_regfile.regs[2], ctor_sp);
                check32("constructor preserves status", dut.u_cpu.mstatus, ctor_status);
                for (integer i = 0; i < 36; i++)
                    check32($sformatf("initial frame word %0d", i), ram32(ctor_frame + 32'(i * 4)), initial_fields[i]);
                if (ctors <= 16) alignment_coverage[ctors - 1] = 1'b1;
                else begin
                    live_frames[ctors - 16] = ctor_frame;
                    for (integer i = 0; i < 36; i++) live_fields[ctors - 16][i] = initial_fields[i];
                end
                ctor_active = 1'b0;
                ctor_returns++;
            end

            if (old_pc == symbols[1]) begin
                if (switching || restores >= 2 || ctor_returns != 18)
                    $fatal(1, "Unexpected first-restore call");
                source_id = owner;
                target_id = restores + 1;
                check32("first restore source owner", 32'(owner), 32'(restores));
                check32("software target selection", ram32(symbols[8]), 32'(target_id));
                check32("caller deliberately has MIE set", dut.u_cpu.mstatus, 32'h1888);
                pointer_location = dut.u_cpu.u_regfile.regs[10];
                frame_base = live_frames[target_id];
                if (pointer_location == frame_base)
                    $fatal(1, "switch_to received a frame instead of &thread->sp");
                check32("thread sp field contains frame pointer", ram32(pointer_location), frame_base);
                for (integer i = 0; i < 33; i++) begin
                    target_fields[i] = live_fields[target_id][i];
                    if (i == 32 && target_id == 2) target_fields[i] |= 32'h8;
                    check32("target frame intact", ram32(frame_base + 32'(i * 4)), target_fields[i]);
                end
                indirect_loaded = 1'b0;
                epc_restored = 1'b0;
                status_restored = 1'b0;
                load_mask = 0;
                switching = 1'b1;
            end
            if (switching) begin
                if (old_pc != symbols[1] && dut.u_cpu.mstatus[3])
                    $fatal(1, "MIE was enabled during context restore");
                if (dut.mem_we) $fatal(1, "First restore unexpectedly stores memory");
                if (dut.u_cpu.mem_load) begin
                    check32("restore load commits", {31'b0, dut.u_cpu.rf_we}, 1);
                    if (!indirect_loaded) begin
                        check32("indirect frame lookup address", address, pointer_location);
                        check32("indirect lookup installs sp", {27'b0, old_instr[11:7]}, 2);
                        check32("indirect lookup data", dut.mem_rdata, frame_base);
                        indirect_loaded = 1'b1;
                    end else begin
                        if (address < frame_base || address >= frame_base + 32'd132 || address[1:0] != 0)
                            $fatal(1, "Restore reads outside saved fields: %08x", address);
                        slot = int'((address - frame_base) >> 2);
                        check32("restore field destination", {27'b0, old_instr[11:7]}, slot >= 31 ? 5 : 32'(slot + 1));
                        check32("restore field data", dut.mem_rdata, target_fields[slot]);
                        load_mask[slot] = 1'b1;
                    end
                end
                if (dut.u_cpu.csr_we) begin
                    case (old_instr[31:20])
                        12'h300: begin
                            check32("restore writes mstatus with MIE clear", dut.u_cpu.csr_wdata,
                                    indirect_loaded ? target_fields[32] & ~32'h8 : 32'h1880);
                            if (indirect_loaded) status_restored = 1'b1;
                        end
                        12'h341: begin
                            check32("restore writes target mepc", dut.u_cpu.csr_wdata, target_fields[31]);
                            epc_restored = 1'b1;
                        end
                        default: $fatal(1, "Unexpected CSR restore");
                    endcase
                end
            end
            if (is_mret) begin
                if (!switching || !indirect_loaded || !epc_restored ||
                    !status_restored || load_mask !== ALL_FIELDS)
                    $fatal(1, "Incomplete register/CSR restore before MRET");
                for (integer reg_num = 1; reg_num < 32; reg_num++)
                    check32($sformatf("restored x%0d", reg_num), dut.u_cpu.u_regfile.regs[reg_num], target_fields[reg_num - 1]);
                check32("MRET target", dut.u_cpu.mepc, symbols[2]);
                check32("MRET status", dut.u_cpu.mstatus, 32'h1880);
                check32("MRET selected", {31'b0, dut.u_cpu.mret_enter}, 1);
            end
            if (!switching && old_pc == symbols[2]) begin
                check32("C entry order", 32'(owner), 32'(entries + 1));
                check32("C entry parameter", dut.u_cpu.u_regfile.regs[10], symbols[7] + 32'((owner - 1) * 8));
                check32("C entry return address", dut.u_cpu.u_regfile.regs[1], symbols[3]);
                check32("C entry stack", dut.u_cpu.u_regfile.regs[2], stack_top(owner));
                entries++;
            end
            if (!switching && old_pc == symbols[3]) begin
                check32("normal return reaches supplied exit", 32'(owner), 32'(exits + 1));
                check32("normal return balances thread stack", dut.u_cpu.u_regfile.regs[2], stack_top(owner));
                check32("software C entry completed", ram32(symbols[9]), 32'(owner));
                exits++;
            end

            @(posedge clk);
            #1;
            if (dut.u_timer.mtime !== old_time + 64'd1)
                $fatal(1, "mtime did not advance");
            if (is_mret) begin
                check32("MRET enters thread", pc, target_fields[31]);
                check32("MRET enables target MIE", dut.u_cpu.mstatus, 32'h1888);
                check32("MRET uses target stack", dut.u_cpu.u_regfile.regs[2], target_fields[1]);
                owner = target_id;
                switching = 1'b0;
                restores++;
                $display("[PASS] first restore #%0d: all 31 GPRs, pc=%08x sp=%08x", restores, pc, target_fields[1]);
            end
            sp_value = dut.u_cpu.u_regfile.regs[2];
            if (sp_value == symbols[14]) stack_live = 1'b1;
            if (stack_live) begin
                if (!(switching ? (stack_valid(sp_value, source_id) || stack_valid(sp_value, target_id)) :
                                   stack_valid(sp_value, owner)))
                    $fatal(1, "Stack ownership/alignment: sp=%08x owner=%0d", sp_value, owner);
                for (integer id = 0; id < 3; id++)
                    if (stack_valid(sp_value, id) && sp_value < min_sp[id]) min_sp[id] = sp_value;
            end
            if (uart_tx_valid) begin
                $write("%c", uart_tx_data);
                if (uart_tx_data == 8'h0a) begin
                    case (uart_lines)
                        0: check_line("M11.2 START", 0);
                        1: check_line("STACK FRAME PASS", 0);
                        2: check_line("THREAD A START", 1);
                        3: check_line("THREAD A RETURN", 1);
                        4: check_line("THREAD B START", 2);
                        5: check_line("THREAD B RETURN", 2);
                        6: check_line("STACK GUARD PASS", 2);
                        7: begin check_line("M11.2 PASS", 2); done = 1'b1; end
                        default: $fatal(1, "Unexpected UART line");
                    endcase
                    uart_lines++;
                    uart_line = "";
                end else uart_line = {uart_line, $sformatf("%c", uart_tx_data)};
            end
            if (done) begin
                check32("constructor calls", 32'(ctors), 18);
                check32("constructor returns", 32'(ctor_returns), 18);
                check32("all 16 stack ends exercised", {16'b0, alignment_coverage}, 32'hffff);
                check32("complete context restores", 32'(restores), 2);
                check32("C thread entries", 32'(entries), 2);
                check32("C thread exits", 32'(exits), 2);
                check32("software thread exits", ram32(symbols[10]), 2);
                check32("startup data cookie", ram32(symbols[11]), 32'h1357_9bdf);
                check32("final MIE clear", {31'b0, dut.u_cpu.mstatus[3]}, 0);
                for (integer i = 0; i < 4; i++) begin
                    check32("A bottom guard", ram32(symbols[5] + 32'(i * 4)), 32'ha55a_0001);
                    check32("B bottom guard", ram32(symbols[6] + 32'(i * 4)), 32'ha55a_0002);
                    check32("B unused tail", ram32(symbols[6] + 32'd1008 + 32'(i * 4)), 32'hcdcd_cdcd);
                    check32("main guard", ram32(symbols[12] + 32'(i * 4)), 32'hc0de_cafe);
                end
                if (switching || ctor_active) $fatal(1, "Unfinished constructor/restore");
                for (integer id = 0; id < 3; id++) begin
                    if (min_sp[id] == stack_top(id)) $fatal(1, "Stack %0d unused", id);
                    $display("[PASS] stack %0d observed use: %0d bytes", id, stack_top(id) - min_sp[id]);
                end
                $display("[PASS] 16 stack-end offsets, 18 complete frames, two MRET starts and normal C returns");
                $display(" M11.2 SOC RT-THREAD START PASS");
                $finish;
            end
            @(negedge clk);
            #1;
        end
        $fatal(1, "First-start timeout: pc=%08x constructors=%0d restores=%0d", pc, ctors, restores);
    end
endmodule
