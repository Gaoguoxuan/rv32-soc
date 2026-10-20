module tb_cpu_m3;

    logic clk;
    logic rst;

    // ============================
    // CPU instruction interface
    // ============================

    logic [31:0] pc;
    logic [31:0] instr;

    // ============================
    // Data memory interface
    // ============================

    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;
    logic        mem_we;

    // ============================
    // Debug
    // ============================

    logic        dbg_reg_we;
    logic [4:0]  dbg_rd_addr;
    logic [31:0] dbg_rd_data;

    logic [31:0] dbg_rs1_data;
    logic [31:0] dbg_rs2_data;

    logic [31:0] dbg_imm;

    logic        dbg_branch_taken;
    logic        dbg_illegal;

    int errors = 0;

    // ============================
    // Data RAM
    // 64 x 32-bit words
    // ============================

    logic [31:0] data_mem [0:63];

    // ============================
    // CPU
    // ============================

    cpu_core dut (
        .clk              (clk),
        .rst              (rst),

        .timer_irq        (1'b0),

        .instr            (instr),
        .pc               (pc),

        .mem_addr         (mem_addr),
        .mem_wdata        (mem_wdata),
        .mem_rdata        (mem_rdata),
        .mem_we           (mem_we),

        .dbg_reg_we       (dbg_reg_we),
        .dbg_rd_addr      (dbg_rd_addr),
        .dbg_rd_data      (dbg_rd_data),

        .dbg_rs1_data     (dbg_rs1_data),
        .dbg_rs2_data     (dbg_rs2_data),

        .dbg_imm          (dbg_imm),

        .dbg_branch_taken (dbg_branch_taken),
        .dbg_illegal      (dbg_illegal)
    );

    // ============================
    // Clock
    // ============================

    initial begin
        clk = 1'b0;

        forever #5 clk = ~clk;
    end

    // ============================
    // Instruction ROM
    // ============================

    always_comb begin

        case (pc)

            // addi x1, x0, 10
            32'h00000000:
                instr = 32'h00A00093;

            // addi x2, x0, 20
            32'h00000004:
                instr = 32'h01400113;

            // add x3, x1, x2
            32'h00000008:
                instr = 32'h002081B3;

            // sub x4, x3, x1
            32'h0000000C:
                instr = 32'h40118233;

            // sw x3, 0(x0)
            32'h00000010:
                instr = 32'h00302023;

            // lw x5, 0(x0)
            32'h00000014:
                instr = 32'h00002283;

            // beq x5, x3, +8
            //
            // PC = 0x18
            // target = 0x20
            32'h00000018:
                instr = 32'h00328463;

            // SHOULD BE SKIPPED
            // addi x6, x0, 111
            32'h0000001C:
                instr = 32'h06F00313;

            // target:
            // addi x6, x0, 222
            32'h00000020:
                instr = 32'h0DE00313;

            // NOP
            default:
                instr = 32'h00000013;

        endcase

    end

    // ============================
    // Asynchronous RAM Read
    // ============================

    always_comb begin
        mem_rdata = data_mem[mem_addr[7:2]];
    end

    // ============================
    // Synchronous RAM Write
    // ============================

     always_ff @(posedge clk) begin
        if (mem_we)
            data_mem[mem_addr[7:2]] <= mem_wdata;
    end

    // ============================
    // Test
    // ============================

    initial begin

        integer i;

        $dumpfile("build/cpu_m3.vcd");
        $dumpvars(0, tb_cpu_m3);


        // Initialize RAM
        for (i = 0; i < 64; i = i + 1)
            data_mem[i] = 32'b0;


        rst = 1'b1;


        repeat (2)
            @(posedge clk);


        @(negedge clk);
        rst = 1'b0;


        // Run enough instructions
        repeat (9) begin

            @(negedge clk);

            $display(
                "PC=%08x instr=%08x we=%0d rd=x%0d data=%08x mem_we=%0d mem_addr=%08x branch=%0d",
                pc,
                instr,

                dbg_reg_we,
                dbg_rd_addr,
                dbg_rd_data,

                mem_we,
                mem_addr,

                dbg_branch_taken
            );

        end


        // ============================
        // Check RAM
        // ============================

        if (data_mem[0] !== 32'd30) begin

            $display(
                "[FAIL] RAM[0]=%08x expected=0000001e",
                data_mem[0]
            );

            errors++;

        end
        else begin

            $display(
                "[PASS] SW/LW memory value = %08x",
                data_mem[0]
            );

        end

        // ============================
        // Access internal registers
        // ============================

        if (dut.u_regfile.regs[1] !== 32'd10) begin
            $display("[FAIL] x1");
            errors++;
        end
        else
            $display("[PASS] x1 = 10");


        if (dut.u_regfile.regs[2] !== 32'd20) begin
            $display("[FAIL] x2");
            errors++;
        end
        else
            $display("[PASS] x2 = 20");


        if (dut.u_regfile.regs[3] !== 32'd30) begin
            $display("[FAIL] x3");
            errors++;
        end
        else
            $display("[PASS] x3 = 30");


        if (dut.u_regfile.regs[4] !== 32'd20) begin
            $display("[FAIL] x4");
            errors++;
        end
        else
            $display("[PASS] x4 = 20");


        if (dut.u_regfile.regs[5] !== 32'd30) begin
            $display("[FAIL] x5");
            errors++;
        end
        else
            $display("[PASS] x5 = 30");


        if (dut.u_regfile.regs[6] !== 32'd222) begin

            $display(
                "[FAIL] x6=%0d expected=222",
                dut.u_regfile.regs[6]
            );

            errors++;

        end
        else begin

            $display(
                "[PASS] BEQ correctly skipped instruction, x6=222"
            );

        end

        // ============================
        // Summary
        // ============================

        if (errors == 0) begin

            $display("");
            $display("==============================");
            $display("         M3 ALL PASS");
            $display("==============================");

        end
        else begin

            $display("");
            $display(
                "M3 FAILED: %0d error(s)",
                errors
            );

            $fatal(1);

        end


        $finish;

    end

endmodule
