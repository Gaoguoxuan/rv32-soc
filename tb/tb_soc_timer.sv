module tb_soc_timer;

    logic clk;
    logic rst;
    logic [31:0] pc;
    logic uart_tx_valid;
    logic [7:0] uart_tx_data;

    localparam logic [31:0] TIMER_BASE = 32'h3000_0000;
    localparam logic [31:0] TIMER_END  = 32'h3000_000f;

    integer compare_phase = 0;
    integer compare_sequences = 0;
    integer byte_writes = 0;
    integer time_low_writes = 0;
    integer time_high_writes = 0;
    integer read_phase = 0;
    integer read_sequences = 0;
    integer read_retries = 0;
    integer irq_rises = 0;
    integer irq_falls = 0;
    integer uart_lines = 0;
    string uart_line = "";
    logic done = 1'b0;

    logic selected;
    logic timer_write;
    logic compare_write;
    logic old_irq;
    logic [31:0] bus_addr;
    logic [31:0] bus_wdata;
    logic [3:0] bus_wstrb;
    logic [31:0] read_high;
    logic [31:0] expected_rdata;
    logic [63:0] old_time;
    logic [63:0] old_compare;

    rv32_soc #(
        .ROM_HEX ("build/soc_timer/soc_timer.hex")
    ) dut (
        .clk           (clk),
        .rst           (rst),
        .pc            (pc),
        .uart_tx_valid (uart_tx_valid),
        .uart_tx_data  (uart_tx_data)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check32(
        input string name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        if (actual !== expected)
            $fatal(1, "%s: got=%08x expected=%08x pc=%08x", name, actual, expected, pc);
    endtask

    task automatic check_line(input string expected);
        if (uart_line != expected)
            $fatal(1, "UART line %0d: got='%s' expected='%s'",
                   uart_lines, uart_line, expected);
    endtask

    initial begin
        rst = 1'b1;
        $dumpfile("build/soc_timer/soc_timer.vcd");
        $dumpvars(0, tb_soc_timer);
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        for (integer cycle = 0; cycle < 200000; cycle++) begin
            bus_addr   = dut.mem_addr;
            bus_wdata  = dut.mem_wdata;
            bus_wstrb  = dut.mem_wstrb;
            selected   = bus_addr >= TIMER_BASE && bus_addr <= TIMER_END;
            timer_write = selected && dut.mem_we;
            compare_write = timer_write && bus_addr[3];
            old_irq     = dut.timer_irq;
            old_time    = dut.u_timer.mtime;
            old_compare = dut.u_timer.mtimecmp;

            check32("Timer address selection", {31'b0, dut.timer_sel}, {31'b0, selected});
            check32("Timer write selection", {31'b0, dut.u_timer.we}, {31'b0, timer_write});
            check32("Timer relative address", dut.u_timer.addr, bus_addr - TIMER_BASE);

            if (dut.u_cpu.trap_enter !== 1'b0)
                $fatal(1, "Unexpected CPU trap: pc=%08x instr=%08x", pc, dut.instr);

            if (timer_write) begin
                if (!bus_addr[3]) begin
                    check32("Time write strobes", {28'b0, bus_wstrb}, 32'hf);
                    if (bus_addr[2])
                        time_high_writes++;
                    else
                        time_low_writes++;
                    read_phase = 0;
                end
                else if (bus_wstrb == 4'hf) begin
                    // Verify the software really emits low=-1, high, low.
                    case (compare_phase)
                        0: begin
                            check32("Compare sequence first address", bus_addr, TIMER_BASE + 32'h08);
                            check32("Compare sequence low=-1", bus_wdata, 32'hffff_ffff);
                            compare_phase = 1;
                        end
                        1: begin
                            check32("Compare sequence high address", bus_addr, TIMER_BASE + 32'h0c);
                            compare_phase = 2;
                        end
                        2: begin
                            check32("Compare sequence final address", bus_addr, TIMER_BASE + 32'h08);
                            compare_phase = 0;
                            compare_sequences++;
                        end
                        default: $fatal(1, "Invalid compare write phase");
                    endcase
                end
                else begin
                    check32("Byte write outside compare update", compare_phase, 32'b0);
                    case (bus_addr)
                        32'h3000_0009: begin
                            check32("Compare low byte strobe", {28'b0, bus_wstrb}, 32'h2);
                            check32("Compare low byte data", bus_wdata, 32'h0000_aa00);
                        end
                        32'h3000_000f: begin
                            check32("Compare high byte strobe", {28'b0, bus_wstrb}, 32'h8);
                            check32("Compare high byte data", bus_wdata, 32'h9900_0000);
                        end
                        default: $fatal(1, "Unexpected partial timer write: %08x", bus_addr);
                    endcase
                    byte_writes++;
                end
            end

            if (selected && dut.u_cpu.mem_load) begin
                case (bus_addr[3:2])
                    2'd0: expected_rdata = old_time[31:0];
                    2'd1: expected_rdata = old_time[63:32];
                    2'd2: expected_rdata = old_compare[31:0];
                    2'd3: expected_rdata = old_compare[63:32];
                endcase
                check32("Timer CPU read mux", dut.mem_rdata, expected_rdata);

                if (!bus_addr[3]) begin
                    case (read_phase)
                        0: begin
                            check32("Time read starts with high", bus_addr, TIMER_BASE + 32'h04);
                            read_high = dut.mem_rdata;
                            read_phase = 1;
                        end
                        1: begin
                            check32("Time read middle is low", bus_addr, TIMER_BASE);
                            read_phase = 2;
                        end
                        2: begin
                            check32("Time read ends with high", bus_addr, TIMER_BASE + 32'h04);
                            if (read_high != dut.mem_rdata)
                                read_retries++;
                            read_sequences++;
                            read_phase = 0;
                        end
                        default: $fatal(1, "Invalid time read phase");
                    endcase
                end
            end

            @(posedge clk);
            #1;

            if (!old_irq && dut.timer_irq) begin
                // In this image IRQ must rise by counting to a programmed deadline.
                if (compare_sequences < 3 || compare_sequences > 4 ||
                    timer_write || dut.u_timer.mtimecmp !== old_compare ||
                    dut.u_timer.mtime !== old_compare ||
                    old_time + 64'd1 !== dut.u_timer.mtime)
                    $fatal(1, "Unexpected IRQ rise: time=%016x compare=%016x",
                           dut.u_timer.mtime, dut.u_timer.mtimecmp);
                irq_rises++;
                $display("[PASS] deadline #%0d reached at %016x", irq_rises, dut.u_timer.mtime);
            end
            if (old_irq && !dut.timer_irq) begin
                if (!compare_write || dut.u_timer.mtimecmp <= dut.u_timer.mtime)
                    $fatal(1, "IRQ cleared without rearming the comparator");
                irq_falls++;
                $display("[PASS] timer IRQ cleared by a future compare value");
            end

            if (uart_tx_valid) begin
                $write("%c", uart_tx_data);
                if (uart_tx_data == 8'h0a) begin
                    case (uart_lines)
                        0: check_line("M9.2 START");
                        1: check_line("MMIO PASS");
                        2: check_line("READ64 PASS");
                        3: check_line("TICK 1");
                        4: check_line("TICK 2");
                        5: begin
                            check_line("M9.2 PASS");
                            done = 1'b1;
                        end
                        default: $fatal(1, "Unexpected extra UART line");
                    endcase
                    uart_lines++;
                    uart_line = "";
                end
                else
                    uart_line = {uart_line, $sformatf("%c", uart_tx_data)};
            end

            if (pc[1:0] !== 2'b00 || pc >= 32'd4096)
                $fatal(1, "Invalid instruction address: %08x", pc);

            if (done) begin
                check32("Complete compare write sequences", compare_sequences, 32'd5);
                check32("No unfinished compare write", compare_phase, 32'd0);
                check32("Byte writes through the CPU", byte_writes, 32'd2);
                check32("Time low writes", time_low_writes, 32'd64);
                check32("Time high writes", time_high_writes, 32'd64);
                check32("No unfinished time read", read_phase, 32'd0);
                check32("IRQ rise count", irq_rises, 32'd2);
                check32("IRQ clear count", irq_falls, 32'd2);
                check32("Final IRQ level", {31'b0, dut.timer_irq}, 32'd0);
                if (read_sequences < 64 || read_retries == 0)
                    $fatal(1, "Rollover read retry was not exercised: reads=%0d retries=%0d",
                           read_sequences, read_retries);
                if (dut.u_timer.mtimecmp !== 64'hffff_ffff_ffff_ffff)
                    $fatal(1, "Final comparator was not disarmed");
                $display("[PASS] %0d high/low/high reads, %0d rollover retries",
                         read_sequences, read_retries);
                $display("==============================");
                $display("    M9.2 SOC TIMER PASS");
                $display("==============================");
                $finish;
            end
            @(negedge clk);
        end

        $fatal(1, "SoC timer timeout: pc=%08x UART lines=%0d reads=%0d retries=%0d",
               pc, uart_lines, read_sequences, read_retries);
    end

endmodule
