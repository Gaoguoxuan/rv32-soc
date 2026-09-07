module rv32_soc (
    input  logic        clk,
    input  logic        rst,

    input  logic [31:0] instr,

    output logic [31:0] pc,

    output logic        uart_tx_valid,
    output logic [7:0]  uart_tx_data
);

    // ============================================================
    // CPU memory interface
    // ============================================================

    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;

    logic        mem_we;
    logic [3:0]  mem_wstrb;


    // ============================================================
    // Address map
    // ============================================================

    localparam logic [31:0] RAM_BASE = 32'h1000_0000;

    localparam logic [31:0] RAM_END  = 32'h1000_03FF;

    localparam logic [31:0] UART_TX  = 32'h2000_0000;


    logic ram_sel;
    logic uart_sel;

    logic [31:0] ram_rdata;


    // ============================================================
    // CPU
    // ============================================================

    cpu_core u_cpu (
        .clk       (clk),
        .rst       (rst),

        .instr     (instr),
        .pc        (pc),

        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_rdata (mem_rdata),

        .mem_we    (mem_we),
        .mem_wstrb (mem_wstrb)
    );


    // ============================================================
    // Address decoder
    // ============================================================

    always_comb begin

        ram_sel  = (mem_addr >= RAM_BASE) &&
                   (mem_addr <= RAM_END);

        uart_sel = (mem_addr == UART_TX);

    end


    // ============================================================
    // RAM
    // ============================================================

    simple_ram #(
        .WORDS (256)
    ) u_ram (
        .clk   (clk),

        .addr  (mem_addr - RAM_BASE),

        .wdata (mem_wdata),
        .wstrb (mem_wstrb),

        .we    (
            mem_we &&
            ram_sel
        ),

        .rdata (ram_rdata)
    );


    // ============================================================
    // UART MMIO
    // ============================================================

    uart_mmio u_uart (
        .clk      (clk),
        .rst      (rst),

        .we       (
            mem_we &&
            uart_sel &&
            mem_wstrb[0]
        ),

        .wdata    (mem_wdata),

        .tx_valid (uart_tx_valid),
        .tx_data  (uart_tx_data)
    );


    // ============================================================
    // Read mux
    // ============================================================

    always_comb begin

        if (ram_sel)
            mem_rdata = ram_rdata;

        else
            mem_rdata = 32'b0;

    end

endmodule
