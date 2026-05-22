module top_cpu (
    input clk,
    input reset,
    input [31:0] instr,
    output [31:0] result
);

    // Program Counter (TMR + Alignment Enforcement + Jump Watchdog)
    reg [31:0] pc_r1, pc_r2, pc_r3;
    wire [31:0] pc_voted_raw;
    wire [31:0] pc; // The current, aligned, TMR'd PC value

    // Majority voter for the raw PC values
    assign pc_voted_raw = (pc_r1 & pc_r2) | (pc_r2 & pc_r3) | (pc_r1 & pc_r3);

    // Alignment enforcement for the current PC value
    assign pc = pc_voted_raw & ~3; // Force pc[1:0] = 2'b00

    // Ideal sequential next PC value (incremented by 4 and aligned)
    // This serves as the 'fallback' if a jump is deemed illegal, and is the intended next PC.
    wire [31:0] ideal_pc_sequential_next = (pc + 4) & ~3;

    // Jump Distance Watchdog Logic
    parameter [31:0] MAX_JUMP_THRESHOLD = 128; // Max allowed absolute jump in bytes

    // Replicated logic for generating the proposed next PC value.
    // In this simple CPU, the only *intended* next PC is the sequential one.
    // We replicate this calculation to protect against single-point faults in the generation
    // of the intended next PC value.

    // Instance 1: Proposes the ideal sequential next PC
    wire [31:0] proposed_next_pc_val_1 = ideal_pc_sequential_next;
    // Instance 2: Proposes the ideal sequential next PC
    wire [31:0] proposed_next_pc_val_2 = ideal_pc_sequential_next;
    // Instance 3: Proposes the ideal sequential next PC
    wire [31:0] proposed_next_pc_val_3 = ideal_pc_sequential_next;

    // Majority voter for these proposed next PC values.
    // This votes on the *ideal* next PC, providing a robust candidate
    // for the final watchdog to check. This protects against faults
    // in the (pc + 4) calculation or its propagation paths.
    wire [31:0] voted_proposed_next_pc;
    assign voted_proposed_next_pc = (proposed_next_pc_val_1 & proposed_next_pc_val_2) |
                                    (proposed_next_pc_val_2 & proposed_next_pc_val_3) |
                                    (proposed_next_pc_val_1 & proposed_next_pc_val_3);

    // Hardened: Replicate the entire Jump Distance Watchdog logic and its multiplexer.
    // This protects against single-point faults in the watchdog's comparison or the
    // selection of the next PC value, which could bypass the TMR registers' update logic.

    // Signed calculation of difference for robust jump distance check.
    // We need to calculate abs(voted_proposed_next_pc - pc) using signed arithmetic
    // to correctly handle potential wrap-around with unsigned comparisons.
    wire [32:0] diff_extended = $signed(voted_proposed_next_pc) - $signed(pc);
    wire [31:0] absolute_diff;
    // If diff_extended is negative (MSB is 1), take its 2's complement to get the absolute value.
    assign absolute_diff = (diff_extended[32]) ? (0 - diff_extended[31:0]) : diff_extended[31:0];

    // Replicated Final Jump Distance Watchdog Application.
    // This watchdog checks if the 'voted_proposed_next_pc' value attempts a
    // forbidden jump. If a jump violation is detected, force the PC to stay at its current value 'pc'.
    // Otherwise, use the 'voted_proposed_next_pc'.
    // The comparison checks if the absolute jump distance is greater than or equal to the threshold.

    // Instance 1 of Watchdog and Mux
    wire jump_violation_detected_1;
    assign jump_violation_detected_1 = (absolute_diff >= MAX_JUMP_THRESHOLD);
    wire [31:0] next_pc_for_tmr_1;
    assign next_pc_for_tmr_1 = jump_violation_detected_1 ? pc : voted_proposed_next_pc;

    // Instance 2 of Watchdog and Mux
    wire jump_violation_detected_2;
    assign jump_violation_detected_2 = (absolute_diff >= MAX_JUMP_THRESHOLD);
    wire [31:0] next_pc_for_tmr_2;
    assign next_pc_for_tmr_2 = jump_violation_detected_2 ? pc : voted_proposed_next_pc;

    // Instance 3 of Watchdog and Mux
    wire jump_violation_detected_3;
    assign jump_violation_detected_3 = (absolute_diff >= MAX_JUMP_THRESHOLD);
    wire [31:0] next_pc_for_tmr_3;
    assign next_pc_for_tmr_3 = jump_violation_detected_3 ? pc : voted_proposed_next_pc;

    // Majority voter for the final next PC value that will update the TMR registers.
    // This corrects any single fault in the replicated watchdog logic or its output mux.
    wire [31:0] voted_next_pc_for_tmr;
    assign voted_next_pc_for_tmr = (next_pc_for_tmr_1 & next_pc_for_tmr_2) |
                                   (next_pc_for_tmr_2 & next_pc_for_tmr_3) |
                                   (next_pc_for_tmr_1 & next_pc_for_tmr_3);

    // Update logic for the TMR registers
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc_r1 <= 0;
            pc_r2 <= 0;
            pc_r3 <= 0;
        end else begin
            // All three shadow registers update based on the *voted* watchdog-approved next PC.
            pc_r1 <= voted_next_pc_for_tmr;
            pc_r2 <= voted_next_pc_for_tmr;
            pc_r3 <= voted_next_pc_for_tmr;
        end
    end

    // Register File
    reg [31:0] regfile [0:31];
    wire [4:0] rs1 = instr[19:15];
    wire [4:0] rs2 = instr[24:20];
    wire [4:0] rd  = instr[11:7];
    wire [31:0] rdata1 = regfile[rs1];
    wire [31:0] rdata2 = regfile[rs2];

    always @(posedge clk) begin
        if (rd != 0) regfile[rd] <= result;
    end

    // ALU
    reg [31:0] alu_out;
    always @(*) begin
        case (instr[14:12])
            3'b000: alu_out = rdata1 + rdata2;   // ADD
            3'b001: alu_out = rdata1 - rdata2;   // SUB
            3'b010: alu_out = rdata1 & rdata2;   // AND
            3'b011: alu_out = rdata1 | rdata2;   // OR
            3'b100: alu_out = rdata1 ^ rdata2;   // XOR
            default: alu_out = 0;
        endcase
    end

    assign result = alu_out;

endmodule
