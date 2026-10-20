module tb_misaligned_asm;

    logic clk;
    logic rst;
    logic [31:0] pc;
    logic [31:0] instr;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;
    logic        mem_we;
    logic [3:0]  mem_wstrb;

    localparam logic [31:0] RAM_BASE = 32'h1000_0000;
    localparam logic [31:0] RAM_END  = 32'h1000_003f;
    localparam logic [31:0] NOP      = 32'h0000_0013;
    localparam logic [31:0] MRET     = 32'h3020_0073;

    logic [31:0] imem [0:1023];
    logic [31:0] dmem [0:15];

    integer load_fault_count = 0;
    integer store_fault_count = 0;
    integer masked_fault_count = 0;
    integer mret_count = 0;
    integer ram_write_count = 0;

    logic [31:0] saved_instr;
    logic [31:0] saved_pc;
    logic [31:0] saved_mstatus;
    logic [31:0] saved_mtvec;
    logic [31:0] saved_mepc;
    logic [31:0] saved_mcause;
    logic [31:0] saved_mtval;
    logic [31:0] saved_mscratch;
    logic [31:0] saved_mie;
    logic [31:0] saved_mip;
    logic [31:0] expected_addr;
    logic [31:0] expected_cause;
    logic [31:0] saved_regs [0:31];
    logic [31:0] saved_ram [0:15];

    cpu_core dut (
        .clk       (clk),
        .rst       (rst),
        .timer_irq (1'b0),
        .instr     (instr),
        .pc        (pc),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_rdata (mem_rdata),
        .mem_we    (mem_we),
        .mem_wstrb (mem_wstrb)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_comb begin
        instr = (pc < 32'd4096) ? imem[pc[11:2]] : NOP;
        mem_rdata = (mem_addr >= RAM_BASE && mem_addr <= RAM_END)
                  ? dmem[mem_addr[5:2]] : 32'b0;
    end

    // A word array with byte strobes supports legal byte and halfword writes.
    // RAM_BASE is 64-byte aligned, so addr[5:2] selects the containing word.
    always_ff @(posedge clk) begin
        if (!rst && mem_we) begin
            if (mem_addr < RAM_BASE || mem_addr > RAM_END)
                $fatal(1, "RAM write out of range: %08x", mem_addr);
            for (integer lane = 0; lane < 4; lane++) begin
                if (mem_wstrb[lane])
                    dmem[mem_addr[5:2]][lane*8 +: 8] <= mem_wdata[lane*8 +: 8];
            end
            ram_write_count <= ram_write_count + 1;
        end
    end

    // Fixed expected addresses for the assembly's fault instructions.
    // These do not use the DUT's address calculation or misaligned signal.
    function automatic logic [31:0] fault_address(input logic [31:0] word);
        case (word)
            32'h001a_aa03: fault_address = 32'h1000_0001; // lw s4,1(s5)
            32'h002a_aa03: fault_address = 32'h1000_0002;
            32'h003a_aa03: fault_address = 32'h1000_0003;
            32'h001a_9a03: fault_address = 32'h1000_0001; // lh s4,1(s5)
            32'h003a_9a03: fault_address = 32'h1000_0003;
            32'h001a_da03: fault_address = 32'h1000_0001; // lhu s4,1(s5)
            32'h003a_da03: fault_address = 32'h1000_0003;
            32'h001a_a003: fault_address = 32'h1000_0001; // lw x0,1(s5)
            32'hfffc_aa03: fault_address = 32'h1000_0007; // lw s4,-1(s9)
            32'hfffc_9a03: fault_address = 32'h1000_0007; // lh s4,-1(s9)
            32'h016a_a0a3: fault_address = 32'h1000_0001; // sw s6,1(s5)
            32'h016a_a123: fault_address = 32'h1000_0002;
            32'h016a_a1a3: fault_address = 32'h1000_0003;
            32'h016a_90a3: fault_address = 32'h1000_0001; // sh s6,1(s5)
            32'h016a_91a3: fault_address = 32'h1000_0003;
            32'hff6c_afa3: fault_address = 32'h1000_0007; // sw s6,-1(s9)
            32'hff6c_9fa3: fault_address = 32'h1000_0007; // sh s6,-1(s9)
            default:       fault_address = 32'b0;
        endcase
    endfunction

    task automatic check_value(
        input string       name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        if (actual !== expected)
            $fatal(1, "%s: got=%08x expected=%08x (pc=%08x instr=%08x)",
                   name, actual, expected, saved_pc, saved_instr);
    endtask

    initial begin
        rst = 1'b1;
        for (integer i = 0; i < 1024; i++)
            imem[i] = NOP;
        for (integer i = 0; i < 16; i++)
            dmem[i] = 32'b0;
        $readmemh("build/misaligned/misaligned.hex", imem);
        $dumpfile("build/misaligned/misaligned.vcd");
        $dumpvars(0, tb_misaligned_asm);

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        for (integer cycle = 0; cycle < 2000; cycle++) begin
            saved_instr    = instr;
            saved_pc       = pc;
            saved_mstatus  = dut.mstatus;
            saved_mtvec    = dut.mtvec;
            saved_mepc     = dut.mepc;
            saved_mcause   = dut.mcause;
            saved_mtval    = dut.mtval;
            saved_mscratch = dut.mscratch;
            saved_mie      = dut.mie;
            saved_mip      = dut.mip;
            expected_addr  = fault_address(saved_instr);
            expected_cause = saved_instr[6:0] == 7'h03 ? 32'd4 : 32'd6;

            if (expected_addr != 32'b0) begin
                check_value("Fault effective address", mem_addr, expected_addr);
                check_value("Fault normal write enables",
                            {29'b0, dut.rf_we, dut.csr_we, mem_we}, 32'b0);
                check_value("Fault byte write strobes", {28'b0, mem_wstrb}, 32'b0);
                for (integer r = 0; r < 32; r++)
                    saved_regs[r] = dut.u_regfile.regs[r];
                for (integer w = 0; w < 16; w++)
                    saved_ram[w] = dmem[w];
            end
            else if (dut.trap_enter !== 1'b0)
                $fatal(1, "Unexpected trap during a legal instruction: pc=%08x instr=%08x",
                       saved_pc, saved_instr);

            @(posedge clk);
            #1;

            if (expected_addr != 32'b0) begin
                check_value("Trap PC", pc, {saved_mtvec[31:2], 2'b00});
                check_value("Trap mepc", dut.mepc, saved_pc);
                check_value("Trap cause", dut.mcause, expected_cause);
                check_value("Trap mtval address", dut.mtval, expected_addr);
                check_value("Trap MIE", {31'b0, dut.mstatus[3]}, 32'd0);
                check_value("Trap MPIE", {31'b0, dut.mstatus[7]},
                            {31'b0, saved_mstatus[3]});
                check_value("Trap MPP", {30'b0, dut.mstatus[12:11]}, 32'd3);
                check_value("Preserve mtvec", dut.mtvec, saved_mtvec);
                check_value("Preserve mscratch", dut.mscratch, saved_mscratch);
                check_value("Preserve mie", dut.mie, saved_mie);
                check_value("Preserve mip", dut.mip, saved_mip);
                for (integer r = 0; r < 32; r++)
                    check_value($sformatf("Preserve x%0d", r),
                                dut.u_regfile.regs[r], saved_regs[r]);
                for (integer w = 0; w < 16; w++)
                    check_value($sformatf("Preserve RAM[%0d]", w), dmem[w], saved_ram[w]);

                if (expected_cause == 32'd4)
                    load_fault_count++;
                else
                    store_fault_count++;
                if (!saved_mstatus[3])
                    masked_fault_count++;
                $display("[PASS] instr=%08x mepc=%08x cause=%0d mtval=%08x old MIE=%0d; registers/RAM preserved",
                         saved_instr, dut.mepc, dut.mcause, dut.mtval, saved_mstatus[3]);
            end
            else if (saved_instr == MRET) begin
                mret_count++;
                check_value("MRET PC", pc, saved_mepc);
                check_value("MRET MIE", {31'b0, dut.mstatus[3]},
                            {31'b0, saved_mstatus[7]});
                check_value("MRET MPIE", {31'b0, dut.mstatus[7]}, 32'd1);
                check_value("MRET MPP", {30'b0, dut.mstatus[12:11]}, 32'd3);
                check_value("MRET mepc", dut.mepc, saved_mepc);
                check_value("MRET mcause", dut.mcause, saved_mcause);
                check_value("MRET mtval", dut.mtval, saved_mtval);
            end

            if (pc[1:0] !== 2'b00 || pc >= 32'd4096)
                $fatal(1, "Invalid instruction address: %08x", pc);
            if (dut.u_regfile.regs[31] === 32'hffff_ffff)
                $fatal(1, "Assembly self-check failed: pc=%08x mepc=%08x mcause=%08x mtval=%08x",
                       pc, dut.mepc, dut.mcause, dut.mtval);

            if (dut.u_regfile.regs[31] === 32'd1) begin
                check_value("Load fault count", load_fault_count, 32'd11);
                check_value("Store fault count", store_fault_count, 32'd8);
                check_value("Faults with MIE=0", masked_fault_count, 32'd2);
                check_value("MRET count", mret_count, 32'd19);
                check_value("Handler entries", dut.u_regfile.regs[8], 32'd19);
                check_value("Successful returns", dut.u_regfile.regs[9], 32'd19);
                check_value("Legal RAM write count", ram_write_count, 32'd10);
                check_value("RAM word 0 sentinel", dmem[0], 32'h1020_3040);
                check_value("RAM word 1 sentinel", dmem[1], 32'h5060_7080);
                check_value("Legal byte stores", dmem[4], 32'h55fe_7f80);
                check_value("Legal halfword stores", dmem[5], 32'h8abc_2468);
                check_value("Load destination sentinel", dut.u_regfile.regs[20], 32'h1357_9bdf);
                $display("==============================");
                $display("  M8.4 MISALIGNED ACCESS PASS");
                $display("==============================");
                $finish;
            end
            @(negedge clk);
        end

        $fatal(1, "Misaligned access timeout: pc=%08x loads=%0d stores=%0d returns=%0d",
               pc, load_fault_count, store_fault_count, mret_count);
    end

endmodule
