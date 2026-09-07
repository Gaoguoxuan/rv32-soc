module uart_mmio (
    input  logic        clk,
    input  logic        rst,

    input  logic        we,
    input  logic [31:0] wdata,

    output logic        tx_valid,
    output logic [7:0]  tx_data
);

    always_ff @(posedge clk) begin

        if (rst) begin

            tx_valid <= 1'b0;
            tx_data  <= 8'b0;

        end

        else begin

            tx_valid <= 1'b0;

            if (we) begin

                tx_valid <= 1'b1;
                tx_data  <= wdata[7:0];

            end

        end

    end

endmodule
