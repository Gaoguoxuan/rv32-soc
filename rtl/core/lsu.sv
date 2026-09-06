module lsu(
    input  logic [31:0] addr,
    input  logic [31:0] store_data,
    input  logic [31:0] mem_rdata,

    input  logic [2:0]  load_type,
    input  logic [1:0]  store_type,

    output logic [31:0] load_data,

    output logic [31:0] mem_wdata,
    output logic [3:0]  mem_wstrb,

    output logic        misaligned

);

    // ==============================
    // Load types
    // ==============================

    localparam logic [2:0] LD_NONE = 3'b000;
    localparam logic [2:0] LD_B    = 3'b001;
    localparam logic [2:0] LD_H    = 3'b010;
    localparam logic [2:0] LD_W    = 3'b011;
    localparam logic [2:0] LD_BU   = 3'b100;
    localparam logic [2:0] LD_HU   = 3'b101;

    // ==============================
    // Store types
    // ==============================

    localparam logic [1:0] ST_NONE = 2'b00;
    localparam logic [1:0] ST_B    = 2'b01;
    localparam logic [1:0] ST_H    = 2'b10;
    localparam logic [1:0] ST_W    = 2'b11;

    logic [7:0]  selected_byte;
    logic [15:0] selected_half;

    always_comb begin

        // ==========================
        // Select byte
        // ==========================

        case (addr[1:0])

            2'b00:
                selected_byte = mem_rdata[7:0];
            2'b01:
                selected_byte = mem_rdata[15:8];
            2'b10:
                selected_byte = mem_rdata[23:16];
            2'b11:
                selected_byte = mem_rdata[31:24];
        endcase

        // ==========================
        // Select halfword
        // ==========================

        if (addr[1] == 1'b0)
            selected_half = mem_rdata[15:0];
        else
            selected_half = mem_rdata[31:16];

        // ==========================
        // Defaults
        // ==========================
   
        load_data = 32'b0;

        mem_wdata = 32'b0;
        mem_wstrb = 4'b0000;

        misaligned = 1'b0;

        // ==========================
        // LOAD
        // ==========================

        case (load_type) 

            LD_B: begin
                load_data = {{24{selected_byte[7]}}, selected_byte};
            end

            LD_BU: begin
                load_data = {24'b0, selected_byte};
            end

            LD_H: begin
                if (addr[0] != 1'b0)
                    misaligned = 1'b1;
                else
                    load_data = {{16{selected_half[15]}}, selected_half};
            end

            LD_HU: begin
                if (addr[0] != 1'b0)
                    misaligned = 1'b1;
                else
                    load_data = {16'b0, selected_half};
            end

            LD_W: begin
                if (addr[1:0] != 2'b00)
                    misaligned = 1'b1;
                else
                    load_data = mem_rdata;
            end

            default: begin
                load_data = 32'b0;
            end
        endcase

        // ==========================
        // STORE
        // ==========================

        case (store_type)
        
            ST_B: begin
                case (addr[1:0])
                    
                    2'b00: begin
                        mem_wstrb = 4'b0001;
                        mem_wdata = {24'b0, store_data[7:0]};    
                    end

                    2'b01: begin
                        mem_wstrb = 4'b0010;
                        mem_wdata = {16'b0, store_data[7:0], 8'b0};
                    end

                    2'b10: begin
                        mem_wstrb = 4'b0100;
                        mem_wdata = {8'b0, store_data[7:0], 16'b0};
                    end

                    2'b11: begin
                        mem_wstrb = 4'b1000;
                        mem_wdata = {store_data[7:0], 24'b0};
                    end
                endcase
            end

            ST_H: begin
                if (addr[0] != 1'b0) begin
                    misaligned = 1'b1;
                end
                else if (addr[1] == 1'b0) begin
                    mem_wstrb = 4'b0011;
                    mem_wdata = {16'b0, store_data[15:0]};
                end
                else begin
                    mem_wstrb = 4'b1100;
                    mem_wdata = {store_data[15:0], 16'b0};
                end
            end

            ST_W: begin
                if (addr[1:0] != 2'b00) begin
                    misaligned = 1'b1;
                end
                else begin
                    mem_wstrb = 4'b1111;
                    mem_wdata = store_data;
                end
            end

            default: begin
            end

        endcase

        if (misaligned) mem_wstrb = 4'b0000;
    end

endmodule
