`timescale 1ns / 1ps

module top_fpga #(
    parameter IMEMSIZE = 4096,
    parameter DMEMSIZE = 4096
) (
    input wire clk,  // fast board clock (e.g. 100 MHz)
    input wire reset,  // FIXED: active-high reset
    output [15:0] led
);

  // wire [15:0] pc_disp = pipe_u.inst_fetch_pc[15:0];
  wire [31:0] current_pc;  // FIXED: Connect to external output pin
  wire [15:0] pc_disp = current_pc[15:0];

  wire        exception;

  ////////////////////////////////////////////////////////////
  // Clock divider
  ////////////////////////////////////////////////////////////
  parameter DIVISOR = 100_000_000;
  reg [26:0] clk_cnt;
  reg        slow_clk;

  always @(posedge clk) begin
    if (reset) begin
      clk_cnt  <= 0;
      slow_clk <= 1'b0;
    end else if (clk_cnt == DIVISOR - 1) begin
      clk_cnt  <= 0;
      slow_clk <= ~slow_clk;
    end else begin
      clk_cnt <= clk_cnt + 1;
    end
  end


  ////////////////////////////////////////////////////////////
  // PIPE ↔ MEMORY WIRES
  ////////////////////////////////////////////////////////////
  wire [31:0] inst_mem_read_data;
  wire        inst_mem_is_valid;

  wire [31:0] dmem_read_data;
  wire        dmem_write_valid;
  wire        dmem_read_valid;

  // FIXED: Added missing wires to connect pipe to memory
  wire [31:0] inst_mem_address;
  wire        inst_mem_is_ready;
  wire [31:0] dmem_read_address;
  wire        dmem_read_ready;
  wire [31:0] dmem_write_address;
  wire        dmem_write_ready;
  wire [31:0] dmem_write_data;
  wire [ 3:0] dmem_write_byte;

  assign inst_mem_is_valid = 1'b1;
  assign dmem_write_valid = 1'b1;
  assign dmem_read_valid = 1'b1;
  assign led = pc_disp;

  ////////////////////////////////////////////////////////////
  // PIPELINE CPU
  ////////////////////////////////////////////////////////////
  pipe pipe_u (
      .clk(slow_clk),  // FIXED: Switched to slow clock for visual observation
      .reset(~reset),
      .stall(1'b0),
      .exception(exception),
      .pc_out(current_pc),  // FIXED: See above
      .inst_mem_address(inst_mem_address),  // FIXED: Connected port
      .inst_mem_is_valid(inst_mem_is_valid),
      .inst_mem_read_data(inst_mem_read_data),
      .inst_mem_is_ready(inst_mem_is_ready),  // FIXED: Connected port

      .dmem_read_address(dmem_read_address),  // FIXED: Connected port
      .dmem_read_ready(dmem_read_ready),  // FIXED: Connected port
      .dmem_read_data_temp(dmem_read_data),
      .dmem_read_valid(dmem_read_valid),
      .dmem_write_address(dmem_write_address),  // FIXED: Connected port
      .dmem_write_ready(dmem_write_ready),  // FIXED: Connected port
      .dmem_write_data(dmem_write_data),  // FIXED: Connected port
      .dmem_write_byte(dmem_write_byte),  // FIXED: Connected port
      .dmem_write_valid(dmem_write_valid)
  );


  ////////////////////////////////////////////////////////////
  // INSTRUCTION MEMORY
  ////////////////////////////////////////////////////////////
  instr_mem IMEM (
      .clk(slow_clk),  // FIXED: Connect to slow_clk
      .pc(inst_mem_address),  // FIXED: Connected inst_mem_address
      .instr(inst_mem_read_data)
  );


  ////////////////////////////////////////////////////////////
  // DATA MEMORY
  ////////////////////////////////////////////////////////////
  data_mem DMEM (
      .clk(slow_clk),  // FIXED: Connect to slow_clk

      .re(dmem_read_ready),  // FIXED: Connected dmem_read_ready
      .raddr(dmem_read_address),  // FIXED: Connected dmem_read_address
      .rdata(dmem_read_data),

      .we(dmem_write_ready),  // FIXED: Connected dmem_write_ready
      .waddr(dmem_write_address),  // FIXED: Connected dmem_write_address
      .wdata(dmem_write_data),  // FIXED: Connected dmem_write_data
      .wstrb(dmem_write_byte)  // FIXED: Connected dmem_write_byte
  );



endmodule
