module simple_ram #(
    parameter integer WORDS = 256
)(
    input  logic        clk,

    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input  logic [3:0]  wstrb,
    input  logic        we,

    output logic [31:0] rdata
);

    logic [31:0] mem [0:WORDS-1];

    wire [$clog2(WORDS)-1:0] word_addr;

    assign word_addr = addr[$clog2(WORDS)+1:2];


    // Asynchronous read
    always_comb begin
        rdata = mem[word_addr];
    end


    // Synchronous write
    always_ff @(posedge clk) begin

        if (we) begin

            if (wstrb[0])
                mem[word_addr][7:0] <= wdata[7:0];

            if (wstrb[1])
                mem[word_addr][15:8] <= wdata[15:8];

            if (wstrb[2])
                mem[word_addr][23:16] <= wdata[23:16];

            if (wstrb[3])
                mem[word_addr][31:24] <= wdata[31:24];

        end

    end

endmodule
