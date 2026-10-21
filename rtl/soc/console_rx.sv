module console_rx (
    input  logic        clk,
    input  logic        rst,

    // CPU MMIO，addr 是相对于 0x2000_0000 的偏移
    input  logic [31:0] addr,
    input  logic        we,
    input  logic [3:0]  wstrb,
    input  logic [31:0] wdata,
    output logic [31:0] rdata,

    // 仿真终端送来的字符
    input  logic        rx_valid,
    input  logic [7:0]  rx_data,
    output logic        rx_ready
);

    logic       full;
    logic [7:0] data_buf;
    logic       ack;

    assign ack = we &&
             (addr == 32'h0000_000c) &&
             wstrb[0] &&
             wdata[0];

    assign rx_ready = !rst && (!full || ack);

    always_comb begin
        rdata = 32'b0;

        // 0x04: status, 0x08: data. Reads do not consume the byte.
        case (addr)
            32'h0000_0004: rdata = {31'b0, full};
            32'h0000_0008: rdata = full ? {24'b0, data_buf} : 32'b0;
            default: ;
        endcase
    end

    always_ff @(posedge clk) begin

        if (rst) begin

            full     <= 1'b0;
            data_buf <= 8'b0;

        end

        else begin

            if (ack) begin

                full     <= 1'b0;
                data_buf <= 8'b0;

            end

            // A new byte wins when ACK and reception share the same edge.
            if (rx_valid && rx_ready) begin

                full     <= 1'b1;
                data_buf <= rx_data;

            end

        end

    end

endmodule
