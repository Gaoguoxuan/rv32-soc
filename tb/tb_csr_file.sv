module tb_csr_file;

    logic clk;
    logic rst;
    logic timer_irq;
    logic trap_enter;
    logic mret_enter;

    logic [11:0] csr_addr;
    logic [31:0] csr_rdata;

    logic csr_valid;
    logic csr_writable;

    logic        csr_we;
    logic [31:0] csr_wdata;

    logic [31:0] mstatus;
    logic [31:0] mie;
    logic [31:0] mtvec;
    logic [31:0] mscratch;
    logic [31:0] mepc;
    logic [31:0] mcause;
    logic [31:0] mip;

    integer errors = 0;
    integer mtip_checks = 0;


    csr_file dut (
        .clk          (clk),
        .rst          (rst),

        .csr_addr     (csr_addr),

        .trap_enter   (trap_enter),
        .trap_pc      (32'h00000080),
        .trap_cause   (32'd11),
        .trap_tval    (32'b0),

        .timer_irq    (timer_irq),
        .mret_enter   (mret_enter),
        .mtval        (),

        .csr_rdata    (csr_rdata),
        .csr_valid    (csr_valid),
        .csr_writable (csr_writable),

        .csr_we       (csr_we),
        .csr_wdata    (csr_wdata),

        .mstatus      (mstatus),
        .mie          (mie),
        .mtvec        (mtvec),
        .mscratch     (mscratch),
        .mepc         (mepc),
        .mcause       (mcause),
        .mip          (mip)
    );


    initial begin
        clk = 1'b0;

        forever #5
            clk = ~clk;
    end


    task automatic write_csr(
        input logic [11:0] addr,
        input logic [31:0] data
    );
        begin

            @(negedge clk);

            csr_addr  = addr;
            csr_wdata = data;
            csr_we    = 1'b1;

            @(posedge clk);

            #1;

            csr_we = 1'b0;

        end
    endtask


    task automatic check_csr(
        input logic [11:0] addr,
        input logic [31:0] expected,
        input string       name
    );
        begin

            csr_addr = addr;

            #1;

            if (csr_valid && csr_rdata === expected) begin

                $display(
                    "[PASS] %-10s = %08x",
                    name,
                    csr_rdata
                );

            end

            else begin

                $display(
                    "[FAIL] %-10s got=%08x expected=%08x",
                    name,
                    csr_rdata,
                    expected
                );

                errors++;

            end

        end
    endtask


    task automatic check_mtip(input logic pending, input string name);
        logic [31:0] expected;
        begin
            expected = pending ? 32'h00000080 : 32'b0;
            check_csr(12'h344, expected, name);
            if (mip !== expected) begin
                $display("[FAIL] %s: mip output=%08x expected=%08x", name, mip, expected);
                errors++;
            end
            mtip_checks++;
        end
    endtask


    initial begin

        csr_addr  = 12'b0;
        csr_wdata = 32'b0;
        csr_we    = 1'b0;
        timer_irq = 1'b0;
        trap_enter = 1'b0;
        mret_enter = 1'b0;

        rst = 1'b1;

        repeat (2)
            @(posedge clk);

        @(negedge clk);
        rst = 1'b0;

        check_mtip(1'b0, "MTIP reset");


        // --------------------------------------------
        // mtval reset, CSR write/read, and reset after a nonzero value.
        // The second reset catches a missing reset assignment even in a
        // simulator that initializes registers to zero automatically.
        // --------------------------------------------

        check_csr(12'h343, 32'b0, "mtval reset");

        if (!csr_writable) begin
            $display("[FAIL] mtval should be writable");
            errors++;
        end

        write_csr(12'h343, 32'h89abcdef);
        check_csr(12'h343, 32'h89abcdef, "mtval write");

        write_csr(12'h343, 32'h13579bdf);
        check_csr(12'h343, 32'h13579bdf, "mtval rewrite");

        @(negedge clk);
        rst = 1'b1;
        @(posedge clk);
        #1;
        check_csr(12'h343, 32'b0, "mtval re-reset");
        @(negedge clk);
        rst = 1'b0;


        // --------------------------------------------
        // mscratch
        // --------------------------------------------

        write_csr(
            12'h340,
            32'h12345678
        );

        check_csr(
            12'h340,
            32'h12345678,
            "mscratch"
        );


        // --------------------------------------------
        // mtvec
        // --------------------------------------------

        write_csr(
            12'h305,
            32'h00000100
        );

        check_csr(
            12'h305,
            32'h00000100,
            "mtvec"
        );


        // --------------------------------------------
        // mepc
        // --------------------------------------------

        write_csr(
            12'h341,
            32'h00000080
        );

        check_csr(
            12'h341,
            32'h00000080,
            "mepc"
        );


        // --------------------------------------------
        // unknown CSR
        // --------------------------------------------

        csr_addr = 12'hFFF;

        #1;

        if (!csr_valid)
            $display("[PASS] invalid CSR detected");
        else begin
            $display("[FAIL] invalid CSR not detected");
            errors++;
        end


        // --------------------------------------------
        // mip is currently read-only
        // --------------------------------------------

        csr_addr = 12'h344;

        #1;

        if (!csr_writable)
            $display("[PASS] mip read-only");
        else begin
            $display("[FAIL] mip should be read-only");
            errors++;
        end


        // --------------------------------------------
        // MTIP describes pending state independently of both enable bits.
        // Change the input away from a rising edge to catch a registered
        // or sticky implementation instead of the intended direct path.
        // --------------------------------------------

        for (integer enables = 0; enables < 4; enables++) begin
            write_csr(12'h300, enables[1] ? 32'h8 : 32'b0);
            write_csr(12'h304, enables[0] ? 32'h80 : 32'b0);

            @(negedge clk);
            #1;
            timer_irq = 1'b1;
            check_mtip(1'b1, $sformatf("MTIP high MIE=%0b MTIE=%0b", enables[1], enables[0]));

            @(negedge clk);
            #1;
            timer_irq = 1'b0;
            check_mtip(1'b0, $sformatf("MTIP low MIE=%0b MTIE=%0b", enables[1], enables[0]));

            check_csr(12'h300, enables[1] ? 32'h8 : 32'b0, "MIE preserved");
            check_csr(12'h304, enables[0] ? 32'h80 : 32'b0, "MTIE preserved");
        end

        // Keep the current project's read-only mip policy: software cannot
        // assert/clear MTIP or set any of the unimplemented pending bits.
        write_csr(12'h344, 32'hffffffff);
        check_mtip(1'b0, "SW cannot set MTIP");

        @(negedge clk);
        timer_irq = 1'b1;
        write_csr(12'h344, 32'b0);
        check_mtip(1'b1, "SW cannot clear MTIP");
        write_csr(12'h344, 32'hffffffff);
        check_mtip(1'b1, "Other pending bits zero");

        // Trap entry masks delivery through MIE, but must retain pending
        // state. MRET restores MIE and also must leave MTIP asserted.
        @(negedge clk);
        trap_enter = 1'b1;
        @(posedge clk);
        #1;
        trap_enter = 1'b0;
        check_mtip(1'b1, "Trap preserves MTIP");
        check_csr(12'h300, 32'h1880, "Trap masks MIE");

        @(negedge clk);
        mret_enter = 1'b1;
        @(posedge clk);
        #1;
        mret_enter = 1'b0;
        check_mtip(1'b1, "MRET preserves MTIP");
        check_csr(12'h300, 32'h1888, "MRET restores MIE");

        // mip has no stored reset state: it still reflects a high external
        // input during CSR reset. In the SoC the timer itself resets low.
        @(negedge clk);
        rst = 1'b1;
        @(posedge clk);
        #1;
        check_mtip(1'b1, "Reset with IRQ high");
        check_csr(12'h300, 32'b0, "MIE reset");
        check_csr(12'h304, 32'b0, "MTIE reset");

        @(negedge clk);
        #1;
        timer_irq = 1'b0;
        check_mtip(1'b0, "IRQ clears during reset");
        @(negedge clk);
        rst = 1'b0;
        check_mtip(1'b0, "MTIP after reset");


        if (errors == 0) begin

            $display("");
            $display("==============================");
            $display("       M7.1 CSR FILE PASS");
            $display("   M8.3 MTVAL CSR CHECKS PASS");
            $display("   M9.3.1 MTIP CSR CHECKS PASS (%0d checks)", mtip_checks);
            $display("==============================");

        end

        else begin

            $fatal(
                1,
                "%0d CSR test(s) failed",
                errors
            );

        end


        $finish;

    end

endmodule
