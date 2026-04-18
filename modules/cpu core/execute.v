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
	input     	immediate_sel,
	input     	mem_write,
	input     	jal,
	input     	jalr,
	input     	lui,
	input     	alu,
	input     	branch,
	input     	arithsubtype,
	input     	mem_to_reg,
	input     	stall_read,

	input  [4:0]  dest_reg_sel,
	input  [2:0]  alu_op,
	input  [1:0]  dmem_raddr,
	input         is_m_ext,          // <-- ADD THIS LINE

	// -----------------------------	// FROM WB	// -----------------------------

	// -----------------------------	// EX → PIPE	// -----------------------------
	output        mul_stall,         // <--- ADD THIS BRAND NEW LINE
	output        div_stall,         // <--- ADD THIS LINE
	output [31:0] alu_operand1,
	output [31:0] alu_operand2,
	output [31:0] write_address,

	output reg [31:0] next_pc,
	output reg    	branch_taken,

	// -----------------------------  // EX → WB	// -----------------------------
	output [31:0] wb_result,
	output    	wb_mem_write,
	output    	wb_alu_to_reg,
	output [4:0]  wb_dest_reg_sel,
	output    	wb_mem_to_reg,
	output [31:0] wb_store_address,
	output [31:0] wb_store_data,
	output [1:0]  wb_read_address,
	output [2:0]  mem_alu_operation,

	// -----------------------------  // EX → UART monitor // -----------------------------
	output reg     mext_done,
	output reg [2:0]  mext_func3,
	output reg [31:0] mext_operand1,
	output reg [31:0] mext_operand2,
	output reg [31:0] mext_result,
	output reg [31:0] mext_pc,
	output reg [4:0]  mext_rd,
	output reg [7:0]  mext_unit_cycles
);

//////////////// Including OPCODES ////////////////////////////
`include "opcode.vh"

////////////////////////////////////////////////////////////// LOCAL INTERNAL SIGNALS/////////////////////////////////

reg  [31:0] ex_result;
wire [32:0] ex_result_subs;
wire [32:0] ex_result_subu;

////////////////////////////////////////////////////////////// Operand selection///////////////////////////////////////////////////////

// TODO-EX-1:
// Select ALU operands
// - The first operand must come from the first value read from the register file
// - The second operand must come from the immediate when immediate selection is enabled
// - Otherwise, the second operand must come from the second value read from the register file

assign alu_operand1 = reg_rdata1;
assign alu_operand2 = immediate_sel ? execute_imm : reg_rdata2;

////////////////////////////////////////////////////////////// Subtractions////////////////////////////////////////////////////////////


// TODO-EX-2:
// Generate subtraction results required for branch comparison
// - One result (ex_result_subs) must treat both operands as signed values
// - Another result (ex_result_subu) must treat both operands as unsigned values
// - The results must be wide enough to capture the sign/borrow bit
// - These results will be used later to evaluate branch conditions

assign ex_result_subs =
	{alu_operand1[31], alu_operand1} -
	{alu_operand2[31], alu_operand2};

assign ex_result_subu = {1'b0, alu_operand1} - {1'b0, alu_operand2};

////////////////////////////////////////////////////////////// Address & branch stall////////////////////////////////////////

assign write_address = alu_operand1 + execute_imm;

////////////////////////////////////////////////////////////// Next PC logic////////////////////////////////////////////////////////////


// TODO-EX-3:
// Compute the next program counter and branch decision
// Guidelines:
// - Default next PC advances to the next sequential instruction
// - For jump instructions:
// 	* JAL computes the target using the current PC and an immediate
// 	* JALR computes the target using a register value (first read) and an immediate
// - For branch instructions:
// 	* Evaluate the branch condition using comparison/subtraction results
// 	* If the condition is satisfied, jump to the branch target
// 	* Otherwise, continue sequential execution
// - Branch resolution must be suppressed when a branch stall is active

always @(*) begin
	next_pc  	= fetch_pc + 4;
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
        	next_pc  	= fetch_pc + 4;
        	branch_taken = 1'b0;
    	end
	endcase
end

////////////////////////////////////////////////////////////// ALU result logic////////////////////////////////////////////////////////////

// TODO-EX-4:
// Generate the execute-stage result (ex_result)
// Guidelines:
// - For store instructions, forward the value that will be written to memory
// - For jump instructions (JAL/JALR), produce the return address (PC + 4)
// - LUI must place the immediate value directly into the destination register
// - For ALU instructions, compute the result based on the decoded ALU operation
// - The arithmetic subtype signal selects between related operations

//////////////////////////////////////////////////////////////
// Radix-4 Multiplier Instance
//////////////////////////////////////////////////////////////
wire        mul_start;
wire        mul_ready;
wire [63:0] mul_product;
reg         mul_started;
reg         mul_done;
reg [31:0]  mul_pc_active;
reg [4:0]   mul_rd_active;
reg [2:0]   mul_func3_active;

// Start multiplying if it's an ALU instruction, FUNC3 is 000 (ADD/MUL mapping), M-ext is active, and we aren't done.
wire is_mul_inst = alu && (alu_op == ADD) && is_m_ext;
wire new_mul_inst =
    is_mul_inst &&
    ((pc != mul_pc_active) || (dest_reg_sel != mul_rd_active) || (alu_op != mul_func3_active));

assign mul_start = is_mul_inst && (!mul_started || new_mul_inst) && (!mul_done || new_mul_inst);

// Stall the pipeline while multiplication is running
assign mul_stall = is_mul_inst && (!mul_done || new_mul_inst);

booth_radix4_multiplier u_radix4_mul (
    .clk           (clk),
    .reset         (reset),
    .start         (mul_start),
    .ready         (mul_ready),
    .multiplicand_M(alu_operand1),
    .multiplier_Q  (alu_operand2),
    .product       (mul_product)
);
// =========================================================================

// =========================================================================
// Multi-Cycle Divider Logic & Instance
// =========================================================================
wire        div_start;
wire        div_ready;
wire [31:0] div_result;
reg         mul_ready_d;
reg         div_ready_d;
reg         div_started;
reg         div_done;
reg [31:0]  div_pc_active;
reg [4:0]   div_rd_active;
reg [2:0]   div_func3_active;

// FUNC3 decoding for division:
// 100 = DIV, 101 = DIVU, 110 = REM, 111 = REMU
wire is_div_inst = alu && is_m_ext && (alu_op[2] == 1'b1); 
wire is_signed   = (alu_op == 3'b100) || (alu_op == 3'b110);
wire is_rem      = (alu_op == 3'b110) || (alu_op == 3'b111);
wire new_div_inst =
    is_div_inst &&
    ((pc != div_pc_active) || (dest_reg_sel != div_rd_active) || (alu_op != div_func3_active));

assign div_start = is_div_inst && (!div_started || new_div_inst) && (!div_done || new_div_inst);
assign div_stall = is_div_inst && (!div_done || new_div_inst);

multi_cycle_divider u_divider (
    .clk       (clk),
    .reset     (reset),
    .start     (div_start),
    .is_signed (is_signed),
    .is_rem    (is_rem),
    .dividend  (alu_operand1),
    .divisor   (alu_operand2),
    .ready     (div_ready),
    .result    (div_result)
);

always @(posedge clk or negedge reset) begin
    if (!reset) begin
        mul_started      <= 1'b0;
        mul_done         <= 1'b0;
        mul_pc_active    <= 32'd0;
        mul_rd_active    <= 5'd0;
        mul_func3_active <= 3'd0;
        div_started      <= 1'b0;
        div_done         <= 1'b0;
        div_pc_active    <= 32'd0;
        div_rd_active    <= 5'd0;
        div_func3_active <= 3'd0;
        mul_ready_d      <= 1'b0;
        div_ready_d      <= 1'b0;
        mext_done        <= 1'b0;
        mext_func3       <= 3'b000;
        mext_operand1    <= 32'd0;
        mext_operand2    <= 32'd0;
        mext_result      <= 32'd0;
        mext_pc          <= 32'd0;
        mext_rd          <= 5'd0;
        mext_unit_cycles <= 8'd0;
    end else begin
        if (!is_mul_inst) begin
            mul_started <= 1'b0;
            mul_done    <= 1'b0;
            mul_pc_active <= 32'd0;
            mul_rd_active <= 5'd0;
            mul_func3_active <= 3'd0;
        end else begin
            if (new_mul_inst) begin
                mul_started <= 1'b1;
                mul_done    <= 1'b0;
                mul_pc_active <= pc;
                mul_rd_active <= dest_reg_sel;
                mul_func3_active <= alu_op;
            end else if (!mul_started) begin
                mul_started <= 1'b1;
                mul_pc_active <= pc;
                mul_rd_active <= dest_reg_sel;
                mul_func3_active <= alu_op;
            end
            if (mul_ready)
                mul_done <= 1'b1;
        end

        if (!is_div_inst) begin
            div_started <= 1'b0;
            div_done    <= 1'b0;
            div_pc_active <= 32'd0;
            div_rd_active <= 5'd0;
            div_func3_active <= 3'd0;
        end else begin
            if (new_div_inst) begin
                div_started <= 1'b1;
                div_done    <= 1'b0;
                div_pc_active <= pc;
                div_rd_active <= dest_reg_sel;
                div_func3_active <= alu_op;
            end else if (!div_started) begin
                div_started <= 1'b1;
                div_pc_active <= pc;
                div_rd_active <= dest_reg_sel;
                div_func3_active <= alu_op;
            end
            if (div_ready)
                div_done <= 1'b1;
        end

        mul_ready_d <= mul_ready;
        div_ready_d <= div_ready;
        mext_done   <= 1'b0;

        if ((is_mul_inst && mul_ready && !mul_ready_d) ||
            (is_div_inst && div_ready && !div_ready_d)) begin
            mext_done        <= 1'b1;
            mext_func3       <= alu_op;
            mext_operand1    <= alu_operand1;
            mext_operand2    <= alu_operand2;
            mext_result      <= is_div_inst ? div_result : mul_product[31:0];
            mext_pc          <= pc;
            mext_rd          <= dest_reg_sel;
            mext_unit_cycles <= is_div_inst ? 8'd32 : 8'd16;
        end
    end
end

always @(*) begin
	case (1'b1)
    	mem_write: ex_result = alu_operand2;
    	jal,
    	jalr:  	ex_result = pc + 4;
    	lui:   	ex_result = execute_imm;

    	alu: begin
        // 1. Check for M-extension operations FIRST
        if (is_m_ext) begin
            if (is_div_inst) begin
                ex_result = div_result;        // DIV, DIVU, REM, REMU
            end else begin
                ex_result = mul_product[31:0]; // MUL
            end
        end 
        // 2. Otherwise, route standard ALU operations
        else begin
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
    end

    	default: ex_result = 'hx;
	endcase
end


////////////////////////////////////////////////////////////// EX → WB pipeline register/////////////////////////////////////////

ex_mem_wb_reg u_ex_mem_wb (
	.clk        	(clk),
	.reset_n    	(reset),
	.stall_n    	(~stall_read),

	.ex_result  	(ex_result),
	.store_address  (write_address),
	.store_data     (alu_operand2),

	.mem_write  	(mem_write),
	.alu_to_reg 	(alu | lui | jal |
                  	jalr | mem_to_reg),
	.dest_reg_sel   (dest_reg_sel),
	.mem_to_reg 	(mem_to_reg),
	.read_address   (dmem_raddr),
	.alu_operation  (alu_op),

	.ex_mem_result    	(wb_result),
	.ex_mem_mem_write 	(wb_mem_write),
	.ex_mem_alu_to_reg	(wb_alu_to_reg),
	.ex_mem_dest_reg_sel  (wb_dest_reg_sel),
	.ex_mem_mem_to_reg	(wb_mem_to_reg),
	.ex_mem_store_address(wb_store_address),
	.ex_mem_store_data   (wb_store_data),
	.ex_mem_read_address  (wb_read_address),
	.ex_mem_alu_operation (mem_alu_operation)
);

endmodule


module ex_mem_wb_reg (
	input     	clk,
	input     	reset_n,
	input     	stall_n,

	// Data
	input  [31:0] ex_result,
	input  [31:0] store_address,
	input  [31:0] store_data,

	// Control inputs from EX/MEM
	input     	mem_write,
	input     	alu_to_reg,
	input  [4:0]  dest_reg_sel,
	input     	mem_to_reg,
	input  [1:0]  read_address,
	input  [2:0]  alu_operation,

	// Outputs to WB
	output reg [31:0] ex_mem_result,
	output reg    	ex_mem_mem_write,
	output reg    	ex_mem_alu_to_reg,
	output reg [4:0]  ex_mem_dest_reg_sel,
	output reg    	ex_mem_mem_to_reg,
	output reg [31:0] ex_mem_store_address,
	output reg [31:0] ex_mem_store_data,
	output reg [1:0]  ex_mem_read_address,
	output reg [2:0]  ex_mem_alu_operation
);

// TODO-EX-5:
// EX/MEM → WB pipeline register
// Guidelines:
// - Store all execute-stage data and control signals on the rising clock edge
// - On reset, clear all stored values to a safe default
// - When a stall is asserted, prevent unintended updates
// - All outputs must hold their previous values unless explicitly updated

always @(posedge clk or negedge reset_n) begin
	if (!reset_n) begin
    	ex_mem_result     	<= 32'h0;
    	ex_mem_mem_write  	<= 1'b0;
    	ex_mem_alu_to_reg 	<= 1'b0;
    	ex_mem_dest_reg_sel   <= 5'h0;
    	ex_mem_mem_to_reg 	<= 1'b0;
    	ex_mem_store_address <= 32'h0;
    	ex_mem_store_data    <= 32'h0;
    	ex_mem_read_address   <= 2'h0;
    	ex_mem_alu_operation  <= 3'h0;
	end
    else if (stall_n) begin
    	ex_mem_result     	<= ex_result;// TODO-EX-5
    	ex_mem_mem_write  	<= mem_write;// TODO-EX-5
    	ex_mem_alu_to_reg 	<= alu_to_reg;// TODO-EX-5
    	ex_mem_dest_reg_sel   <= dest_reg_sel;// TODO-EX-5
    	ex_mem_mem_to_reg 	<= mem_to_reg;// TODO-EX-5
    	ex_mem_store_address <= store_address;
    	ex_mem_store_data    <= store_data;
    	ex_mem_read_address   <= read_address;// TODO-EX-5
    	ex_mem_alu_operation  <= alu_operation;// TODO-EX-5
	end
end

endmodule
