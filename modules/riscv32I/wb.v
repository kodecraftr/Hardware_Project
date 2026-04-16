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
    output inst_mem_is_ready_o,
    output wb_stall_o,
    output reg [31:0] wb_write_address_o,
    output reg [31:0] wb_write_data_o,
    output reg [3:0] wb_write_byte_o,
    output reg [31:0] wb_read_data_o,
    output reg [31:0] inst_fetch_pc_o,
    output reg wb_stall_first_o,
    output reg wb_stall_second_o
);

  // import "opcode.vh" for OPCODES
  `include "opcode.vh"


  ////////////////////////////////////////////////////////////
  // assigning these variables to read from the instruction memory
  ////////////////////////////////////////////////////////////

  assign inst_mem_address_o  = fetch_pc_i;
  assign inst_mem_is_ready_o = !fetch_pause_i && !stall_read_i;

  ////////////////////////////////////////////////////////////
  // No WB-generated branch stalls. Control hazards are handled by EX-stage flush.
  ////////////////////////////////////////////////////////////

  assign wb_stall_o = 1'b0;

  ////////////////////////////////////////////////////////////
  // instruction fetch pc update
  ////////////////////////////////////////////////////////////

  // Drive instruction memory address using the current fetch PC
  // Instruction fetch must be disabled when a read stall is asserted

  always @(posedge clk or negedge reset) begin
    if (!reset) inst_fetch_pc_o <= RESET;  // reset to instruction fetch program counter
    else if (!stall_read_i) inst_fetch_pc_o <= fetch_pc_i;  // fetch the next instruction
  end

  ////////////////////////////////////////////////////////////
  always @(posedge clk or negedge reset) begin
    if (!reset) begin
      wb_stall_first_o  <= 1'b0;
      wb_stall_second_o <= 1'b0;
    end else begin
      wb_stall_first_o  <= 1'b0;
      wb_stall_second_o <= 1'b0;
    end
  end

  ////////////////////////////////////////////////////////////
  // Preparing write data for store type instructions
  ////////////////////////////////////////////////////////////

  // Prepare data memory write signals for store instructions
  // - Generate write address
  // - Generate write data with proper byte replication
  // - Generate byte-enable signals based on address alignment

  always @* begin
    wb_write_address_o = wb_store_address_i;
    wb_write_byte_o    = 4'h0;
    wb_write_data_o    = 32'h0;

    case (wb_alu_operation_i)

      // TODO-WB: Store Byte (SB)
      SB: begin
        wb_write_data_o = {4{wb_store_data_i[7:0]}};
        case (wb_store_address_i[1:0])
          2'b00:   wb_write_byte_o = 4'b0001;
          2'b01:   wb_write_byte_o = 4'b0010;
          2'b10:   wb_write_byte_o = 4'b0100;
          default: wb_write_byte_o = 4'b1000;
        endcase
      end
      // TODO-WB: Store Halfword (SH)
      SH: begin
        wb_write_data_o = {2{wb_store_data_i[15:0]}};
        wb_write_byte_o = wb_store_address_i[1] ? 4'b1100 : 4'b0011;
      end
      SW: begin
        wb_write_data_o = wb_store_data_i;
        wb_write_byte_o = 4'b1111;
      end
      default: begin
        wb_write_data_o = 32'h0;
        wb_write_byte_o = 4'h0;
      end
    endcase
  end

  ////////////////////////////////////////////////////////////
  // load instruction based on the OPCODES
  ////////////////////////////////////////////////////////////

  // Format load data based on load type
  // - Apply sign-extension or zero-extension
  // - Select correct byte or halfword using read address bits


  always @* begin
    case (wb_alu_operation_i)
      LB: begin  // Load byte
        case (wb_read_address_i)
          2'b00: wb_read_data_o = {{24{dmem_read_data_i[7]}}, dmem_read_data_i[7:0]};
          2'b01: wb_read_data_o = {{24{dmem_read_data_i[15]}}, dmem_read_data_i[15:8]};
          2'b10: wb_read_data_o = {{24{dmem_read_data_i[23]}}, dmem_read_data_i[23:16]};
          2'b11: wb_read_data_o = {{24{dmem_read_data_i[31]}}, dmem_read_data_i[31:24]};  // TODO
        endcase
      end

      // load halfword
      LH:
      wb_read_data_o =
            wb_read_address_i[1]
            ? {{16{dmem_read_data_i[31]}}, dmem_read_data_i[31:16]}
            : {{16{dmem_read_data_i[15]}}, dmem_read_data_i[15:0]};

      LW: wb_read_data_o = dmem_read_data_i;  // load word

      LBU: begin  // load byte unsigned
        case (wb_read_address_i)
          2'b00: wb_read_data_o = {24'h0, dmem_read_data_i[7:0]};
          2'b01: wb_read_data_o = {24'h0, dmem_read_data_i[15:8]};
          2'b10: wb_read_data_o = {24'h0, dmem_read_data_i[23:16]};
          2'b11: wb_read_data_o = {24'h0, dmem_read_data_i[31:24]};
        endcase
      end

      // load halfword unsigned
      LHU:
      wb_read_data_o =
            wb_read_address_i[1]
            ? {16'h0, dmem_read_data_i[31:16]}
            : {16'h0, dmem_read_data_i[15:0]};

      default: wb_read_data_o = 'hx;
    endcase
  end

endmodule
