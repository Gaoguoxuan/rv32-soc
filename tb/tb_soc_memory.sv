module tb_soc_memory;
    localparam logic [31:0] ROM_TAIL = 32'h5aa5_9669;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [31:0] pc;
    logic uart_tx_valid;
    logic [7:0] uart_tx_data;
    logic [31:0] probe_addr = 32'h0000_fffc;
    logic [31:0] probe_instr;
    logic [31:0] probe_data;
    logic probe_done = 1'b0;
    logic done = 1'b0;
    logic stack_live = 1'b0;
    logic [4:0] ram_writes_seen = 5'b0;
    logic [3:0] unmapped_reads_seen = 4'b0;
    logic [3:0] unmapped_writes_seen = 4'b0;
    logic [2:0] partial_writes_seen = 3'b0;
    logic [31:0] addr;
    logic expected_rom;
    logic expected_ram;
    integer high_fetches = 0;
    integer high_data_reads = 0;
    integer rom_tail_reads = 0;
    integer rom_tail_writes = 0;
    integer uart_lines = 0;
    string uart_line = "";

    rv32_soc #(
        .ROM_HEX ("build/soc_memory/soc_memory.hex"),
        .ROM_BYTES (64 * 1024),
        .RAM_BYTES (64 * 1024)
    ) dut (
        .clk (clk), .rst (rst), .pc (pc),
        .uart_tx_valid (uart_tx_valid), .uart_tx_data (uart_tx_data),
        .uart_rx_valid (1'b0),
        .uart_rx_data  (8'b0),
        .uart_rx_ready ()
    );

    // Check instruction-fetch boundaries independently of CPU control flow.
    simple_rom #(
        .WORDS (16384), .HEX_FILE ("build/soc_memory/soc_memory.hex")
    ) rom_probe (
        .instr_addr (probe_addr), .instr_data (probe_instr),
        .data_addr (probe_addr), .data_rdata (probe_data)
    );

    initial begin
        forever #5 clk = ~clk;
    end

    task automatic check32(input string name, input logic [31:0] actual,
                           input logic [31:0] expected);
        if (actual !== expected)
            $fatal(1, "%s: got=%08x expected=%08x pc=%08x addr=%08x",
                   name, actual, expected, pc, dut.mem_addr);
    endtask

    task automatic check_line(input string expected);
        if (uart_line != expected)
            $fatal(1, "UART line %0d: got='%s' expected='%s'", uart_lines, uart_line, expected);
    endtask

    initial begin
        #1;
        check32("last ROM instruction word", probe_instr, ROM_TAIL);
        check32("last ROM data word", probe_data, ROM_TAIL);
        probe_addr = 32'h0001_0000;
        #1;
        check32("first out-of-range fetch is NOP", probe_instr, 32'h13);
        check32("first out-of-range data is zero", probe_data, 32'b0);
        probe_addr = 32'hffff_ffff;
        #1;
        check32("highest address fetch is NOP", probe_instr, 32'h13);
        check32("highest address data is zero", probe_data, 32'b0);
        probe_done = 1'b1;
    end

    initial begin
        $dumpfile("build/soc_memory/soc_memory.vcd");
        $dumpvars(0, tb_soc_memory);
        // Nonzero initial RAM makes missing data/BSS initialization visible.
        for (integer i = 0; i < 16384; i++)
            dut.u_ram.mem[i] = 32'hfeed_0000 ^ 32'(i);
        check32("ROM array word count", $size(dut.u_rom.mem), 32'd16384);
        check32("RAM array word count", $size(dut.u_ram.mem), 32'd16384);
        check32("ROM last byte", dut.ROM_END, 32'h0000_ffff);
        check32("RAM last byte", dut.RAM_END, 32'h1000_ffff);
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        #1;

        for (integer cycle = 0; cycle < 100000; cycle++) begin
            addr = dut.mem_addr;
            expected_rom = addr < 32'h0001_0000;
            expected_ram = addr >= 32'h1000_0000 && addr <= 32'h1000_ffff;
            check32("ROM decode", {31'b0, dut.rom_sel}, {31'b0, expected_rom});
            check32("RAM decode", {31'b0, dut.ram_sel}, {31'b0, expected_ram});
            check32("RAM write qualification", {31'b0, dut.u_ram.we},
                    {31'b0, (dut.mem_we && expected_ram)});
            if (dut.u_cpu.trap_enter)
                $fatal(1, "Unexpected trap: pc=%08x instr=%08x cause=%08x",
                       pc, dut.instr, dut.u_cpu.trap_cause);
            if (pc[1:0] != 2'b0 || pc >= 32'h10000)
                $fatal(1, "Invalid program address: %08x", pc);
            if (pc >= 32'h2000 && pc < 32'h4000)
                high_fetches++;

            if (dut.u_cpu.mem_load) begin
                case (addr)
                    32'h0000_4000: begin
                        high_data_reads++;
                        check32("high ROM data", dut.mem_rdata, 32'hcafe_babe);
                    end
                    32'h0000_fffc, 32'h0000_ffff: begin
                        rom_tail_reads++;
                        check32("ROM tail data", dut.mem_rdata, ROM_TAIL);
                    end
                    32'h0001_0000: begin
                        unmapped_reads_seen[0] = 1'b1;
                        check32("after ROM read", dut.mem_rdata, 32'b0);
                    end
                    32'h0fff_fffc: begin
                        unmapped_reads_seen[1] = 1'b1;
                        check32("before RAM read", dut.mem_rdata, 32'b0);
                    end
                    32'h1001_0000: begin
                        unmapped_reads_seen[2] = 1'b1;
                        check32("after RAM read", dut.mem_rdata, 32'b0);
                    end
                    32'hffff_fffc: begin
                        unmapped_reads_seen[3] = 1'b1;
                        check32("high unmapped read", dut.mem_rdata, 32'b0);
                    end
                    default: begin end
                endcase
            end

            if (dut.mem_we) begin
                case (addr)
                    32'h1000_0000: ram_writes_seen[0] = 1'b1;
                    32'h1000_0400: ram_writes_seen[1] = 1'b1;
                    32'h1000_1000: ram_writes_seen[2] = 1'b1;
                    32'h1000_8000: ram_writes_seen[3] = 1'b1;
                    32'h1000_fffc: begin
                        if (dut.mem_wstrb == 4'hf)
                            ram_writes_seen[4] = 1'b1;
                        else begin
                            check32("last low-half strobe", {28'b0, dut.mem_wstrb}, 32'h3);
                            check32("last low-half data", dut.mem_wdata, 32'h0000_1234);
                            partial_writes_seen[2] = 1'b1;
                        end
                    end
                    32'h1000_ffff: begin
                        check32("last byte strobe", {28'b0, dut.mem_wstrb}, 32'h8);
                        check32("last byte data", dut.mem_wdata, 32'h5a00_0000);
                        partial_writes_seen[0] = 1'b1;
                    end
                    32'h1000_fffe: begin
                        check32("last high-half strobe", {28'b0, dut.mem_wstrb}, 32'hc);
                        check32("last high-half data", dut.mem_wdata, 32'h9abc_0000);
                        partial_writes_seen[1] = 1'b1;
                    end
                    32'h0000_fffc: begin
                        rom_tail_writes++;
                        check32("ROM store cannot write RAM", {31'b0, dut.u_ram.we}, 32'b0);
                    end
                    32'h0001_0000: unmapped_writes_seen[0] = 1'b1;
                    32'h0fff_fffc: unmapped_writes_seen[1] = 1'b1;
                    32'h1001_0000: unmapped_writes_seen[2] = 1'b1;
                    32'hffff_fffc: unmapped_writes_seen[3] = 1'b1;
                    default: begin end
                endcase
            end

            @(posedge clk);
            #1;
            if (dut.u_cpu.u_regfile.regs[2] == 32'h1000_fff0)
                stack_live = 1'b1;
            if (stack_live && (dut.u_cpu.u_regfile.regs[2] < 32'h1000_fbf0 ||
                dut.u_cpu.u_regfile.regs[2] > 32'h1000_fff0 ||
                dut.u_cpu.u_regfile.regs[2][3:0] != 4'b0))
                $fatal(1, "Stack out of range/alignment: %08x", dut.u_cpu.u_regfile.regs[2]);
            if (uart_tx_valid) begin
                $write("%c", uart_tx_data);
                if (uart_tx_data == 8'h0a) begin
                    case (uart_lines)
                        0: check_line("M10.1 START");
                        1: check_line("HIGH ROM PASS");
                        2: check_line("RAM RANGE PASS");
                        3: check_line("BOUNDARY PASS");
                        4: begin check_line("M10.1 PASS"); done = 1'b1; end
                        default: $fatal(1, "Unexpected extra UART line");
                    endcase
                    uart_lines++;
                    uart_line = "";
                end
                else
                    uart_line = {uart_line, $sformatf("%c", uart_tx_data)};
            end

            if (done) begin
                check32("all RAM regions exercised", {27'b0, ram_writes_seen}, 32'h1f);
                check32("all unmapped reads exercised", {28'b0, unmapped_reads_seen}, 32'hf);
                check32("all unmapped writes exercised", {28'b0, unmapped_writes_seen}, 32'hf);
                check32("all partial writes exercised", {29'b0, partial_writes_seen}, 32'h7);
                check32("ROM read-only exercised", rom_tail_writes, 32'd1);
                check32("low RAM sentinel", dut.u_ram.mem[0], 32'h1122_3344);
                check32("old RAM boundary sentinel", dut.u_ram.mem[256], 32'h5566_7788);
                check32("4 KiB RAM sentinel", dut.u_ram.mem[1024], 32'h89ab_cdef);
                check32("high RAM sentinel", dut.u_ram.mem[8192], 32'h1357_9bdf);
                check32("last RAM word", dut.u_ram.mem[16383], 32'h9abc_1234);
                check32("ROM tail unchanged", dut.u_rom.mem[16383], ROM_TAIL);
                if (!probe_done || !stack_live || high_fetches == 0 ||
                    high_data_reads == 0 || rom_tail_reads == 0)
                    $fatal(1, "Missing high-address or boundary coverage");
                $display("[PASS] %0d high ROM instruction fetches; startup data/BSS in high RAM", high_fetches);
                $display("[PASS] 64 KiB ROM/RAM, independent RAM regions, final byte/halfword/word, unmapped accesses");
                $display("==============================");
                $display(" M10.1 SOC MEMORY PASS");
                $display("==============================");
                $finish;
            end
            @(negedge clk);
            #1;
        end
        $fatal(1, "Memory test timeout: pc=%08x lines=%0d", pc, uart_lines);
    end
endmodule
