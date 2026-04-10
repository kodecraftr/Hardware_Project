`timescale 1ns / 1ps

module tb_pipeline;

////////////////////////////////////////////////////////////
// CLOCK & RESET
////////////////////////////////////////////////////////////
reg clk;
reg reset;

// 100 MHz clock
initial begin
	clk = 0;
	forever #5 clk = ~clk;
end

// reset (active low in our CPU)
initial begin
	reset = 0;
	#100;
	reset = 1;
end

initial begin
    $dumpfile("pipeline.vcd"); // Name of the file to create
    $dumpvars(0, tb_pipeline);  // 0 means dump all signals in 'tb_pipeline' and below
end


////////////////////////////////////////////////////////////
// PIPE ↔ MEMORY SIGNALS
////////////////////////////////////////////////////////////
wire [31:0] inst_mem_read_data;
wire    	inst_mem_is_valid;

wire [31:0] dmem_read_data;
wire    	dmem_write_valid;
wire    	dmem_read_valid;

// FIXED: Added missing wires to connect DUT to memory in testbench
wire [31:0] inst_mem_address;
wire        inst_mem_is_ready;
wire [31:0] dmem_read_address;
wire        dmem_read_ready;
wire [31:0] dmem_write_address;
wire        dmem_write_ready;
wire [31:0] dmem_write_data;
wire [3:0]  dmem_write_byte;
wire [31:0] pc_out;

assign inst_mem_is_valid = 1'b1;
assign dmem_write_valid  = 1'b1;
assign dmem_read_valid   = 1'b1;

wire exception;


////////////////////////////////////////////////////////////
// DUT : PIPELINE CPU
////////////////////////////////////////////////////////////
pipe DUT (
	.clk(clk),
	.reset(reset),
	.stall(1'b0),
	.exception(exception),
	.pc_out(pc_out), // FIXED

	.inst_mem_address(inst_mem_address), // FIXED: Connected port
	.inst_mem_is_valid(inst_mem_is_valid),
	.inst_mem_read_data(inst_mem_read_data),
	.inst_mem_is_ready(inst_mem_is_ready), // FIXED: Connected port

	.dmem_read_address(dmem_read_address), // FIXED: Connected port
	.dmem_read_ready(dmem_read_ready), // FIXED: Connected port
	.dmem_read_data_temp(dmem_read_data),
	.dmem_read_valid(dmem_read_valid),
	.dmem_write_address(dmem_write_address), // FIXED: Connected port
	.dmem_write_ready(dmem_write_ready), // FIXED: Connected port
	.dmem_write_data(dmem_write_data), // FIXED: Connected port
	.dmem_write_byte(dmem_write_byte), // FIXED: Connected port
	.dmem_write_valid(dmem_write_valid)
);


////////////////////////////////////////////////////////////
// INSTRUCTION MEMORY  (matches instr_mem.v)
////////////////////////////////////////////////////////////
instr_mem IMEM (
	.clk(clk),
	.pc(inst_mem_address), // FIXED: Connected inst_mem_address
	.instr(inst_mem_read_data)
);


////////////////////////////////////////////////////////////
// DATA MEMORY  (matches data_mem.v)
////////////////////////////////////////////////////////////
data_mem DMEM (
	.clk(clk),

	.re(dmem_read_ready), // FIXED: Connected dmem_read_ready
	.raddr(dmem_read_address), // FIXED: Connected dmem_read_address
	.rdata(dmem_read_data),
	

	.we(dmem_write_ready), // FIXED: Connected dmem_write_ready
	.waddr(dmem_write_address), // FIXED: Connected dmem_write_address
	.wdata(dmem_write_data), // FIXED: Connected dmem_write_data
	.wstrb(dmem_write_byte) // FIXED: Connected dmem_write_byte
);


////////////////////////////////////////////////////////////
// SIMULATION TIME
////////////////////////////////////////////////////////////


always @(posedge clk) begin
    // 1. Print 'result' when a store instruction writes to memory 
    // (This captures the array swaps and variable updates in code_sort.c)
    if (dmem_write_ready) begin
        $display("time: %21d ,result = %10d", $time, dmem_write_data);
    end

    // 2. Check for program completion (when the pipeline halts or jumps to 0)
    if (DUT.execute.next_pc == 32'h00000000) begin
        $display("All instructions are Fetched");
        $display("next_pc = 00000000");
        $finish;
    end else begin
        // 3. Continuously print the internal next_pc
        $display("next_pc = %08x", DUT.execute.next_pc);
    end
end

endmodule
