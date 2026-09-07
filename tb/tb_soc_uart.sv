module tb_soc_uart;

    logic clk;
    logic rst;

    logic [31:0] pc;
    //logic [31:0] instr;

    logic uart_tx_valid;
    logic [7:0] uart_tx_data;

    //logic [31:0] imem [0:1023];

    //integer i;

    // ============================================================
    // DUT
    // ============================================================

    rv32_soc #(
        .ROM_HEX (
            "build/uart/uart.hex"
        )
    ) dut (
        .clk           (clk),
        .rst           (rst),

        //.instr         (instr),
        .pc            (pc),

        .uart_tx_valid (uart_tx_valid),
        .uart_tx_data  (uart_tx_data)
    );

    // ============================================================
    // Clock
    // ============================================================

    initial begin

        clk = 1'b0;

        forever #5 clk = ~clk;

    end


    // always_comb begin

    //     if (pc < 32'h00001000)
    //         instr = imem[pc[11:2]];
    //     else
    //         instr = 32'h00000013;

    // end

    // ============================================================
    // Observe UART
    // ============================================================

    always_ff @(posedge clk) begin

        if (!rst && uart_tx_valid)
            $write("%c", uart_tx_data);

    end

    // ============================================================
    // Simulation
    // ============================================================

    initial begin

        $dumpfile(
            "build/uart/uart.vcd"
        );

        $dumpvars(
            0,
            tb_soc_uart
        );

    end


    initial begin

        rst = 1'b1;

        // for (i = 0; i < 1024; i = i + 1)
        //     imem[i] = 32'h00000013;

        // $readmemh(
        //     "build/uart/uart.hex",
        //     imem
        // );

        repeat (2)
            @(posedge clk);

        @(negedge clk);

        rst = 1'b0;


        repeat (500)
            @(posedge clk);


        $display("");
        $display("==============================");
        //$display("       UART TEST DONE");
        $display("       M6.2 ROM TEST DONE");
        $display("==============================");

        $finish;

    end

endmodule