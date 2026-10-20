module tb_cpu_timer_irq;

    localparam logic [31:0] ENTRY = 32'h0000_0040;
    localparam logic [31:0] VECTOR = 32'h0000_0200;
    localparam logic [31:0] NOP = 32'h0000_0013;
    localparam logic [31:0] MRET = 32'h3020_0073;
    localparam logic [31:0] TIMER_CAUSE = 32'h8000_0007;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic timer_irq = 1'b0;
    logic [31:0] pc;
    logic [31:0] instr;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;
    logic mem_we;
    logic [3:0] mem_wstrb;
    logic [31:0] imem [0:255];
    logic [31:0] dmem [0:15];

    integer ram_writes = 0;
    integer csr_writes = 0;
    integer checks = 0;
    integer scenarios = 0;
    integer irq_entries = 0;
    integer sync_entries = 0;
    integer returns = 0;
    string scenario = "startup";

    logic [31:0] saved_regs [0:31];
    logic [31:0] saved_ram [0:15];
    logic [31:0] saved_pc;
    logic [31:0] saved_status;
    logic [31:0] saved_mie;
    logic [31:0] saved_vector;
    logic [31:0] saved_scratch;
    integer saved_ram_writes;
    integer saved_csr_writes;

    cpu_core dut (
        .clk (clk),
        .rst (rst),
        .timer_irq (timer_irq),
        .instr (instr),
        .pc (pc),
        .mem_addr (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_rdata (mem_rdata),
        .mem_we (mem_we),
        .mem_wstrb (mem_wstrb)
    );

    initial begin
        forever #5 clk = ~clk;
    end

    always_comb begin
        instr = pc < 32'd1024 ? imem[pc[9:2]] : NOP;
        mem_rdata = mem_addr < 32'd64 ? dmem[mem_addr[5:2]] : 32'b0;
    end

    // Observe real writes, so a premature or repeated store is visible.
    always @(posedge clk) begin
        if (!rst && mem_we) begin
            if (mem_addr >= 32'd64 || mem_addr[1:0] != 2'b00)
                $fatal(1, "%s: invalid RAM write %08x", scenario, mem_addr);
            for (integer lane = 0; lane < 4; lane++) begin
                if (mem_wstrb[lane])
                    dmem[mem_addr[5:2]][lane*8 +: 8] <= mem_wdata[lane*8 +: 8];
            end
            ram_writes <= ram_writes + 1;
        end
        if (!rst && dut.csr_we)
            csr_writes <= csr_writes + 1;
    end

    function automatic logic [31:0] enc_i(
        input logic [6:0] opcode,
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [11:0] immediate
    );
        return {immediate, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] addi(
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [11:0] immediate
    );
        return enc_i(7'h13, rd, rs1, 3'b000, immediate);
    endfunction

    function automatic logic [31:0] csr(
        input logic [11:0] address,
        input logic [2:0] command,
        input logic [4:0] rs1,
        input logic [4:0] rd
    );
        return {address, rs1, command, rd, 7'h73};
    endfunction

    function automatic logic [31:0] sw(input logic [11:0] offset);
        return {offset[11:5], 5'd6, 5'd0, 3'b010, offset[4:0], 7'h23};
    endfunction

    task automatic check32(
        input string name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        if (actual !== expected)
            $fatal(1, "%s / %s: got=%08x expected=%08x pc=%08x instr=%08x",
                   scenario, name, actual, expected, pc, instr);
        checks++;
    endtask

    // Each task begins/ends away from the active edge. Inspect the old
    // instruction before tick(), and the committed state after tick().
    task automatic tick;
        @(posedge clk);
        #1;
        @(negedge clk);
        #1;
    endtask

    task automatic pass_case;
        scenarios++;
        $display("[PASS] %s", scenario);
    endtask

    task automatic boot(input logic global_enable, input logic timer_enable);
        @(negedge clk);
        rst = 1'b1;
        timer_irq = 1'b0;
        ram_writes = 0;
        csr_writes = 0;
        for (integer i = 0; i < 256; i++)
            imem[i] = NOP;
        for (integer i = 0; i < 16; i++)
            dmem[i] = 32'hdead_beef + 32'(i);

        // Configure all architectural state by executing instructions;
        // the bench never forces a CPU register or CSR.
        imem[0]  = addi(5'd1, 5'd0, 12'h200);
        imem[1]  = csr(12'h305, 3'b001, 5'd1, 5'd0);
        imem[2]  = addi(5'd2, 5'd0, 12'h080);
        imem[3]  = csr(12'h304, 3'b001, timer_enable ? 5'd2 : 5'd0, 5'd0);
        imem[4]  = addi(5'd3, 5'd0, 12'h008);
        imem[5]  = addi(5'd5, 5'd0, 12'h007);
        imem[6]  = addi(5'd6, 5'd0, 12'h066);
        imem[7]  = addi(5'd9, 5'd0, 12'h055);
        imem[8]  = csr(12'h340, 3'b001, 5'd9, 5'd0);
        imem[9]  = addi(5'd8, 5'd0, 12'h123);
        imem[10] = csr(12'h343, 3'b001, 5'd8, 5'd0);
        imem[11] = addi(5'd10, 5'd0, 12'h077);
        imem[12] = addi(5'd11, 5'd0, 12'h088);
        imem[13] = addi(5'd12, 5'd0, 12'h300);
        imem[14] = csr(12'h341, 3'b001, 5'd12, 5'd0);
        imem[15] = csr(12'h300, 3'b001, global_enable ? 5'd3 : 5'd0, 5'd0);

        // A minimal handler records one visit and returns without changing
        // mepc. The bench controls the external interrupt level separately.
        imem[VECTOR >> 2] = addi(5'd20, 5'd20, 12'd1);
        imem[(VECTOR >> 2) + 1] = MRET;

        repeat (2) @(posedge clk);
        #1;
        check32("reset PC", pc, 32'b0);
        check32("reset cause", dut.mcause, 32'b0);
        check32("reset timer selection", {31'b0, dut.take_timer_irq}, 32'b0);
        @(negedge clk);
        rst = 1'b0;
        #1;
        for (integer i = 0; i < 16; i++) begin
            check32("no setup trap", {31'b0, dut.trap_enter}, 32'b0);
            tick();
            check32("setup PC", pc, 32'((i + 1) * 4));
        end
        check32("test entry PC", pc, ENTRY);
        check32("initial MIE", dut.mstatus, global_enable ? 32'h8 : 32'b0);
        check32("initial MTIE", dut.mie, timer_enable ? 32'h80 : 32'b0);
        check32("dirty mtval", dut.mtval, 32'h123);
        check32("initial return address", dut.mepc, 32'h300);
    endtask

    task automatic enter_trap(
        input logic [31:0] cause,
        input logic [31:0] tval,
        input logic is_interrupt
    );
        saved_pc = pc;
        saved_status = dut.mstatus;
        saved_mie = dut.mie;
        saved_vector = dut.mtvec;
        saved_scratch = dut.mscratch;
        saved_ram_writes = ram_writes;
        saved_csr_writes = csr_writes;
        for (integer i = 0; i < 32; i++)
            saved_regs[i] = dut.u_regfile.regs[i];
        for (integer i = 0; i < 16; i++)
            saved_ram[i] = dmem[i];

        check32("trap selected", {31'b0, dut.trap_enter}, 32'd1);
        check32("synchronous priority", {31'b0, dut.sync_trap}, {31'b0, !is_interrupt});
        check32("timer selected", {31'b0, dut.take_timer_irq}, {31'b0, is_interrupt});
        check32("MRET excluded", {31'b0, dut.mret_enter}, 32'b0);
        check32("ordinary writes cancelled", {29'b0, dut.rf_we, dut.csr_we, mem_we}, 32'b0);
        check32("trap cause before clock", dut.trap_cause, cause);
        check32("trap value before clock", dut.trap_tval, tval);

        tick();
        check32("Direct trap vector", pc, VECTOR);
        check32("saved PC is unexecuted instruction", dut.mepc, saved_pc);
        check32("saved cause", dut.mcause, cause);
        check32("saved mtval", dut.mtval, tval);
        check32("trap status stack", dut.mstatus,
                (saved_status & ~32'h1888) | ((saved_status & 32'h8) << 4) | 32'h1800);
        check32("mtvec preserved", dut.mtvec, saved_vector);
        check32("mie preserved", dut.mie, saved_mie);
        check32("mscratch preserved", dut.mscratch, saved_scratch);
        check32("no premature RAM write", ram_writes, saved_ram_writes);
        check32("no premature CSR write", csr_writes, saved_csr_writes);
        for (integer i = 0; i < 32; i++)
            check32($sformatf("preserve x%0d", i), dut.u_regfile.regs[i], saved_regs[i]);
        for (integer i = 0; i < 16; i++)
            check32($sformatf("preserve RAM[%0d]", i), dmem[i], saved_ram[i]);
        check32("pending source retained", dut.mip, 32'h80);
        check32("handler IRQ masked", {31'b0, dut.timer_irq_req}, 32'b0);
        check32("handler cannot immediately nest", {31'b0, dut.take_timer_irq}, 32'b0);
        if (is_interrupt)
            irq_entries++;
        else
            sync_entries++;
    endtask

    task automatic return_from_handler(input logic clear_irq);
        logic [31:0] return_pc;
        logic [31:0] cause;
        logic [31:0] tval;
        logic [31:0] visits;
        return_pc = dut.mepc;
        cause = dut.mcause;
        tval = dut.mtval;
        visits = dut.u_regfile.regs[20];
        tick();
        check32("handler visit recorded", dut.u_regfile.regs[20], visits + 32'd1);
        check32("handler reaches MRET", pc, VECTOR + 32'd4);

        timer_irq = !clear_irq;
        #1;
        check32("MRET selected", {31'b0, dut.mret_enter}, 32'd1);
        check32("MRET is not a trap", {31'b0, dut.trap_enter}, 32'b0);
        check32("MRET ordinary writes", {29'b0, dut.rf_we, dut.csr_we, mem_we}, 32'b0);
        tick();
        check32("return to original instruction", pc, return_pc);
        check32("MRET status stack", dut.mstatus, 32'h1888);
        check32("MRET preserves mepc", dut.mepc, return_pc);
        check32("MRET preserves cause", dut.mcause, cause);
        check32("MRET preserves mtval", dut.mtval, tval);
        check32("MRET pending level", dut.mip, clear_irq ? 32'b0 : 32'h80);
        check32("reevaluate IRQ after MRET", {31'b0, dut.take_timer_irq}, {31'b0, !clear_irq});
        returns++;
    endtask

    task automatic test_mask(input integer flags);
        scenario = $sformatf("mask MIE=%0b MTIE=%0b MTIP=%0b", flags[2], flags[1], flags[0]);
        boot(flags[2], flags[1]);
        imem[ENTRY >> 2] = addi(5'd5, 5'd5, 12'd1);
        timer_irq = flags[0];
        #1;
        check32("raw pending visible", dut.mip, flags[0] ? 32'h80 : 32'b0);
        check32("enabled request", {31'b0, dut.timer_irq_req}, flags == 7 ? 32'd1 : 32'b0);
        if (flags == 7) begin
            enter_trap(TIMER_CAUSE, 32'b0, 1'b1);
            return_from_handler(1'b1);
            check32("counter still unexecuted", dut.u_regfile.regs[5], 32'd7);
        end
        else begin
            check32("masked trap absent", {31'b0, dut.trap_enter}, 32'b0);
            check32("masked IRQ absent", {31'b0, dut.take_timer_irq}, 32'b0);
        end
        tick();
        check32("counter executes", dut.u_regfile.regs[5], 32'd8);
        check32("counter next PC", pc, ENTRY + 32'd4);
        tick();
        check32("counter executes once", dut.u_regfile.regs[5], 32'd8);
        pass_case();
    endtask

    task automatic check_replay_effects(
        input integer kind,
        input integer prior_ram_writes,
        input integer prior_csr_writes
    );
        check32("store commits once", ram_writes, prior_ram_writes + (kind == 2 ? 1 : 0));
        check32("CSR commits once", csr_writes, prior_csr_writes + (kind >= 3 && kind <= 6 ? 1 : 0));
        check32("RAM value", dmem[0], kind == 2 ? 32'h66 : 32'hdead_beef);
        case (kind)
            0: check32("ADDI result", dut.u_regfile.regs[5], 32'd8);
            1: check32("LW result", dut.u_regfile.regs[11], 32'hdead_beef);
            3: begin
                check32("CSRRW old value", dut.u_regfile.regs[11], 32'h55);
                check32("CSRRW new value", dut.mscratch, 32'h66);
            end
            4: begin
                check32("CSRRC old status", dut.u_regfile.regs[11], 32'h1888);
                check32("CSRRC disables MIE", dut.mstatus, 32'h1880);
            end
            5: begin
                check32("CSRRC old enables", dut.u_regfile.regs[11], 32'h80);
                check32("CSRRC disables MTIE", dut.mie, 32'b0);
            end
            6: begin
                check32("CSRRW old vector", dut.u_regfile.regs[11], VECTOR);
                check32("CSRRW new vector", dut.mtvec, 32'h300);
            end
            7, 8: check32("jump link", dut.u_regfile.regs[10], ENTRY + 32'd4);
            default: begin end
        endcase
    endtask

    task automatic test_replay(input integer kind);
        logic [31:0] instruction;
        logic [31:0] next_address;
        integer prior_ram_writes;
        integer prior_csr_writes;
        next_address = ENTRY + 32'd4;
        case (kind)
            0: begin scenario = "preempt ADDI"; instruction = addi(5'd5, 5'd5, 12'd1); end
            1: begin scenario = "preempt LW"; instruction = enc_i(7'h03, 5'd11, 5'd0, 3'b010, 12'b0); end
            2: begin scenario = "preempt SW"; instruction = sw(12'b0); end
            3: begin scenario = "preempt CSRRW mscratch"; instruction = csr(12'h340, 3'b001, 5'd6, 5'd11); end
            4: begin scenario = "preempt CSRRC mstatus"; instruction = csr(12'h300, 3'b011, 5'd3, 5'd11); end
            5: begin scenario = "preempt CSRRC mie"; instruction = csr(12'h304, 3'b011, 5'd2, 5'd11); end
            6: begin scenario = "preempt CSRRW mtvec"; instruction = csr(12'h305, 3'b001, 5'd12, 5'd11); end
            7: begin scenario = "preempt JAL"; instruction = 32'h0080_056f; next_address = ENTRY + 32'd8; end
            8: begin scenario = "preempt JALR"; instruction = enc_i(7'h67, 5'd10, 5'd0, 3'b000, 12'h048); next_address = ENTRY + 32'd8; end
            9: begin scenario = "preempt taken BEQ"; instruction = 32'h0000_0463; next_address = ENTRY + 32'd8; end
            default: $fatal(1, "Invalid replay test");
        endcase
        boot(1'b1, 1'b1);
        imem[ENTRY >> 2] = instruction;
        timer_irq = 1'b1;
        #1;
        enter_trap(TIMER_CAUSE, 32'b0, 1'b1);
        return_from_handler(1'b1);
        check32("replay PC", pc, ENTRY);
        prior_ram_writes = ram_writes;
        prior_csr_writes = csr_writes;
        tick();
        check32("replayed control flow", pc, next_address);
        check_replay_effects(kind, prior_ram_writes, prior_csr_writes);
        tick();
        check32("following NOP", pc, next_address + 32'd4);
        check_replay_effects(kind, prior_ram_writes, prior_csr_writes);
        pass_case();
    endtask

    task automatic test_sync_priority(input integer kind);
        logic [31:0] instruction;
        logic [31:0] cause;
        logic [31:0] tval;
        case (kind)
            0: begin scenario = "ECALL beats timer"; instruction = 32'h0000_0073; cause = 32'd11; tval = 32'b0; end
            1: begin scenario = "illegal MUL beats timer"; instruction = 32'h036a_8a33; cause = 32'd2; tval = instruction; end
            2: begin scenario = "illegal short encoding beats timer"; instruction = 32'hdead_0002; cause = 32'd2; tval = 32'h2; end
            3: begin scenario = "illegal CSR beats timer"; instruction = csr(12'h7c0, 3'b001, 5'd6, 5'd11); cause = 32'd2; tval = instruction; end
            4: begin scenario = "misaligned LW beats timer"; instruction = enc_i(7'h03, 5'd11, 5'd0, 3'b010, 12'd1); cause = 32'd4; tval = 32'd1; end
            5: begin scenario = "misaligned SW beats timer"; instruction = sw(12'd2); cause = 32'd6; tval = 32'd2; end
            default: $fatal(1, "Invalid synchronous test");
        endcase
        boot(1'b1, 1'b1);
        imem[ENTRY >> 2] = instruction;
        timer_irq = 1'b1;
        #1;
        check32("timer is eligible", {31'b0, dut.timer_irq_req}, 32'd1);
        enter_trap(cause, tval, 1'b0);
        pass_case();
    endtask

    task automatic test_mret_priority;
        scenario = "timer entry excludes simultaneous MRET";
        boot(1'b1, 1'b1);
        imem[ENTRY >> 2] = MRET;
        timer_irq = 1'b1;
        #1;
        enter_trap(TIMER_CAUSE, 32'b0, 1'b1);
        pass_case();
    endtask

    task automatic test_retrigger;
        scenario = "uncleared level retriggers after MRET";
        boot(1'b1, 1'b1);
        imem[ENTRY >> 2] = addi(5'd5, 5'd5, 12'd1);
        timer_irq = 1'b1;
        #1;
        enter_trap(TIMER_CAUSE, 32'b0, 1'b1);
        return_from_handler(1'b0);
        check32("pending return has not executed ADDI", dut.u_regfile.regs[5], 32'd7);
        enter_trap(TIMER_CAUSE, 32'b0, 1'b1);
        return_from_handler(1'b1);
        check32("two handler visits", dut.u_regfile.regs[20], 32'd2);
        tick();
        check32("ADDI after source cleared", dut.u_regfile.regs[5], 32'd8);
        tick();
        check32("ADDI still executes once", dut.u_regfile.regs[5], 32'd8);
        pass_case();
    endtask

    task automatic test_unmask(input logic global_enable);
        scenario = global_enable ? "reevaluate pending IRQ after enabling MIE" :
                                   "reevaluate pending IRQ after enabling MTIE";
        boot(!global_enable, global_enable);
        imem[ENTRY >> 2] = global_enable ? csr(12'h300, 3'b001, 5'd3, 5'd0) :
                                                          csr(12'h304, 3'b001, 5'd2, 5'd0);
        imem[(ENTRY >> 2) + 1] = addi(5'd5, 5'd5, 12'd1);
        timer_irq = 1'b1;
        #1;
        check32("enable instruction not interrupted", {31'b0, dut.trap_enter}, 32'b0);
        check32("enable write allowed", {31'b0, dut.csr_we}, 32'd1);
        tick();
        check32("enable instruction committed", pc, ENTRY + 32'd4);
        check32("pending IRQ reevaluated", {31'b0, dut.take_timer_irq}, 32'd1);
        enter_trap(TIMER_CAUSE, 32'b0, 1'b1);
        return_from_handler(1'b1);
        tick();
        check32("instruction after enabling resumes", dut.u_regfile.regs[5], 32'd8);
        tick();
        check32("instruction after enabling executes once", dut.u_regfile.regs[5], 32'd8);
        pass_case();
    endtask

    task automatic test_withdraw;
        scenario = "withdrawn IRQ is not latched";
        boot(1'b1, 1'b1);
        imem[ENTRY >> 2] = addi(5'd5, 5'd5, 12'd1);
        timer_irq = 1'b1;
        #1;
        check32("level initially eligible", {31'b0, dut.take_timer_irq}, 32'd1);
        timer_irq = 1'b0;
        #1;
        check32("withdrawn level cancels entry", {31'b0, dut.trap_enter}, 32'b0);
        tick();
        check32("normal instruction completes", dut.u_regfile.regs[5], 32'd8);
        check32("normal next PC", pc, ENTRY + 32'd4);
        check32("no handler visits", dut.u_regfile.regs[20], 32'b0);
        check32("mepc unchanged", dut.mepc, 32'h300);
        check32("mcause unchanged", dut.mcause, 32'b0);
        check32("mtval unchanged", dut.mtval, 32'h123);
        pass_case();
    endtask

    initial begin
        $dumpfile("build/cpu_timer_irq/cpu_timer_irq.vcd");
        $dumpvars(0, tb_cpu_timer_irq);
        for (integer flags = 0; flags < 8; flags++)
            test_mask(flags);
        for (integer kind = 0; kind < 10; kind++)
            test_replay(kind);
        for (integer kind = 0; kind < 6; kind++)
            test_sync_priority(kind);
        test_mret_priority();
        test_retrigger();
        test_unmask(1'b1);
        test_unmask(1'b0);
        test_withdraw();
        check32("scenario count", scenarios, 32'd29);
        check32("timer entry count", irq_entries, 32'd16);
        check32("synchronous entry count", sync_entries, 32'd6);
        check32("MRET count", returns, 32'd15);
        $display("[PASS] %0d scenarios, %0d checks, %0d timer entries, %0d synchronous entries, %0d returns",
                 scenarios, checks, irq_entries, sync_entries, returns);
        $display("==============================");
        $display(" M9.3.2 CPU TIMER IRQ PASS");
        $display("==============================");
        $finish;
    end

    initial begin
        #50000;
        $fatal(1, "CPU timer IRQ timeout: %s pc=%08x", scenario, pc);
    end

endmodule
