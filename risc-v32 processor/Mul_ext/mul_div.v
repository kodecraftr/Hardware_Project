`timescale 1ns/1ps

module mul_div (
    input clk,
    input reset_n,
    input start,
    input [2:0] funct3,
    input [31:0] a,
    input [31:0] b,
    output reg [31:0] result,
    output reg busy
);

    // RISC-V M-Extension Funct3 Mapping
    localparam MUL    = 3'b000, 
               DIV    = 3'b100, DIVU   = 3'b101,
               REM    = 3'b110, REMU   = 3'b111;

    reg [5:0]  count;
    reg [31:0] op_a, op_b;
    reg [63:0] temp_rem;
    reg        res_sign, rem_sign;
    
    // 33-bit wires for proper absolute value conversion of 0x80000000
    wire [32:0] abs_a = ((funct3 == DIV || funct3 == REM) && a[31]) ? 
                        (33'h0 - {1'b0, a}) : {1'b0, a};
    wire [32:0] abs_b = ((funct3 == DIV || funct3 == REM) && b[31]) ? 
                        (33'h0 - {1'b0, b}) : {1'b0, b};

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            busy <= 0;
            result <= 0;
            count <= 0;
        end else begin
            if (start && !busy) begin
                busy <= 1;
                count <= 0;
                
                case (funct3)
                    MUL: result <= a * b; // Inferred DSP slice
                    
                    DIV, DIVU, REM, REMU: begin
                        // Handle Sign Logic for Signed Ops
                        res_sign <= (funct3 == DIV || funct3 == REM) ? (a[31] ^ b[31]) : 1'b0;
                        rem_sign <= (funct3 == DIV || funct3 == REM) ? a[31] : 1'b0;
                        
                        // Convert to Absolute Values using 33-bit math to correctly handle 0x80000000
                        // This avoids the negative overflow bug where -0x80000000 = 0x80000000 in 32-bit
                        op_a <= abs_a[31:0];
                        op_b <= abs_b[31:0];
                        
                        // Initial state for Division
                        temp_rem <= {32'b0, abs_a[31:0]};
                    end
                endcase
            end else if (busy) begin
                if (funct3 == MUL) begin
                    busy <= 0;
                end else if (b == 0) begin // Divide by zero case
                    busy <= 0;
                    result <= (funct3[1]) ? a : 32'hFFFFFFFF; 
                end else if (count < 32) begin
                    // Standard Shift-and-Subtract (Restoring)
                    if ({temp_rem[62:0], 1'b0} >= {op_b, 32'b0}) begin
                        temp_rem <= ({temp_rem[62:0], 1'b0} - {op_b, 32'b0}) | 64'b1;
                    end else begin
                        temp_rem <= {temp_rem[62:0], 1'b0};
                    end
                    count <= count + 1;
                end else begin
                    busy <= 0;
                    // Final Sign Correction
                    if (funct3 == DIV || funct3 == DIVU)
                        result <= res_sign ? -temp_rem[31:0] : temp_rem[31:0];
                    else
                        result <= rem_sign ? -temp_rem[63:32] : temp_rem[63:32];
                end
            end
        end
    end
endmodule