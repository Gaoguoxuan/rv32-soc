module timer_mmio (
    input  logic        clk,
    input  logic        rst,

    input  logic [31:0] addr,    // 相对定时器基地址的字节偏移
    input  logic [31:0] wdata,
    input  logic [3:0]  wstrb,
    input  logic        we,

    output logic [31:0] rdata,
    output logic        timer_irq
);

    logic [63:0] mtime;
    logic [63:0] mtimecmp;

    logic [63:0] mtime_next;
    logic [63:0] mtimecmp_next;

    always_ff @(posedge clk) begin
        if (rst) begin
            mtime     <= 64'b0;
            mtimecmp  <= 64'hFFFF_FFFF_FFFF_FFFF;
        end
        else begin
            mtime     <= mtime_next;
            mtimecmp  <= mtimecmp_next;
        end
    end

    always_comb begin
        mtime_next     = mtime + 64'd1;
        mtimecmp_next  = mtimecmp;

        rdata          = 32'b0;

        if (we && (|wstrb)) begin
            case (addr[31:2])
                30'd0: begin
                    mtime_next = mtime;

                    for (int i = 0; i < 4; i++) begin
                        if (wstrb[i]) begin
                            mtime_next[(i*8)+:8] = wdata[(i*8)+:8];
                        end
                    end
                end
                30'd1: begin
                    mtime_next = mtime;

                    for (int i = 0; i < 4; i++) begin
                        if (wstrb[i]) begin
                            mtime_next[(i*8)+32+:8] = wdata[(i*8)+:8];
                        end
                    end
                end
                30'd2: begin
                    mtimecmp_next = mtimecmp;

                    for (int i = 0; i < 4; i++) begin
                        if (wstrb[i]) begin
                            mtimecmp_next[(i*8)+:8] = wdata[(i*8)+:8];
                        end
                    end
                end
                30'd3: begin
                    mtimecmp_next = mtimecmp;

                    for (int i = 0; i < 4; i++) begin
                        if (wstrb[i]) begin
                            mtimecmp_next[(i*8)+32+:8] = wdata[(i*8)+:8];
                        end
                    end
                end
                default: begin
                end
            endcase
        end
        case (addr[31:2])
            30'd0:   rdata = mtime[31:0];
            30'd1:   rdata = mtime[63:32];
            30'd2:   rdata = mtimecmp[31:0];
            30'd3:   rdata = mtimecmp[63:32];
            default: rdata = 32'b0;
        endcase
    end

    assign timer_irq = (mtime >= mtimecmp);



endmodule
