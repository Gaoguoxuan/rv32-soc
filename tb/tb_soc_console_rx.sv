module tb_soc_console_rx;
    localparam logic [31:0] TX = 32'h2000_0000;
    localparam logic [31:0] STATUS = 32'h2000_0004;
    localparam logic [31:0] DATA = 32'h2000_0008;
    localparam logic [31:0] ACK = 32'h2000_000c;
    localparam int STREAM_LEN = 12;
    localparam logic [7:0] STREAM [0:STREAM_LEN-1] =
        '{8'h41, 8'h00, 8'hff, 8'h7f, 8'h80, 8'h52,
          8'h49, 8'h53, 8'h43, 8'h2d, 8'h56, 8'h0a};

    logic clk = 1'b0, rst = 1'b1;
    logic [31:0] pc;
    logic uart_tx_valid, uart_rx_valid = 1'b0, uart_rx_ready;
    logic [7:0] uart_tx_data, uart_rx_data = 8'b0;
    logic full = 1'b0;
    logic [7:0] pending_byte = 8'b0;
    logic boot_ready = 1'b0, done = 1'b0;
    logic ack_write, accepted, tx_write, rx_selected;
    logic [7:0] tx_byte;
    integer sent = 0, consumed = 0, tx_count = 0, idle_cycles = 0;
    integer replacements = 0, stalled_cycles = 0;
    integer empty_polls = 0, drain_polls = 0, data_reads = 0;
    integer ignored_writes = 0, checks = 0;
    string image_path = "build/soc_console_rx/soc_console_rx.hex";
    string banner = "CONSOLE RX READY\n";
    string trailer = "\nCONSOLE RX PASS\n";

    rv32_soc dut (
        .clk (clk), .rst (rst), .pc (pc),
        .uart_tx_valid (uart_tx_valid), .uart_tx_data (uart_tx_data),
        .uart_rx_valid (uart_rx_valid), .uart_rx_data (uart_rx_data),
        .uart_rx_ready (uart_rx_ready)
    );

    initial forever #5 clk = ~clk;

    task automatic check32(input string name, input logic [31:0] actual,
                           input logic [31:0] expected);
        if (actual !== expected)
            $fatal(1, "%s: got=%08x expected=%08x pc=%08x addr=%08x sent=%0d consumed=%0d",
                   name, actual, expected, pc, dut.mem_addr, sent, consumed);
        checks++;
    endtask

    function automatic logic [7:0] expected_tx(input integer index);
        if (index < banner.len()) return banner[index];
        if (index < banner.len() + STREAM_LEN)
            return STREAM[index - banner.len()];
        if (index == banner.len() + STREAM_LEN) return 8'h5a;
        if (index < banner.len() + STREAM_LEN + 1 + trailer.len())
            return trailer[index - banner.len() - STREAM_LEN - 1];
        $fatal(1, "Unexpected extra UART output at byte %0d", index);
        return 0;
    endfunction

    initial begin
        if ($value$plusargs("image=%s", image_path)) begin end
        #1; // Let simple_rom initialize before loading the selected image.
        $display("[IMAGE] %s", image_path);
        $readmemh(image_path, dut.u_rom.mem);
        repeat (2) @(posedge clk);
        #1;
        check32("reset ready", {31'b0, uart_rx_ready}, 0);
        check32("reset PC", pc, 0);

        @(negedge clk);
        rst = 1'b0;
        for (integer cycle = 0; cycle < 100000; cycle++) begin
            // Once valid is asserted, sent changes only on a handshake.
            // Thus data stays stable for the entire backpressure interval.
            if (sent < STREAM_LEN && boot_ready && empty_polls >= 3) begin
                uart_rx_valid = 1'b1;
                uart_rx_data = STREAM[sent];
            end
            else if (sent == STREAM_LEN && drain_polls >= 3) begin
                uart_rx_valid = 1'b1;
                uart_rx_data = 8'h5a;
            end
            else begin
                uart_rx_valid = 1'b0;
                uart_rx_data = 0;
            end
            #1;

            if (dut.u_cpu.trap_enter)
                $fatal(1, "Unexpected CPU trap at pc=%08x cause=%08x", pc, dut.u_cpu.trap_cause);
            if (pc >= 4096 || pc[1:0] != 0)
                $fatal(1, "Invalid program address %08x", pc);

            rx_selected = dut.mem_addr >= STATUS && dut.mem_addr <= 32'h2000_000f;
            ack_write = dut.mem_we && dut.mem_addr == ACK &&
                        dut.mem_wstrb[0] && dut.mem_wdata[0];
            accepted = uart_rx_valid && uart_rx_ready;
            tx_write = dut.mem_we && dut.mem_addr == TX && dut.mem_wstrb[0];
            tx_byte = dut.mem_wdata[7:0];
            check32("RX address decode", {31'b0, dut.console_rx_sel}, {31'b0, rx_selected});
            check32("RX write qualification", {31'b0, dut.u_console_rx.we},
                    {31'b0, (dut.mem_we && rx_selected)});
            check32("TX write qualification", {31'b0, dut.u_uart.we}, {31'b0, tx_write});
            check32("RX ready", {31'b0, uart_rx_ready}, {31'b0, (!full || ack_write)});
            if (uart_rx_valid && !uart_rx_ready) stalled_cycles++;

            if (dut.u_cpu.mem_load) begin
                case (dut.mem_addr)
                    STATUS: begin
                        check32("CPU reads RX status", dut.mem_rdata, {31'b0, full});
                        if (!full && boot_ready && consumed == 0) empty_polls++;
                        if (!full && consumed == STREAM_LEN) drain_polls++;
                    end
                    DATA: begin
                        check32("CPU reads RX data", dut.mem_rdata,
                                full ? {24'b0, pending_byte} : 0);
                        if (full) data_reads++;
                    end
                    TX, ACK, 32'h2000_0005, 32'h2000_0009, 32'h2000_000f,
                    32'h2000_0010, 32'h2000_0104, 32'h2000_0108:
                        check32("read-only/unmapped read", dut.mem_rdata, 0);
                    default: ;
                endcase
            end

            if (dut.mem_we && (rx_selected || dut.mem_addr == 32'h2000_0010 ||
                              dut.mem_addr == 32'h2000_010c) && !ack_write)
                ignored_writes++;
            if (ack_write && full) begin
                consumed++;
                full = 1'b0;
                if (accepted) replacements++;
            end
            if (accepted) begin
                check32("input byte order", {24'b0, uart_rx_data},
                        sent < STREAM_LEN ? {24'b0, STREAM[sent]} : 32'h5a);
                pending_byte = uart_rx_data;
                full = 1'b1;
                sent++;
            end

            @(posedge clk);
            #1;
            check32("UART valid follows TX store only", {31'b0, uart_tx_valid}, {31'b0, tx_write});
            if (uart_tx_valid) begin
                check32("UART data follows TX store", {24'b0, uart_tx_data}, {24'b0, tx_byte});
                check32("CPU echo/output sequence", {24'b0, uart_tx_data}, {24'b0, expected_tx(tx_count)});
                if (tx_count >= banner.len() && tx_count < banner.len() + STREAM_LEN &&
                    (uart_tx_data < 8'h20 || uart_tx_data >= 8'h7f) && uart_tx_data != 8'h0a)
                    $write("<%02x>", uart_tx_data);
                else
                    $write("%c", uart_tx_data);
                tx_count++;
                if (tx_count == banner.len()) boot_ready = 1'b1;
                if (tx_count == banner.len() + STREAM_LEN + 1 + trailer.len()) done = 1'b1;
            end

            if (done) begin
                idle_cycles++;
                if (idle_cycles == 20) begin
                    check32("accepted inputs", 32'(sent), STREAM_LEN + 1);
                    check32("consumed inputs", 32'(consumed), STREAM_LEN + 1);
                    check32("ACK plus reception", 32'(replacements), STREAM_LEN - 1);
                    check32("final mailbox empty", {31'b0, full}, 0);
                    check32("ignored MMIO writes", 32'(ignored_writes), 7);
                    if (empty_polls < 3 || drain_polls < 3 || stalled_cycles == 0 ||
                        data_reads < 2 * (STREAM_LEN + 1))
                        $fatal(1, "Missing polling/read/backpressure coverage");
                    $display("SOC CONSOLE RX CHECKS PASS (%0d checks, %0d inputs, %0d replacements, %0d stalled cycles)",
                             checks, sent, replacements, stalled_cycles);
                    $finish;
                end
            end
            @(negedge clk);
        end
        $fatal(1, "Console RX simulation timed out");
    end
endmodule
