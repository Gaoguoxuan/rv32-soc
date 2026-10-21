module tb_soc_rtthread;
    localparam logic [31:0] RAM_BASE = 32'h1000_0000;
    localparam logic [31:0] UART_TX = 32'h2000_0000;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [31:0] pc;
    logic uart_tx_valid;
    logic [7:0] uart_tx_data;
    // show_version, kprintf, console, IRQ disable/enable, cookie, stage, guard, bounds.
    logic [31:0] symbols [0:9];
    logic [31:0] min_sp;
    logic stack_live = 1'b0;
    logic done = 1'b0;
    logic port_active = 1'b0;
    logic [1:0] disabled_coverage = 2'b0;
    logic [31:0] port_return_pc;
    logic [31:0] port_sp;
    logic [31:0] port_status;
    logic [31:0] port_expected_status;
    logic [31:0] old_pc;
    logic [7:0] old_uart_data;
    logic uart_write;
    logic [63:0] old_time;
    integer port_kind;
    integer disables = 0;
    integer enables = 0;
    integer port_returns = 0;
    integer version_calls = 0;
    integer printf_calls = 0;
    integer console_calls = 0;
    integer uart_lines = 0;
    integer uart_bytes = 0;
    string image_path = "build/rtthread/rtthread.hex";
    string symbol_path = "build/rtthread/rtthread.symbols.hex";
    string wave_path = "build/rtthread/rtthread.vcd";
    string uart_line = "";
    string version_prefix = " / | \\     4.1.1 build ";

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
            $fatal(1, "%s: got=%08x expected=%08x pc=%08x",
                   name, actual, expected, pc);
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
        $dumpvars(0, tb_soc_rtthread);
        for (integer i = 0; i < 16384; i++)
            dut.u_ram.mem[i] = 32'hfeed_0000 ^ 32'(i);
        #1;
        $readmemh(image_path, dut.u_rom.mem);
        $readmemh(symbol_path, symbols);
        min_sp = symbols[9];
        $display("[RUN] %s", image_path);
        check32("stack top", symbols[9], 32'h1001_0000);
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        #1;

        for (integer cycle = 0; cycle < 500000; cycle++) begin
            old_pc = pc;
            old_uart_data = dut.mem_wdata[7:0];
            old_time = dut.u_timer.mtime;
            uart_write = dut.mem_we && dut.mem_addr == UART_TX && dut.mem_wstrb[0];
            if (pc[1:0] != 0 || pc >= 32'h10000)
                $fatal(1, "Invalid program PC: %08x", pc);
            if (dut.u_cpu.trap_enter)
                $fatal(1, "Unexpected trap: pc=%08x instr=%08x cause=%08x",
                       pc, dut.instr, dut.u_cpu.trap_cause);
            check32("timer source remains masked", dut.u_cpu.mie, 0);
            check32("timer stays disarmed", dut.u_cpu.mip, 0);
            if (dut.mem_we && !(dut.mem_addr >= RAM_BASE && dut.mem_addr < RAM_BASE + 32'h10000) &&
                dut.mem_addr != UART_TX)
                $fatal(1, "Unexpected MMIO/ROM store: %08x", dut.mem_addr);
            if (uart_write)
                check32("UART word write", {28'b0, dut.mem_wstrb}, 32'hf);

            if (old_pc == symbols[0]) version_calls++;
            if (old_pc == symbols[1]) begin
                printf_calls++;
                if (printf_calls == 8) begin
                    for (integer i = 1; i <= 7; i++)
                        check32("variadic register argument", dut.u_cpu.u_regfile.regs[10 + i], 32'(i));
                    for (integer i = 0; i < 3; i++)
                        check32("variadic stack argument",
                                ram32(dut.u_cpu.u_regfile.regs[2] + 32'(i * 4)), 32'(i + 8));
                end
            end
            if (old_pc == symbols[2]) begin
                console_calls++;
                if (dut.u_cpu.u_regfile.regs[10] < RAM_BASE ||
                    dut.u_cpu.u_regfile.regs[10] >= RAM_BASE + 32'h10000)
                    $fatal(1, "Console did not receive the formatted RAM buffer");
            end
            if (old_pc == symbols[3] || old_pc == symbols[4]) begin
                if (port_active) $fatal(1, "Overlapping IRQ port calls");
                check32("IRQ checks run in their test phase", ram32(symbols[6]), 2);
                port_active = 1'b1;
                port_kind = old_pc == symbols[3] ? 1 : 2;
                port_return_pc = dut.u_cpu.u_regfile.regs[1];
                port_sp = dut.u_cpu.u_regfile.regs[2];
                port_status = dut.u_cpu.mstatus;
                port_expected_status = port_status & ~32'h8;
                if (port_kind == 1) begin
                    disables++;
                    disabled_coverage[port_status[3]] = 1'b1;
                end else begin
                    enables++;
                    port_expected_status |= dut.u_cpu.u_regfile.regs[10] & 32'h8;
                end
            end
            if (port_active && old_pc == port_return_pc) begin
                check32("IRQ port restores caller stack", dut.u_cpu.u_regfile.regs[2], port_sp);
                check32("IRQ port changes only MIE", dut.u_cpu.mstatus, port_expected_status);
                if (port_kind == 1)
                    check32("IRQ port returns saved MIE", dut.u_cpu.u_regfile.regs[10], port_status & 32'h8);
                port_active = 1'b0;
                port_returns++;
            end

            @(posedge clk);
            #1;
            if (dut.u_timer.mtime !== old_time + 64'd1)
                $fatal(1, "mtime stopped during console execution");
            check32("UART valid follows real MMIO write", {31'b0, uart_tx_valid}, {31'b0, uart_write});
            if (uart_tx_valid)
                check32("UART byte follows MMIO data", {24'b0, uart_tx_data}, {24'b0, old_uart_data});
            if (dut.u_cpu.u_regfile.regs[2] == symbols[9]) stack_live = 1'b1;
            if (stack_live) begin
                if (dut.u_cpu.u_regfile.regs[2] < symbols[8] ||
                    dut.u_cpu.u_regfile.regs[2] > symbols[9] || dut.u_cpu.u_regfile.regs[2][3:0] != 0)
                    $fatal(1, "Stack range/alignment failed: sp=%08x pc=%08x",
                           dut.u_cpu.u_regfile.regs[2], pc);
                if (dut.u_cpu.u_regfile.regs[2] < min_sp) min_sp = dut.u_cpu.u_regfile.regs[2];
            end
            if (uart_tx_valid) begin
                uart_bytes++;
                $write("%c", uart_tx_data);
                if (uart_tx_data == 8'h0a) begin
                    case (uart_lines)
                        0: check_line("M11.1 START");
                        1: check_line("");
                        2: check_line(" \\ | /");
                        3: check_line("- RT -     Thread Operating System");
                        4: begin
                            // __DATE__ and __TIME__ depend on the actual build.
                            if (uart_line.len() != version_prefix.len() + 20 ||
                                uart_line.substr(0, version_prefix.len() - 1) != version_prefix)
                                $fatal(1, "Unexpected RT-Thread version/build line: '%s'", uart_line);
                        end
                        5: check_line(" 2006 - 2022 Copyright by RT-Thread team");
                        6: check_line("RTHW IRQ PASS");
                        7: check_line("FORMAT d=-12345 u=4000000000 x=89abcdef s=RV32 c=!");
                        8: check_line("ARGS 1 2 3 4 5 6 7 8 9 10");
                        9: check_line("BUFFER PASS");
                        10: begin check_line("M11.1 PASS"); done = 1'b1; end
                        default: $fatal(1, "Unexpected UART line");
                    endcase
                    uart_lines++;
                    uart_line = "";
                end else uart_line = {uart_line, $sformatf("%c", uart_tx_data)};
            end
            if (done) begin
                check32("official version function ran", 32'(version_calls), 1);
                check32("official formatter calls", 32'(printf_calls), 10);
                check32("strong board console calls", 32'(console_calls), 10);
                check32("typed interrupt disable calls", 32'(disables), 5);
                check32("typed interrupt restore calls", 32'(enables), 6);
                check32("all port calls returned", 32'(port_returns), 11);
                check32("enabled/disabled coverage", {30'b0, disabled_coverage}, 3);
                check32("data startup cookie", ram32(symbols[5]), 32'h1357_9bdf);
                check32("all software checks finished", ram32(symbols[6]), 4);
                check32("final mstatus", dut.u_cpu.mstatus, 32'h1880);
                for (integer i = 0; i < 4; i++)
                    check32("stack guard", ram32(symbols[7] + 32'(i * 4)), 32'hc0de_cafe);
                if (port_active || !stack_live || min_sp == symbols[9])
                    $fatal(1, "Incomplete port/stack coverage");
                $display("[PASS] official RT-Thread v4.1.1 banner, formatter, and board console");
                $display("[PASS] typed nested IRQ API; register/stack varargs; buffer bounds");
                $display("[PASS] %0d UART bytes, deepest observed stack use %0d bytes",
                         uart_bytes, symbols[9] - min_sp);
                $display(" M11.1 SOC RT-THREAD CONSOLE PASS");
                $finish;
            end
            @(negedge clk);
            #1;
        end
        $fatal(1, "RT-Thread console timeout: pc=%08x lines=%0d", pc, uart_lines);
    end
endmodule
