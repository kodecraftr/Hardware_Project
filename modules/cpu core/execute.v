`timescale 1ns / 1ps

module execute
#(
	parameter [31:0] RESET = 32'h0000_0000
)
(
	input clk,
	input reset,

	// -----------------------------	// FROM ID/EX	// -----------------------------
	input  [31:0] reg_rdata1,
	input  [31:0] reg_rdata2,
	input  [31:0] execute_imm,
	input  [31:0] pc,
	input  [31:0] fetch_pc,
	input         immediate_sel,
	input         mem_write,
	input         jal,
	input         jalr,
	input         lui,
	input         alu,
	input         branch,
	input         arithsubtype,
	input         mem_to_reg,
	input         stall_read,

	input  [4:0]  dest_reg_sel,
	input  [2:0]  alu_op,
	input  [1:0]  dmem_raddr,

	// -----------------------------	// EX → PIPE	// -----------------------------
	output [31:0] alu_operand1,
	output [31:0] alu_operand2,
	output [31:0] write_address,

	output reg [31:0] next_pc,
	output reg    branch_taken,

	// Temporary output for Stage 1
	output reg [31:0] ex_result
);

//////////////// Including OPCODES ////////////////////////////
`include "opcode.vh"

////////////////////////////////////////////////////////////// LOCAL INTERNAL SIGNALS/////////////////////////////////

wire [32:0] ex_result_subs;
wire [32:0] ex_result_subu;

////////////////////////////////////////////////////////////// Operand selection///////////////////////////////////////////////////////

assign alu_operand1 = reg_rdata1;
assign alu_operand2 = immediate_sel ? execute_imm : reg_rdata2;

////////////////////////////////////////////////////////////// Subtractions////////////////////////////////////////////////////////////

assign ex_result_subs =
	{alu_operand1[31], alu_operand1} -
	{alu_operand2[31], alu_operand2};

assign ex_result_subu = {1'b0, alu_operand1} - {1'b0, alu_operand2};

////////////////////////////////////////////////////////////// Address & branch stall////////////////////////////////////////

assign write_address = alu_operand1 + execute_imm;

////////////////////////////////////////////////////////////// Next PC logic////////////////////////////////////////////////////////////

always @(*) begin
	next_pc      = fetch_pc + 4;
	branch_taken = 1'b0;

	case (1'b1)
    	jal  : begin
            next_pc      = pc + execute_imm;
            branch_taken = 1'b1;
        end
    	jalr : begin
            next_pc      = (alu_operand1 + execute_imm) & 32'hffff_fffe;
            branch_taken = 1'b1;
        end

    	branch: begin
        	case (alu_op)
            	BEQ:  begin
                	if (ex_result_subs == 0) begin
                        next_pc      = pc + execute_imm;
                        branch_taken = 1'b1;
                    end
            	end
            	BNE:  begin
                	if (ex_result_subs != 0) begin
                        next_pc      = pc + execute_imm;
                        branch_taken = 1'b1;
                    end
            	end
            	BLT:  begin
                	if (ex_result_subs[32]) begin
                        next_pc      = pc + execute_imm;
                        branch_taken = 1'b1;
                    end
            	end
            	BGE:  begin
                	if (!ex_result_subs[32]) begin
                        next_pc      = pc + execute_imm;
                        branch_taken = 1'b1;
                    end
            	end
            	BLTU: begin
                	if (ex_result_subu[32]) begin
                        next_pc      = pc + execute_imm;
                        branch_taken = 1'b1;
                    end
            	end
            	BGEU: begin
                	if (!ex_result_subu[32]) begin
                        next_pc      = pc + execute_imm;
                        branch_taken = 1'b1;
                    end
            	end
            	default: begin
                    next_pc      = fetch_pc + 4;
                    branch_taken = 1'b0;
                end
        	endcase
    	end

    	default: begin      
        	next_pc      = fetch_pc + 4;
        	branch_taken = 1'b0;
    	end
	endcase
end

////////////////////////////////////////////////////////////// ALU result logic////////////////////////////////////////////////////////////

always @(*) begin
	case (1'b1)
    	mem_write: ex_result = alu_operand2;
    	jal,
    	jalr:      ex_result = pc + 4;
    	lui:       ex_result = execute_imm;

    	alu: begin
            case (alu_op)
                ADD : ex_result = arithsubtype ? (alu_operand1 - alu_operand2) : (alu_operand1 + alu_operand2);
                SLL : ex_result = alu_operand1 << alu_operand2[4:0];
                SLT : ex_result = ex_result_subs[32];
                SLTU: ex_result = ex_result_subu[32];
                XOR : ex_result = alu_operand1 ^ alu_operand2;
                SR  : ex_result = arithsubtype ? $signed(alu_operand1) >>> alu_operand2[4:0] : alu_operand1 >>> alu_operand2[4:0];
                OR  : ex_result = alu_operand1 | alu_operand2;
                AND : ex_result = alu_operand1 & alu_operand2;
                default: ex_result = 'hx;
            endcase
        end

    	default: ex_result = 'hx;
	endcase
end

endmodule