`timescale 1ns / 1ps

module wb #(
    parameter [31:0] RESET = 32'h0000_0000
) (
    input clk,
    input reset,

    input        fetch_pause_i,
    input        stall_read_i,
    input [31:0] fetch_pc_i,

    input wb_mem_to_reg_i,
    input wb_mem_write_i,
    input [31:0] wb_store_address_i,
    input [31:0] wb_store_data_i,

    input [2:0] wb_alu_operation_i,
    input [1:0] wb_read_address_i,

    input [31:0] dmem_read_data_i,
    input        dmem_read_valid_i,
    input        dmem_write_valid_i,

    // Outputs
    output [31:0] inst_mem_address_o,
    output        inst_mem_is_ready_o,
    output        wb_stall_o,

    output reg [31:0] wb_write_address_o,
    output reg [31:0] wb_write_data_o,
    output reg [3:0]  wb_write_byte_o,

    output reg [31:0] wb_read_data_o,
    output reg [31:0] inst_fetch_pc_o
);

`include "opcode.vh"

////////////////////////////////////////////////////////////
// Instruction fetch
////////////////////////////////////////////////////////////

assign inst_mem_address_o  = fetch_pc_i;
assign inst_mem_is_ready_o = !fetch_pause_i && !stall_read_i;

// No stall logic yet
assign wb_stall_o = 1'b0;

////////////////////////////////////////////////////////////
// PC register
////////////////////////////////////////////////////////////

always @(posedge clk or negedge reset) begin
    if (!reset)
        inst_fetch_pc_o <= RESET;
    else if (!stall_read_i)
        inst_fetch_pc_o <= fetch_pc_i;
end

////////////////////////////////////////////////////////////
// Basic STORE logic (ONLY SW for now)
////////////////////////////////////////////////////////////

always @(*) begin
    wb_write_address_o = wb_store_address_i;
    wb_write_data_o    = 32'h0;
    wb_write_byte_o    = 4'h0;

    if (wb_mem_write_i) begin
        wb_write_data_o = wb_store_data_i;
        wb_write_byte_o = 4'b1111; // Only full word
    end
end

////////////////////////////////////////////////////////////
// Basic LOAD logic (ONLY LW)
////////////////////////////////////////////////////////////

always @(*) begin
    if (wb_mem_to_reg_i)
        wb_read_data_o = dmem_read_data_i;
    else
        wb_read_data_o = 32'h0;
end

endmodule