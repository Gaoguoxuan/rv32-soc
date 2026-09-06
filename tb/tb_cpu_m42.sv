module tb_cpu_m42;

    logic clk;
    logic rst;

    logic [31:0] pc;
    logic [31:0] instr;

    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;
    logic        mem_we;

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

            32'h00000000:
                instr = 32'h00500093;

            32'h00000004:
                instr = 32'h00500113;

            // beq x1,x2,+8
            32'h00000008:
                instr = 32'h00208463;

            // skipped
            32'h0000000C:
                instr = 32'h06F00513;

            // lui x3,0x12345
            32'h00000010:
                instr = 32'h123451B7;

            // auipc x4,0x1
            32'h00000014:
                instr = 32'h00001217;

            // jal x5,+8
            32'h00000018:
                instr = 32'h008002EF;

            // skipped
            32'h0000001C:
                instr = 32'h07000513;

            // addi x6,x0,44
            32'h00000020:
                instr = 32'h02C00313;

            // jalr x7,0(x6)
            32'h00000024:
                instr = 32'h000303E7;

            // skipped
            32'h00000028:
                instr = 32'h07100513;

            // addi x8,x0,77
            32'h0000002C:
                instr = 32'h04D00413;

            default:
                instr = 32'h00000013;

        endcase

    end

    always_comb begin
        mem_rdata = data_mem[mem_addr[7:2]];
    end

    always_ff @(posedge clk) begin
        if (mem_we)
            data_mem[mem_addr[7:2]] <= mem_wdata;
    end
 
    initial begin

        integer i;

        $dumpfile("build/cpu_m42.vcd");
        $dumpvars(0, tb_cpu_m42);


        // Initialize RAM
        for (i = 0; i < 64; i = i + 1)
            data_mem[i] = 32'b0;


        rst = 1'b1;


        repeat (2)
            @(posedge clk);


        @(negedge clk);
        rst = 1'b0;

        repeat (9) begin
            
            @(negedge clk)

            $display(
                "PC=%08x instr=%08x reg_we=%0d rd=%08x data=%08x branch=%0d rs1_data=%08x rs2_data=%08x imm=%08x",
                pc,
                instr,
                dbg_reg_we,
                dbg_rd_addr,
                dbg_rd_data,
                dbg_branch_taken,
                dbg_rs1_data,
                dbg_rs2_data,
                dbg_imm
            );

        end

        if (dut.u_regfile.regs[1] !== 32'd5) begin
            $display("[FAIL] x1");
            errors++;
        end
        else    
            $display("[PASS] x1=5");

        if (dut.u_regfile.regs[2] !== 32'd5) begin
            $display("[FAIL] x2");
            errors++;
        end
        else    
            $display("[PASS] x2=5");

        if (dut.u_regfile.regs[10] !== 32'd0) begin
            $display("[FAIL] x10");
            errors++;
        end
        else    
            $display("[PASS] x10=0");

        if (dut.u_regfile.regs[3] !== 32'h12345000) begin
            $display("[FAIL] x3");
            errors++;
        end
        else    
            $display("[PASS] x3=32'h12345000");

        if (dut.u_regfile.regs[4] !== 32'h1014) begin
            $display("[FAIL] x4");
            errors++;
        end
        else    
            $display("[PASS] x4=32'h1014");

        if (dut.u_regfile.regs[5] !== 32'h1c) begin
            $display("[FAIL] x5");
            errors++;
        end
        else    
            $display("[PASS] x5=32'h1c");

        if (dut.u_regfile.regs[6] !== 32'd44) begin
            $display("[FAIL] x6");
            errors++;
        end
        else    
            $display("[PASS] x6=44");

        if (dut.u_regfile.regs[7] !== 32'h28) begin
            $display("[FAIL] x7");
            errors++;
        end
        else    
            $display("[PASS] x7=32'h28");

        if (dut.u_regfile.regs[8] !== 32'd77) begin
            $display("[FAIL] x8");
            errors++;
        end
        else    
            $display("[PASS] x8=77");

        if (errors == 0) begin
        
            $display("");
            $display("==============================");
            $display("         M4.2 ALL PASS");
            $display("==============================");

        end
        else begin
        
            $display("");
            $display(
                "M4.2 FAILED: %0d error(s)",
                errors
            );

            $fatal(1);
        
        end

        $finish;

    end    

endmodule
