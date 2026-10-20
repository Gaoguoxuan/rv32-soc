module tb_timer_mmio;

    logic clk;
    logic rst;
    logic [31:0] addr;
    logic [31:0] wdata;
    logic [3:0] wstrb;
    logic we;
    logic [31:0] rdata;
    logic timer_irq;

    logic [63:0] time_before;
    logic [63:0] compare_before;
    integer checks = 0;

    timer_mmio dut (
        .clk       (clk),
        .rst       (rst),
        .addr      (addr),
        .wdata     (wdata),
        .wstrb     (wstrb),
        .we        (we),
        .rdata     (rdata),
        .timer_irq (timer_irq)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check64(
        input string name,
        input logic [63:0] actual,
        input logic [63:0] expected
    );
        if (actual !== expected)
            $fatal(1, "%s: got=%016x expected=%016x", name, actual, expected);
        checks++;
    endtask

    task automatic check_irq(input logic expected);
        if (timer_irq !== expected)
            $fatal(1, "timer_irq=%b expected=%b (mtime=%016x mtimecmp=%016x)",
                   timer_irq, expected, dut.mtime, dut.mtimecmp);
        checks++;
    endtask

    // Drive before the active edge, then inspect registered state after NBA.
    // Save the old state so counting during a transaction can be checked.
    task automatic step(
        input logic write_enable,
        input logic [31:0] byte_addr,
        input logic [31:0] data,
        input logic [3:0] strobes
    );
        @(negedge clk);
        time_before    = dut.mtime;
        compare_before = dut.mtimecmp;
        addr  = byte_addr;
        wdata = data;
        wstrb = strobes;
        we    = write_enable;
        @(posedge clk);
        #1;
        we    = 1'b0;
        wstrb = 4'b0;
    endtask

    task automatic idle(input integer cycles);
        repeat (cycles) begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic set_time(input logic [63:0] value);
        step(1'b1, 32'h04, value[63:32], 4'hf);
        step(1'b1, 32'h00, value[31:0], 4'hf);
        check64("64-bit mtime write", dut.mtime, value);
    endtask

    task automatic set_compare(input logic [63:0] value);
        step(1'b1, 32'h0c, value[63:32], 4'hf);
        check64("mtime counts during compare-high write", dut.mtime, time_before + 64'd1);
        step(1'b1, 32'h08, value[31:0], 4'hf);
        check64("mtime counts during compare-low write", dut.mtime, time_before + 64'd1);
        check64("64-bit mtimecmp write", dut.mtimecmp, value);
    endtask

    // Asynchronous reads take #1 to settle. Keep read groups short enough
    // to finish before the next rising clock edge when reading mtime.
    task automatic check_read(
        input logic [31:0] byte_addr,
        input logic [31:0] expected
    );
        addr = byte_addr;
        #1;
        check64($sformatf("MMIO read at %08x", byte_addr),
                {32'b0, rdata}, {32'b0, expected});
    endtask

    task automatic reset_timer;
        @(negedge clk);
        rst   = 1'b1;
        we    = 1'b0;
        wstrb = 4'b0;
        repeat (2) @(posedge clk);
        #1;
        check64("reset mtime", dut.mtime, 64'b0);
        check64("reset mtimecmp", dut.mtimecmp, 64'hffff_ffff_ffff_ffff);
        check_irq(1'b0);
        @(negedge clk);
        rst = 1'b0;
    endtask

    initial begin
        rst   = 1'b1;
        addr  = 32'b0;
        wdata = 32'b0;
        wstrb = 4'b0;
        we    = 1'b0;
        $dumpfile("build/timer/timer.vcd");
        $dumpvars(0, tb_timer_mmio);

        reset_timer();
        idle(5);
        check64("five counting cycles", dut.mtime, 64'd5);
        check64("compare holds while counting", dut.mtimecmp, 64'hffff_ffff_ffff_ffff);
        check_irq(1'b0);
        $display("[PASS] reset and continuous counting");

        set_time(64'h1122_3344_5566_7788);
        set_compare(64'h99aa_bbcc_ddee_ff00);
        check_read(32'h00, 32'h5566_778a);
        check_read(32'h04, 32'h1122_3344);
        check_read(32'h08, 32'hddee_ff00);
        check_read(32'h0c, 32'h99aa_bbcc);
        $display("[PASS] four-register write/read mapping");

        set_time(64'h1122_3344_5566_7788);
        step(1'b1, 32'h01, 32'h0000_aa00, 4'b0010);
        check64("mtime low byte write", dut.mtime, 64'h1122_3344_5566_aa88);
        check_read(32'h01, 32'h5566_aa88);
        step(1'b1, 32'h07, 32'haa00_0000, 4'b1000);
        check64("mtime high byte write", dut.mtime, 64'haa22_3344_5566_aa88);
        check_read(32'h07, 32'haa22_3344);
        step(1'b1, 32'h00, 32'h00bb_00cc, 4'b0101);
        check64("mtime noncontiguous byte strobes", dut.mtime, 64'haa22_3344_55bb_aacc);
        $display("[PASS] mtime masked writes preserve all unselected bytes");

        // A write wins over counting, including carry into an unwritten half.
        set_time(64'h0000_0007_ffff_ffff);
        step(1'b1, 32'h00, 32'h0000_0022, 4'b0001);
        check64("low write cancels carry", dut.mtime, 64'h0000_0007_ffff_ff22);
        set_time(64'h0000_0007_ffff_ffff);
        step(1'b1, 32'h04, 32'h1122_3344, 4'hf);
        check64("high write holds low half", dut.mtime, 64'h1122_3344_ffff_ffff);
        idle(1);
        check64("low-to-high counting carry", dut.mtime, 64'h1122_3345_0000_0000);
        $display("[PASS] mtime write priority and 32-bit carry");

        set_compare(64'h1122_3344_5566_7788);
        step(1'b1, 32'h09, 32'h0000_aa00, 4'b0010);
        check64("compare low byte write", dut.mtimecmp, 64'h1122_3344_5566_aa88);
        check64("count during masked compare-low write", dut.mtime, time_before + 64'd1);
        check_read(32'h09, 32'h5566_aa88);
        step(1'b1, 32'h0f, 32'hab00_0000, 4'b1000);
        check64("compare high byte write", dut.mtimecmp, 64'hab22_3344_5566_aa88);
        check64("count during masked compare-high write", dut.mtime, time_before + 64'd1);
        check_read(32'h0f, 32'hab22_3344);
        $display("[PASS] mtimecmp masked writes and byte-address selection");

        for (integer word_index = 0; word_index < 4; word_index++) begin
            step(1'b1, word_index * 32'd4, 32'b0, 4'b0);
            check64("zero strobes keep counter running", dut.mtime, time_before + 64'd1);
            check64("zero strobes preserve compare", dut.mtimecmp, compare_before);
            step(1'b0, word_index * 32'd4, 32'b0, 4'hf);
            check64("we=0 keeps counter running", dut.mtime, time_before + 64'd1);
            check64("we=0 preserves compare", dut.mtimecmp, compare_before);
        end
        $display("[PASS] zero strobes and disabled writes on all four words");

        step(1'b1, 32'h10, 32'b0, 4'hf);
        check64("unmapped write keeps counting", dut.mtime, time_before + 64'd1);
        check64("unmapped write preserves compare", dut.mtimecmp, compare_before);
        check_read(32'h10, 32'b0);
        step(1'b1, 32'h100, 32'b0, 4'hf);
        check64("high address does not alias mtime", dut.mtime, time_before + 64'd1);
        check64("high address does not alias compare", dut.mtimecmp, compare_before);
        check_read(32'h100, 32'b0);
        $display("[PASS] unmapped addresses return zero and ignore writes");

        set_compare(64'd20);
        set_time(64'd19);
        check_irq(1'b0);
        idle(1);
        check64("deadline equality", dut.mtime, 64'd20);
        check_irq(1'b1);
        idle(3);
        check_irq(1'b1);
        set_compare(64'd100);
        check_irq(1'b0);
        set_compare(64'd1);
        check_irq(1'b1);
        $display("[PASS] deadline equality, persistent IRQ, and compare rearming");

        set_compare(64'h0000_0002_0000_0000);
        set_time(64'h0000_0001_ffff_ffff);
        check_irq(1'b0);
        idle(1);
        check64("deadline reached across carry", dut.mtime, 64'h0000_0002_0000_0000);
        check_irq(1'b1);
        set_compare(64'h7fff_ffff_ffff_ffff);
        set_time(64'h8000_0000_0000_0000);
        check_irq(1'b1);
        set_compare(64'h8000_0000_0000_0000);
        set_time(64'h7fff_ffff_ffff_ffff);
        check_irq(1'b0);
        $display("[PASS] full 64-bit unsigned comparison");

        set_compare(64'hffff_ffff_ffff_ffff);
        set_time(64'hffff_ffff_ffff_fffe);
        check_irq(1'b0);
        idle(1);
        check64("maximum counter value", dut.mtime, 64'hffff_ffff_ffff_ffff);
        check_irq(1'b1);
        idle(1);
        check64("64-bit counter wraparound", dut.mtime, 64'b0);
        check_irq(1'b0);
        $display("[PASS] 64-bit wraparound and IRQ follows comparison");

        set_compare(64'd1);
        set_time(64'd2);
        check_irq(1'b1);
        reset_timer();
        $display("[PASS] reset restores state after writes and a pending IRQ");
        $display("==============================");
        $display("    M9.1 TIMER MMIO PASS");
        $display("    %0d checks passed", checks);
        $display("==============================");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Timer test timeout");
    end

endmodule
