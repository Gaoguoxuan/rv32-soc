module simple_rom #(
    parameter integer WORDS = 1024,
    parameter string  HEX_FILE = ""
)(
    // Instruction fetch port
    input  logic [31:0] instr_addr,
    output logic [31:0] instr_data,

    // Data read port
    input  logic [31:0] data_addr,
    output logic [31:0] data_rdata
);

    localparam integer ADDR_BITS = $clog2(WORDS);

    logic [31:0] mem [0:WORDS-1];

    integer i;


    // ============================================================
    // ROM initialization
    // ============================================================

    initial begin

        // Fill unused ROM with RISC-V NOP:
        //
        // addi x0, x0, 0
        //
        // machine code = 0x00000013

        for (i = 0; i < WORDS; i = i + 1)
            mem[i] = 32'h00000013;


        if (HEX_FILE != "") begin

            $display(
                "[ROM] Loading program: %s",
                HEX_FILE
            );

            $readmemh(
                HEX_FILE,
                mem
            );

        end

    end


    // ============================================================
    // Instruction read port
    // ============================================================

    always_comb begin

        if (instr_addr < (WORDS * 4))
            instr_data = mem[instr_addr[ADDR_BITS+1:2]];
        else
            instr_data = 32'h00000013;

    end


    // ============================================================
    // Data read port
    // ============================================================

    always_comb begin

        if (data_addr < (WORDS * 4))
            data_rdata = mem[data_addr[ADDR_BITS+1:2]];
        else
            data_rdata = 32'b0;

    end

endmodule