module tb_cpu_m43;
    logic clk;
    logic rst;

    logic [31:0] pc;
    logic [31:0] instr;

    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;
    logic        mem_we;
    logic [3:0]  mem_wstrb;

    logic        dbg_reg_we;
    logic [4:0]  dbg_rd_addr;
    logic [31:0] dbg_rd_data;

    logic [31:0] dbg_rs1_data;
    logic [31:0] dbg_rs2_data;

    logic [31:0] dbg_imm;

    logic        dbg_branch_taken;
    logic        dbg_illegal;

    int errors = 0;

    logic [31:0] data_mem [0:63];

    cpu_core dut (
        .clk                (clk),
        .rst                (rst),

        .instr              (instr),
        .pc                 (pc),

        .mem_addr           (mem_addr),
        .mem_wdata          (mem_wdata),
        .mem_rdata          (mem_rdata),
        .mem_we             (mem_we),
        .mem_wstrb          (mem_wstrb),

        .dbg_reg_we         (dbg_reg_we),
        .dbg_rd_addr        (dbg_rd_addr),
        .dbg_rd_data        (dbg_rd_data),

        .dbg_rs1_data       (dbg_rs1_data),
        .dbg_rs2_data       (dbg_rs2_data),

        .dbg_imm            (dbg_imm),

        .dbg_branch_taken   (dbg_branch_taken),
        .dbg_illegal        (dbg_illegal)
    );

    initial begin
        clk = 1'b0;

        forever #5 clk = ~clk;
    end

    always_comb begin

        case (pc)

            // addi x1,x0,-1
            32'h00000000:
                instr = 32'hFFF00093;

            // sb x1,0(x0)
            32'h00000004:
                instr = 32'h00100023;

            // lb x2,0(x0)
            32'h00000008:
                instr = 32'h00000103;

            // lbu x3,0(x0)
            32'h0000000C:
                instr = 32'h00004183;

            // addi x4,x0,127
            32'h00000010:
                instr = 32'h07F00213;

            // sb x4,1(x0)
            32'h00000014:
                instr = 32'h004000A3;

            // lh x5,0(x0)
            32'h00000018:
                instr = 32'h00001283;

            // addi x6,x0,-2
            32'h0000001C:
                instr = 32'hFFE00313;

            // sh x6,2(x0)
            32'h00000020:
                instr = 32'h00601123;

            // lh x7,2(x0)
            32'h00000024:
                instr = 32'h00201383;

            // lhu x8,2(x0)
            32'h00000028:
                instr = 32'h00205403;

            // lw x9,0(x0)
            32'h0000002C:
                instr = 32'h00002483;

            // addi x10,x0,0x123
            32'h00000030:
                instr = 32'h12300513;

            // sw x10,4(x0)
            32'h00000034:
                instr = 32'h00A02223;

            // lw x11,4(x0)
            32'h00000038:
                instr = 32'h00402583;

            default:
                instr = 32'h00000013;

        endcase

    end

    always_comb begin
        mem_rdata = data_mem[mem_addr[7:2]];
    end

    always_ff @(posedge clk) begin

        if (mem_we) begin

            if (mem_wstrb[0])
                data_mem[mem_addr[7:2]][7:0] <= mem_wdata[7:0];

            if (mem_wstrb[1])
                data_mem[mem_addr[7:2]][15:8] <= mem_wdata[15:8];

            if (mem_wstrb[2])
                data_mem[mem_addr[7:2]][23:16] <= mem_wdata[23:16];

            if (mem_wstrb[3])
                data_mem[mem_addr[7:2]][31:24] <= mem_wdata[31:24];

        end

    end

    initial begin
        integer i;

        $dumpfile("build/cpu_m43.vcd");
        $dumpvars(0, tb_cpu_m43);

        for (i = 0; i < 64; i = i + 1)
            data_mem[i] = 32'b0;

        rst = 1'b1;


        repeat (2)
            @(posedge clk);


        @(negedge clk);
        rst = 1'b0;

        repeat (15) begin
            @(negedge clk);

            $display(
                "PC=%08x instr=%08x reg_we=%0d rd=%08x data=%08x branch=%0d rs1_data=%08x rs2_data=%08x imm=%08x mem_we=%0d mem_addr=%08x mem_rdata=%08x mem_wdata=%08x mem_wstrb=%08x",
                pc,
                instr,
                dbg_reg_we,
                dbg_rd_addr,
                dbg_rd_data,
                dbg_branch_taken,
                dbg_rs1_data,
                dbg_rs2_data,
                dbg_imm,
                mem_we,
                mem_addr,
                mem_rdata,
                mem_wdata,
                mem_wstrb
            );

        end

        if (dut.u_regfile.regs[2] !== 32'hFFFFFFFF) begin
            $display("[FAIL] LB");
            errors++;
        end
        else
            $display("[PASS] LB sign extension");


        if (dut.u_regfile.regs[3] !== 32'h000000FF) begin
            $display("[FAIL] LBU");
            errors++;
        end
        else
            $display("[PASS] LBU zero extension");


        if (dut.u_regfile.regs[5] !== 32'h00007FFF) begin
            $display("[FAIL] LH positive");
            errors++;
        end
        else
            $display("[PASS] LH positive");


        if (dut.u_regfile.regs[7] !== 32'hFFFFFFFE) begin
            $display("[FAIL] LH negative");
            errors++;
        end
        else
            $display("[PASS] LH sign extension");


        if (dut.u_regfile.regs[8] !== 32'h0000FFFE) begin
            $display("[FAIL] LHU");
            errors++;
        end
        else
            $display("[PASS] LHU zero extension");


        if (dut.u_regfile.regs[9] !== 32'hFFFE7FFF) begin
            $display("[FAIL] LW");
            errors++;
        end
        else
            $display("[PASS] LW = FFFE7FFF");


        if (data_mem[0] !== 32'hFFFE7FFF) begin
            $display(
                "[FAIL] SB/SH RAM=%08x",
                data_mem[0]
            );
            errors++;
        end
        else
            $display("[PASS] SB/SH byte lanes");


        if (dut.u_regfile.regs[11] !== 32'h00000123) begin
            $display("[FAIL] SW/LW regression");
            errors++;
        end
        else
            $display("[PASS] SW/LW regression");

        if (errors == 0) begin

            $display("");
            $display("==============================");
            $display("        M4.3 ALL PASS");
            $display("==============================");

        end
        else begin

            $display("");
            $display(
                "M4.3 FAILED: %0d error(s)",
                errors
            );

            $fatal(1);

        end


        $finish;

    end



endmodule
