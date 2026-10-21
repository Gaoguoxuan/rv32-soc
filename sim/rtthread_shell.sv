module rtthread_shell (
    input  logic        clk,
    input  logic        rst,
    input  logic        uart_rx_valid,
    input  logic [7:0]  uart_rx_data,
    output logic        uart_rx_ready,
    output logic        uart_tx_valid,
    output logic [7:0]  uart_tx_data,
    output logic [31:0] pc,
    output logic        fault
);
    string image_path;

    rv32_soc #(.ROM_BYTES(65536), .RAM_BYTES(65536)) dut (
        .clk (clk), .rst (rst), .pc (pc),
        .uart_rx_valid (uart_rx_valid), .uart_rx_data (uart_rx_data),
        .uart_rx_ready (uart_rx_ready),
        .uart_tx_valid (uart_tx_valid), .uart_tx_data (uart_tx_data)
    );

    initial begin
        if (!$value$plusargs("image=%s", image_path))
            $fatal(1, "Supply +image=path/to/rtthread_shell.hex");
    end

    // Simulation-only image loading after ROM initialization, before the
    // CPU's first active edge. The production SoC hierarchy is unchanged.
    always @(negedge rst) begin
        $readmemh(image_path, dut.u_rom.mem);
    end

    assign fault = (dut.u_cpu.trap_enter && dut.u_cpu.trap_cause != 32'h8000_0007) ||
                   pc >= 65536 || pc[1:0] != 0;
endmodule
