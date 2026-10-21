module tb_soc_rtthread_input;
    localparam logic [31:0] RAM = 32'h1000_0000;
    localparam logic [31:0] TX = 32'h2000_0000;
    localparam logic [31:0] STATUS = 32'h2000_0004;
    localparam logic [31:0] DATA = 32'h2000_0008;
    localparam logic [31:0] ACK = 32'h2000_000c;
    localparam int GETCHAR = 0, DELAY = 1, TICK = 2, CURRENT = 3, NEST = 4,
        LOCATIONS = 5, RECEIVED = 6, BYTES = 7, TICKS = 8, BEATS = 9,
        BEFORE = 10, GAP = 11, IDLE = 12, DONE = 13, CLEANUP = 14;
    localparam logic [7:0] INPUT_BYTES [0:7] =
        '{8'h41, 8'h00, 8'hff, 8'h80, 8'h52, 8'h56, 8'h0a, 8'h5a};

    logic clk = 1'b0, rst = 1'b1;
    logic [31:0] pc, symbols [0:23];
    logic uart_tx_valid, uart_rx_valid = 1'b0, uart_rx_ready;
    logic [7:0] uart_tx_data, uart_rx_data = 0;
    logic full = 1'b0, pending_call = 1'b0, entry_had_byte;
    logic ack_write, accepted, tx_write, irq;
    logic [7:0] mailbox_byte = 0, tx_byte;
    logic [31:0] return_pc, tick, current_thread;
    integer irqs = 0, sent = 0, acks = 0, data_reads = 0, replacements = 0;
    integer calls = 0, returns = 0, delay_calls = 0, entry_delays = 0;
    integer fast_returns = 0, blocked_returns = 0, stalled_cycles = 0;
    integer beat_stores = 0, rx_lines = 0, lines = 0, checks = 0;
    integer parsed_index, parsed_byte, parsed_tick;
    string image_path = "build/rtthread_input/rtthread_input.hex";
    string symbol_path = "build/rtthread_input/rtthread_input.symbols.hex";
    string uart_line = "";

    rv32_soc #(.ROM_BYTES(65536), .RAM_BYTES(65536)) dut (
        .clk (clk), .rst (rst), .pc (pc),
        .uart_tx_valid (uart_tx_valid), .uart_tx_data (uart_tx_data),
        .uart_rx_valid (uart_rx_valid), .uart_rx_data (uart_rx_data),
        .uart_rx_ready (uart_rx_ready)
    );
    initial forever #50 clk = ~clk; // 10 MHz, 10000 clocks per tick.

    function automatic logic [31:0] ram32(input logic [31:0] address);
        if (address < RAM || address >= RAM + 65536 || address[1:0] != 0)
            $fatal(1, "Invalid monitored RAM word %08x", address);
        return dut.u_ram.mem[(address - RAM) >> 2];
    endfunction
    function automatic logic [31:0] ram8(input logic [31:0] address);
        return (ram32(address & ~32'h3) >> (8 * int'(address[1:0]))) & 32'hff;
    endfunction
    function automatic logic [31:0] location(input integer index);
        return ram32(symbols[LOCATIONS] + 32'(index * 4));
    endfunction
    task automatic check32(input string name, input logic [31:0] actual,
                           input logic [31:0] expected);
        if (actual !== expected)
            $fatal(1, "%s: got=%08x expected=%08x pc=%08x IRQs=%0d sent=%0d returns=%0d",
                   name, actual, expected, pc, irqs, sent, returns);
        checks++;
    endtask

    task automatic check_finish;
        check32("getchar calls", 32'(calls), 8);
        check32("getchar returns", 32'(returns), 8);
        check32("fast returns", 32'(fast_returns), 6);
        check32("blocking returns", 32'(blocked_returns), 2);
        check32("one-tick delays", 32'(delay_calls), 11);
        check32("input handshakes", 32'(sent), 8);
        check32("data reads", 32'(data_reads), 8);
        check32("ACK writes", 32'(acks), 8);
        check32("same-edge replacements", 32'(replacements), 6);
        check32("real timer IRQs", 32'(irqs), 16);
        check32("heartbeat stores", 32'(beat_stores), 8);
        check32("RX output lines", 32'(rx_lines), 8);
        check32("kernel tick", ram32(symbols[TICK]), 16);
        check32("received", ram32(symbols[RECEIVED]), 8);
        check32("beats", ram32(symbols[BEATS]), 8);
        check32("beats before input", ram32(symbols[BEFORE]), 2);
        check32("beats during gap", ram32(symbols[GAP]), 3);
        check32("receiver done", ram32(symbols[DONE]), 1);
        check32("idle cleanup", ram32(symbols[CLEANUP]), 1);
        check32("no interrupt nesting", ram8(symbols[NEST]), 0);
        check32("mailbox empty", {31'b0, full}, 0);
        check32("MIE stopped for finish", {31'b0, dut.u_cpu.mstatus[3]}, 0);
        check32("MTIE stopped for finish", {31'b0, dut.u_cpu.mie[7]}, 0);
        if (pending_call || stalled_cycles == 0 || ram32(symbols[IDLE]) == 0)
            $fatal(1, "Missing return/backpressure/idle coverage");
        for (integer i = 0; i < 8; i++) begin
            check32("saved byte", ram8(symbols[BYTES] + 32'(i)), {24'b0, INPUT_BYTES[i]});
            check32("saved receive tick", ram32(symbols[TICKS] + 32'(i * 4)), i < 7 ? 5 : 11);
        end
        $display("RT-THREAD INPUT CHECKS PASS (%0d checks, %0d one-tick delays, %0d fast returns, %0d beats)",
                 checks, delay_calls, fast_returns, beat_stores);
        $finish;
    endtask

    task automatic check_line;
        case (lines)
            0: if (uart_line != "RT-THREAD RX START") $fatal(1, "Wrong startup: %s", uart_line);
            1: if (uart_line != "KERNEL READY") $fatal(1, "Kernel failed: %s", uart_line);
            2, 3, 4, 5, 6, 7, 8, 9: begin
                if ($sscanf(uart_line, "RX BYTE %d=%x tick=%d", parsed_index, parsed_byte, parsed_tick) != 3)
                    $fatal(1, "Invalid RX output: %s", uart_line);
                check32("output index", 32'(parsed_index), 32'(rx_lines));
                check32("output byte", 32'(parsed_byte), {24'b0, INPUT_BYTES[rx_lines]});
                check32("output tick", 32'(parsed_tick), rx_lines < 7 ? 5 : 11);
                rx_lines++;
            end
            10: if (uart_line != "HEARTBEAT PASS count=8 before=2 gap=3")
                    $fatal(1, "Heartbeat failed: %s", uart_line);
            11: if (uart_line != "IDLE/STACK/CLEANUP PASS") $fatal(1, "Guard/cleanup failed: %s", uart_line);
            12: begin
                if (uart_line != "RT-THREAD RX PASS") $fatal(1, "Test failed: %s", uart_line);
                check_finish();
            end
            default: $fatal(1, "Unexpected output: %s", uart_line);
        endcase
        lines++;
        uart_line = "";
    endtask

    initial begin
        if ($value$plusargs("image=%s", image_path)) begin end
        if ($value$plusargs("symbols=%s", symbol_path)) begin end
        #1;
        $display("[IMAGE] %s", image_path);
        $readmemh(image_path, dut.u_rom.mem);
        $readmemh(symbol_path, symbols);
        // Require startup code to initialize globals instead of relying on
        // the simulator's default zero RAM contents.
        for (integer i = 0; i < 16384; i++) dut.u_ram.mem[i] = 32'hfeed_0000 ^ 32'(i);
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        for (integer cycle = 0; cycle < 250000; cycle++) begin
            uart_rx_valid = (sent < 7 && irqs >= 5) || (sent == 7 && irqs >= 11);
            uart_rx_data = sent < 8 ? INPUT_BYTES[sent] : 8'b0;
            #1;
            tick = ram32(symbols[TICK]);
            current_thread = ram32(symbols[CURRENT]);
            irq = dut.u_cpu.trap_enter;
            if (irq) begin
                check32("only timer traps", dut.u_cpu.trap_cause, 32'h8000_0007);
                irqs++;
            end
            if (pc[1:0] != 0 || pc >= 65536) $fatal(1, "Invalid PC %08x", pc);

            if (!irq && pc == symbols[GETCHAR]) begin
                if (pending_call) $fatal(1, "Reentrant getchar");
                check32("getchar runs on receiver", current_thread, location(0));
                check32("getchar outside IRQ", ram8(symbols[NEST]), 0);
                check32("getchar MIE", {31'b0, dut.u_cpu.mstatus[3]}, 1);
                pending_call = 1'b1;
                return_pc = dut.u_cpu.u_regfile.regs[1];
                entry_had_byte = full;
                entry_delays = delay_calls;
                calls++;
            end
            if (!irq && pending_call && current_thread == location(0) && pc == return_pc) begin
                check32("getchar returned byte", dut.u_cpu.u_regfile.regs[10] & 32'hff,
                        {24'b0, INPUT_BYTES[returns]});
                check32("getchar ACK before return", 32'(acks), 32'(returns + 1));
                check32("getchar return tick", tick, returns < 7 ? 5 : 11);
                check32("getchar restored MIE", {31'b0, dut.u_cpu.mstatus[3]}, 1);
                if (entry_had_byte) begin
                    check32("buffered byte needs no delay", 32'(delay_calls), 32'(entry_delays));
                    fast_returns++;
                end
                else begin
                    if (delay_calls == entry_delays) $fatal(1, "Empty getchar did not delay");
                    blocked_returns++;
                end
                pending_call = 1'b0;
                returns++;
            end
            if (!irq && pc == symbols[DELAY] && current_thread == location(0)) begin
                if (!pending_call) $fatal(1, "Receiver delayed outside getchar");
                check32("RX delay duration", dut.u_cpu.u_regfile.regs[10], 1);
                check32("RX delay MIE", {31'b0, dut.u_cpu.mstatus[3]}, 1);
                delay_calls++;
            end
            // Exclude the startup code's BSS clear before threads run.
            if (calls != 0 && dut.mem_we && dut.mem_addr == symbols[BEATS]) begin
                check32("heartbeat runs on lower-priority thread", current_thread, location(1));
                if (pending_call) begin
                    check32("receiver suspended while heartbeat runs", ram8(location(4)) & 7, 2);
                    check32("RX waiting until next tick", ram32(location(5)), tick + 1);
                end
                beat_stores++;
            end

            ack_write = dut.mem_we && dut.mem_addr == ACK && dut.mem_wstrb[0] && dut.mem_wdata[0];
            accepted = uart_rx_valid && uart_rx_ready;
            tx_write = dut.mem_we && dut.mem_addr == TX && dut.mem_wstrb[0];
            tx_byte = dut.mem_wdata[7:0];
            check32("RX ready", {31'b0, uart_rx_ready}, {31'b0, (!full || ack_write)});
            if (uart_rx_valid && !uart_rx_ready) stalled_cycles++;
            if (!irq && dut.u_cpu.mem_load && dut.mem_addr == STATUS)
                check32("status read", dut.mem_rdata, {31'b0, full});
            if (!irq && dut.u_cpu.mem_load && dut.mem_addr == DATA) begin
                if (!full || !pending_call) $fatal(1, "Data read without a pending byte/call");
                check32("data read", dut.mem_rdata, {24'b0, mailbox_byte});
                data_reads++;
            end
            if (ack_write) begin
                if (!full || !pending_call) $fatal(1, "ACK without pending input");
                check32("ACK follows data read", 32'(data_reads), 32'(acks + 1));
                acks++;
                full = 1'b0;
                if (accepted) replacements++;
            end
            if (accepted) begin
                mailbox_byte = uart_rx_data;
                full = 1'b1;
                sent++;
            end

            @(posedge clk);
            #1;
            check32("only TX stores produce output", {31'b0, uart_tx_valid}, {31'b0, tx_write});
            if (uart_tx_valid) begin
                check32("TX store data", {24'b0, uart_tx_data}, {24'b0, tx_byte});
                $write("%c", uart_tx_data);
                if (uart_tx_data == 8'h0a) check_line();
                else uart_line = {uart_line, $sformatf("%c", uart_tx_data)};
            end
            @(negedge clk);
        end
        $fatal(1, "RT-Thread input test timed out");
    end
endmodule
