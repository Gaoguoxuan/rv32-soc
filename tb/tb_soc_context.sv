module tb_soc_context;
    localparam logic [31:0] RAM_BASE = 32'h1000_0000;
    localparam logic [31:0] RET = 32'h0000_8067;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [31:0] pc;
    logic uart_tx_valid;
    logic [7:0] uart_tx_data;
    logic [31:0] symbols [0:5];
    logic [31:0] source_regs [0:13];
    logic [31:0] target_regs [0:13];
    logic [31:0] source_ptr;
    logic [31:0] target_ptr;
    logic [31:0] shared_gp;
    logic [31:0] shared_tp;
    logic [31:0] initial_entry [1:2];
    logic [31:0] initial_argument [1:2];
    logic [31:0] min_sp [0:2];
    logic [13:0] save_mask = 14'b0;
    logic [13:0] load_mask = 14'b0;
    logic switching = 1'b0;
    logic finishing_switch;
    logic stack_live = 1'b0;
    logic done = 1'b0;
    logic [31:0] addr;
    logic [31:0] old_instr;
    logic [31:0] old_pc;
    integer source_id = 0;
    integer target_id = 0;
    integer owner = 0;
    integer switches = 0;
    integer bootstrap_entries = 0;
    integer bootstrap_calls = 0;
    integer exit_entries = 0;
    integer uart_lines = 0;
    integer slot;
    integer ram_word;
    string image_path = "build/context/context.hex";
    string symbol_path = "build/context/context.symbols.hex";
    string wave_path = "build/context/context.vcd";
    string uart_line = "";

    rv32_soc #(.ROM_BYTES(65536), .RAM_BYTES(65536)) dut (
        .clk (clk), .rst (rst), .pc (pc),
        .uart_tx_valid (uart_tx_valid), .uart_tx_data (uart_tx_data)
    );

    initial begin
        forever #5 clk = ~clk;
    end

    function automatic integer reg_number(input integer field);
        case (field)
            0: return 1;  // ra
            1: return 2;  // sp
            2: return 8;  // s0
            3: return 9;  // s1
            default: return field + 14;  // s2..s11: x18..x27
        endcase
    endfunction

    function automatic logic [31:0] stack_bottom(input integer id);
        case (id)
            0: return 32'h1000_f800;
            1: return symbols[4] + 32'd16;
            default: return symbols[5] + 32'd16;
        endcase
    endfunction

    function automatic logic [31:0] stack_top(input integer id);
        case (id)
            0: return 32'h1001_0000;
            1: return symbols[4] + 32'd1024;
            default: return symbols[5] + 32'd1024;
        endcase
    endfunction

    function automatic logic stack_valid(input logic [31:0] value, input integer id);
        return value >= stack_bottom(id) && value <= stack_top(id) && value[3:0] == 4'b0;
    endfunction

    function automatic integer expected_source(input integer number);
        if (number == 0) return 0;
        return number[0] ? 1 : 2;
    endfunction

    function automatic integer expected_target(input integer number);
        if (number == 8) return 0;
        return number[0] ? 2 : 1;
    endfunction

    task automatic check32(input string name, input logic [31:0] actual,
                           input logic [31:0] expected);
        if (actual !== expected)
            $fatal(1, "%s: got=%08x expected=%08x pc=%08x owner=%0d switch=%0d",
                   name, actual, expected, pc, owner, switches);
    endtask

    task automatic check_line(input string expected, input integer expected_owner);
        if (uart_line != expected)
            $fatal(1, "UART line %0d: got='%s' expected='%s'", uart_lines, uart_line, expected);
        check32("UART thread ownership", owner, expected_owner);
    endtask

    initial begin
        if ($value$plusargs("image=%s", image_path)) begin end
        if ($value$plusargs("symbols=%s", symbol_path)) begin end
        if ($value$plusargs("wave=%s", wave_path)) begin end
        $dumpfile(wave_path);
        $dumpvars(0, tb_soc_context);
        for (integer i = 0; i < 16384; i++)
            dut.u_ram.mem[i] = 32'hfeed_0000 ^ 32'(i);
        // The same simulator runs independently compiled O0/O2 ROM images.
        // Load before releasing reset, without forcing CPU architectural state.
        #1;
        $readmemh(image_path, dut.u_rom.mem);
        $readmemh(symbol_path, symbols);
        $display("[RUN] %s", image_path);
        check32("thread A stack location", symbols[4], 32'h1000_8000);
        check32("thread B stack location", symbols[5], 32'h1000_9000);
        for (integer id = 0; id < 3; id++)
            min_sp[id] = stack_top(id);
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        #1;

        for (integer cycle = 0; cycle < 200000; cycle++) begin
            old_pc = pc;
            old_instr = dut.instr;
            addr = dut.mem_addr;
            finishing_switch = 1'b0;
            if (pc[1:0] != 2'b0 || pc >= 32'h10000)
                $fatal(1, "Invalid program PC: %08x", pc);
            if (dut.u_cpu.trap_enter || dut.u_cpu.mstatus[3] || dut.u_cpu.mie != 0)
                $fatal(1, "Unexpected trap/interrupt enable at pc=%08x instr=%08x", pc, old_instr);

            if (old_pc == symbols[0]) begin
                if (switching || switches >= 9)
                    $fatal(1, "Unexpected context_switch entry");
                source_id = expected_source(switches);
                target_id = expected_target(switches);
                check32("switch starts in source thread", owner, source_id);
                source_ptr = dut.u_cpu.u_regfile.regs[10];
                target_ptr = dut.u_cpu.u_regfile.regs[11];
                check32("from context", source_ptr, symbols[3] + 32'(source_id * 56));
                check32("to context", target_ptr, symbols[3] + 32'(target_id * 56));
                for (integer i = 0; i < 14; i++) begin
                    source_regs[i] = dut.u_cpu.u_regfile.regs[reg_number(i)];
                    target_regs[i] = dut.u_ram.mem[((target_ptr - RAM_BASE) >> 2) + 32'(i)];
                end
                if (!stack_valid(source_regs[1], source_id) || !stack_valid(target_regs[1], target_id))
                    $fatal(1, "Invalid source/target stack: %08x -> %08x", source_regs[1], target_regs[1]);
                if (target_regs[0][1:0] != 2'b0 || target_regs[0] >= 32'h10000)
                    $fatal(1, "Invalid target return address: %08x", target_regs[0]);
                if (switches < 2) begin
                    check32("new thread starts at bootstrap", target_regs[0], symbols[1]);
                    check32("new thread stack top", target_regs[1], stack_top(target_id));
                    initial_entry[target_id] = target_regs[2];
                    initial_argument[target_id] = target_regs[3];
                    for (integer i = 4; i < 14; i++)
                        check32("new thread register seed", target_regs[i],
                                32'h5a00_0000 | (32'(target_id - 1) << 16) | 32'(i - 2));
                end
                shared_gp = dut.u_cpu.u_regfile.regs[3];
                shared_tp = dut.u_cpu.u_regfile.regs[4];
                save_mask = 14'b0;
                load_mask = 14'b0;
                switching = 1'b1;
            end

            if (switching) begin
                if (dut.mem_we) begin
                    if (addr < source_ptr || addr >= source_ptr + 32'd56 || addr[1:0] != 2'b0)
                        $fatal(1, "Unexpected context store: %08x", addr);
                    slot = int'((addr - source_ptr) >> 2);
                    check32("context store strobe", {28'b0, dut.mem_wstrb}, 32'hf);
                    check32("context store value", dut.mem_wdata, source_regs[slot]);
                    save_mask[slot] = 1'b1;
                end
                if (dut.u_cpu.mem_load) begin
                    if (addr < target_ptr || addr >= target_ptr + 32'd56 || addr[1:0] != 2'b0)
                        $fatal(1, "Unexpected context load: %08x", addr);
                    slot = int'((addr - target_ptr) >> 2);
                    check32("restore destination", {27'b0, old_instr[11:7]}, 32'(reg_number(slot)));
                    check32("restore load value", dut.mem_rdata, target_regs[slot]);
                    check32("restore write enable", {31'b0, dut.u_cpu.rf_we}, 32'd1);
                    load_mask[slot] = 1'b1;
                end
                if (old_instr == RET) begin
                    check32("all context fields saved", {18'b0, save_mask}, 32'h3fff);
                    check32("all context fields restored", {18'b0, load_mask}, 32'h3fff);
                    for (integer i = 0; i < 14; i++) begin
                        check32($sformatf("restored x%0d", reg_number(i)),
                                dut.u_cpu.u_regfile.regs[reg_number(i)], target_regs[i]);
                        check32($sformatf("saved context field %0d", i),
                                dut.u_ram.mem[((source_ptr - RAM_BASE) >> 2) + 32'(i)], source_regs[i]);
                    end
                    check32("shared gp unchanged", dut.u_cpu.u_regfile.regs[3], shared_gp);
                    check32("shared tp unchanged", dut.u_cpu.u_regfile.regs[4], shared_tp);
                    finishing_switch = 1'b1;
                end
            end

            if (old_pc == symbols[1]) begin
                if (owner == 0)
                    $fatal(1, "Main entered thread bootstrap");
                check32("bootstrap stack", dut.u_cpu.u_regfile.regs[2], stack_top(owner));
                check32("bootstrap function", dut.u_cpu.u_regfile.regs[8], initial_entry[owner]);
                check32("bootstrap argument", dut.u_cpu.u_regfile.regs[9], initial_argument[owner]);
                bootstrap_entries++;
            end
            if (old_pc == symbols[1] + 32'd4) begin
                check32("C thread argument a0", dut.u_cpu.u_regfile.regs[10], initial_argument[owner]);
                check32("bootstrap call opcode", old_instr, 32'h0004_00e7);
                bootstrap_calls++;
            end
            if (old_pc == symbols[2]) begin
                check32("thread exit order", owner, exit_entries + 1);
                exit_entries++;
            end

            @(posedge clk);
            #1;
            if (finishing_switch) begin
                check32("switch resumes exact ra", pc, target_regs[0]);
                check32("switch installs target sp", dut.u_cpu.u_regfile.regs[2], target_regs[1]);
                owner = target_id;
                switching = 1'b0;
                switches++;
                $display("[PASS] switch #%0d: %0d -> %0d, pc=%08x sp=%08x",
                         switches, source_id, target_id, pc, target_regs[1]);
            end
            if (old_pc == symbols[1] + 32'd4) begin
                check32("bootstrap calls thread entry", pc, initial_entry[owner]);
                check32("thread C return address", dut.u_cpu.u_regfile.regs[1], symbols[1] + 32'd8);
            end

            if (dut.u_cpu.u_regfile.regs[2] == stack_top(0))
                stack_live = 1'b1;
            if (stack_live) begin
                if (!(switching ? (stack_valid(dut.u_cpu.u_regfile.regs[2], source_id) ||
                                   stack_valid(dut.u_cpu.u_regfile.regs[2], target_id)) :
                                  stack_valid(dut.u_cpu.u_regfile.regs[2], owner)))
                    $fatal(1, "Stack ownership/alignment failed: sp=%08x owner=%0d",
                           dut.u_cpu.u_regfile.regs[2], owner);
                for (integer id = 0; id < 3; id++) begin
                    if (stack_valid(dut.u_cpu.u_regfile.regs[2], id) && dut.u_cpu.u_regfile.regs[2] < min_sp[id])
                        min_sp[id] = dut.u_cpu.u_regfile.regs[2];
                end
            end

            if (uart_tx_valid) begin
                $write("%c", uart_tx_data);
                if (uart_tx_data == 8'h0a) begin
                    case (uart_lines)
                        0: check_line("M10.2 START", 0);
                        1: check_line("A1", 1);
                        2: check_line("B1", 2);
                        3: check_line("A2", 1);
                        4: check_line("B2", 2);
                        5: check_line("A3", 1);
                        6: check_line("B3", 2);
                        7: check_line("CONTEXT PASS", 0);
                        8: begin check_line("M10.2 PASS", 0); done = 1'b1; end
                        default: $fatal(1, "Unexpected UART line");
                    endcase
                    uart_lines++;
                    uart_line = "";
                end
                else
                    uart_line = {uart_line, $sformatf("%c", uart_tx_data)};
            end
            if (done) begin
                check32("switch count", switches, 32'd9);
                check32("fresh thread starts", bootstrap_entries, 32'd2);
                check32("C entry calls", bootstrap_calls, 32'd2);
                check32("thread exits", exit_entries, 32'd2);
                check32("execution returned to main", owner, 32'b0);
                check32("no unfinished switch", {31'b0, switching}, 32'b0);
                for (integer id = 1; id <= 2; id++) begin
                    ram_word = int'((symbols[id + 3] - RAM_BASE) >> 2);
                    for (integer i = 0; i < 4; i++)
                        check32("thread stack guard", dut.u_ram.mem[ram_word + i], 32'ha55a_0000 | 32'(id - 1));
                end
                for (integer id = 0; id < 3; id++) begin
                    if (min_sp[id] == stack_top(id))
                        $fatal(1, "Stack %0d was not exercised", id);
                    $display("[PASS] stack %0d observed use: %0d bytes", id, stack_top(id) - min_sp[id]);
                end
                $display("==============================");
                $display(" M10.2 SOC CONTEXT PASS");
                $display("==============================");
                $finish;
            end
            @(negedge clk);
            #1;
        end
        $fatal(1, "Context timeout: pc=%08x owner=%0d switches=%0d", pc, owner, switches);
    end
endmodule
