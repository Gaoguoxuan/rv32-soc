module tb_csr_file;

    logic clk;
    logic rst;

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


    csr_file dut (
        .clk          (clk),
        .rst          (rst),

        .csr_addr     (csr_addr),

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

            if (csr_rdata === expected) begin

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


    initial begin

        csr_addr  = 12'b0;
        csr_wdata = 32'b0;
        csr_we    = 1'b0;

        rst = 1'b1;

        repeat (2)
            @(posedge clk);

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


        if (errors == 0) begin

            $display("");
            $display("==============================");
            $display("       M7.1 CSR FILE PASS");
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