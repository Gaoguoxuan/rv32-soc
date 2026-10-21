module tb_console_rx;

    logic clk = 1'b0;
    logic rst;
    logic [31:0] addr;
    logic we;
    logic [3:0] wstrb;
    logic [31:0] wdata;
    logic [31:0] rdata;
    logic rx_valid;
    logic [7:0] rx_data;
    logic rx_ready;
    integer checks = 0;

    console_rx dut (.*);

    initial begin
        forever #5 clk = ~clk;
    end

    task automatic check32(
        input string name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        if (actual !== expected)
            $fatal(1, "%s: got=%08x expected=%08x", name, actual, expected);
        checks++;
    endtask

    // All stimuli change on the falling edge. Observe outputs before the
    // handshake, then check the public MMIO interface after the rising edge.
    task automatic cycle(
        input string name,
        input logic reset_active,
        input logic valid,
        input logic [7:0] byte_in,
        input logic write_enable,
        input logic [31:0] offset,
        input logic [3:0] strobes,
        input logic [31:0] write_data,
        input logic ready_before,
        input logic full_after,
        input logic [7:0] byte_after
    );
        @(negedge clk);
        rst = reset_active;
        rx_valid = valid;
        rx_data = byte_in;
        we = write_enable;
        addr = offset;
        wstrb = strobes;
        wdata = write_data;
        #1;
        check32({name, ": ready before edge"}, {31'b0, rx_ready},
                {31'b0, ready_before});

        @(posedge clk);
        #1;
        // Removing the transaction prevents an ACK read probe from affecting
        // ready; the following MMIO probes complete before the next edge.
        we = 1'b0;
        wstrb = 4'b0;
        rx_valid = 1'b0;
        addr = 32'h04;
        #1;
        check32({name, ": status"}, rdata, {31'b0, full_after});
        check32({name, ": ready after edge"}, {31'b0, rx_ready},
                {31'b0, (!reset_active && !full_after)});
        addr = 32'h08;
        #1;
        check32({name, ": data"}, rdata, {24'b0, byte_after});
    endtask

    task automatic receive_byte(input logic [7:0] value);
        cycle("receive", 0, 1, value, 0, 32'h04, 0, 0, 1, 1, value);
    endtask

    task automatic consume_byte;
        cycle("ACK", 0, 0, 0, 1, 32'h0c, 4'h1, 1, 1, 0, 0);
    endtask

    initial begin
        rst = 1'b1;
        addr = 0;
        we = 0;
        wstrb = 0;
        wdata = 0;
        rx_valid = 0;
        rx_data = 0;

        cycle("reset ignores input and ACK", 1, 1, 8'hff,
              1, 32'h0c, 4'hf, 1, 0, 0, 0);
        cycle("empty", 0, 0, 8'ha5, 0, 32'h04, 0, 0, 1, 0, 0);
        consume_byte();
        $display("[PASS] reset, invalid input and ACK on empty mailbox");

        // Every byte is data, including NUL and 0xff. Repeated reads must not
        // consume it, and a full mailbox must refuse a second byte.
        for (int value = 0; value < 256; value++) begin
            receive_byte(8'(value));
            repeat (2)
                cycle("read holds byte", 0, 0, 0, 0, 32'h08,
                      4'hf, 1, 0, 1, 8'(value));
            cycle("full refuses input", 0, 1, ~8'(value), 0, 32'h04,
                  0, 0, 0, 1, 8'(value));
            consume_byte();
        end
        $display("[PASS] all 256 bytes, repeated reads and backpressure");

        receive_byte(8'h41);
        cycle("ACK disabled by we", 0, 0, 0, 0, 32'h0c,
              4'hf, 1, 0, 1, 8'h41);
        cycle("ACK bit zero", 0, 0, 0, 1, 32'h0c,
              4'hf, 32'hffff_fffe, 0, 1, 8'h41);
        cycle("write status ignored", 0, 0, 0, 1, 32'h04,
              4'hf, 1, 0, 1, 8'h41);
        cycle("write data ignored", 0, 0, 0, 1, 32'h08,
              4'hf, 1, 0, 1, 8'h41);
        consume_byte();

        for (int mask = 0; mask < 16; mask++) begin
            receive_byte(8'h55);
            if ((mask & 1) != 0)
                cycle("ACK lane selected", 0, 0, 0, 1, 32'h0c,
                      4'(mask), 32'hffff_ffff, 1, 0, 0);
            else begin
                cycle("ACK lane not selected", 0, 0, 0, 1, 32'h0c,
                      4'(mask), 32'hffff_ffff, 0, 1, 8'h55);
                consume_byte();
            end
        end
        $display("[PASS] write enable, ACK bit, read-only registers and all strobes");

        receive_byte(8'h42);
        // Include near misses and distant aliases to require full address
        // decoding. Unmapped reads, including ACK, must return zero.
        for (int i = 0; i < 7; i++) begin
            logic [31:0] bad_addr;
            case (i)
                0: bad_addr = 32'h00;
                1: bad_addr = 32'h0d;
                2: bad_addr = 32'h0e;
                3: bad_addr = 32'h0f;
                4: bad_addr = 32'h10;
                5: bad_addr = 32'h10c;
                default: bad_addr = 32'h2000_000c;
            endcase
            cycle("unmapped write ignored", 0, 1, 8'h99, 1, bad_addr,
                  4'hf, 1, 0, 1, 8'h42);
            addr = bad_addr;
            #1;
            check32("unmapped read", rdata, 0);
        end
        addr = 32'h0c;
        #1;
        check32("ACK read", rdata, 0);
        consume_byte();
        $display("[PASS] unmapped accesses and high address bits");

        // An accepted replacement must stay in the mailbox. Consecutive ACK
        // cycles also exercise reception on every clock edge.
        receive_byte(8'h00);
        for (int value = 1; value < 256; value++)
            cycle("ACK plus new byte", 0, 1, 8'(value), 1, 32'h0c,
                  4'h1, 1, 1, 1, 8'(value));
        cycle("invalid ACK refuses replacement", 0, 1, 8'h22,
              1, 32'h0c, 4'he, 1, 0, 1, 8'hff);
        consume_byte();
        cycle("ACK plus input while empty", 0, 1, 8'ha5,
              1, 32'h0c, 4'h1, 1, 1, 1, 8'ha5);
        $display("[PASS] simultaneous ACK and reception, full and empty");

        cycle("reset full mailbox", 1, 1, 8'h33,
              1, 32'h0c, 4'hf, 1, 0, 0, 0);
        cycle("receive after reset", 0, 1, 8'h5a,
              0, 32'h04, 0, 0, 1, 1, 8'h5a);
        consume_byte();
        $display("[PASS] reset wins over simultaneous ACK and input, then recovery");

        $display("CONSOLE RX CHECKS PASS (%0d checks)", checks);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "console RX test timed out");
    end

endmodule
