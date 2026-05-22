module top_cpu (
    input clk,
    input reset,
    input [31:0] instr,
    output [31:0] result
);

    // --- Vulnerable Program Counter ---
    // Single register: One bit-flip here leads to a critical system crash.
    reg [31:0] pc;

    // Standard PC update logic: Simple increment by 4
    // No alignment enforcement and no jump watchdog protection.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc <= 32'h00000000;
        end else begin
            pc <= pc + 4; 
        end
    end

    // --- Register File ---
    reg [31:0] regfile [0:31];
    wire [4:0] rs1 = instr[19:15];
    wire [4:0] rs2 = instr[24:20];
    wire [4:0] rd  = instr[11:7];
    wire [31:0] rdata1 = regfile[rs1];
    wire [31:0] rdata2 = regfile[rs2];

    // Synchronous write to register file
    always @(posedge clk) begin
        if (rd != 0) begin
            regfile[rd] <= result;
        end
    end

    // --- ALU (Arithmetic Logic Unit) ---
    reg [31:0] alu_out;
    always @(*) begin
        case (instr[14:12])
            3'b000:  alu_out = rdata1 + rdata2;   // ADD
            3'b001:  alu_out = rdata1 - rdata2;   // SUB
            3'b010:  alu_out = rdata1 & rdata2;   // AND
            3'b011:  alu_out = rdata1 | rdata2;   // OR
            3'b100:  alu_out = rdata1 ^ rdata2;   // XOR
            default: alu_out = 32'h00000000;
        endcase
    end

    assign result = alu_out;

endmodule
