module tb_soc_memory_params #(
    parameter int unsigned ROM_BYTES = 8,
    parameter int unsigned RAM_BYTES = 16
);
    logic clk = 1'b0;
    logic [31:0] pc;

    rv32_soc #(
        .ROM_BYTES (ROM_BYTES), .RAM_BYTES (RAM_BYTES)
    ) dut (
        .clk (clk), .rst (1'b1), .pc (pc),
        .uart_tx_valid (), .uart_tx_data ()
    );

    initial begin
        forever #5 clk = ~clk;
    end

    initial begin
        #1;
        if ($size(dut.u_rom.mem) != ROM_BYTES / 4 ||
            $size(dut.u_ram.mem) != RAM_BYTES / 4 ||
            dut.ROM_END != ROM_BYTES - 1 || dut.RAM_END != 32'h1000_0000 + RAM_BYTES - 1)
            $fatal(1, "Capacity parameters did not reach arrays/address decoder");
        repeat (2) @(posedge clk);
        #1;
        if (pc !== 32'b0)
            $fatal(1, "Reset PC changed");
        $display("[PASS] small asymmetric configuration: ROM=%0d bytes, RAM=%0d bytes", ROM_BYTES, RAM_BYTES);
        $finish;
    end
endmodule
