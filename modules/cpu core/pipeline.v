`timescale 1ns / 1ps

module pipe #(
    parameter [31:0] RESET = 32'h0000_0000,
    parameter        HALT_ON_ZERO = 1'b0
) (
    input          clk,
    input          reset,
    input          imem_stall_i,
    input          dmem_stall_i,
    output         exception,
    output [31:0]  pc_out,
    output [31:0]  inst_mem_address,
    input          inst_mem_is_valid,
    input  [31:0]  inst_mem_read_data,
    output         inst_mem_is_ready,
    output [31:0]  dmem_read_address,
    output         dmem_read_ready,
    input  [31:0]  dmem_read_data_temp,
    input          dmem_read_valid,
    output [31:0]  dmem_write_address,
    output         dmem_write_ready,
    output [31:0]  dmem_write_data,
    output [ 3:0]  dmem_write_byte,
    input          dmem_write_valid,
    output         mext_event_valid,
    output [2:0]   mext_event_func3,
    output [31:0]  mext_event_operand1,
    output [31:0]  mext_event_operand2,
    output [31:0]  mext_event_result,
    output [31:0]  mext_event_pc,
    output [4:0]   mext_event_rd,
    output [7:0]   mext_event_unit_cycles,
    output [31:0]  mext_event_total_cycles
);

  // -- Internal Wire Declarations (Matching your original exactly) --
  wire [31:0] instruction, pc, inst_fetch_pc, execute_immediate, alu_operand1, alu_operand2;
  wire [31:0] reg_rdata1, reg_rdata2, wb_result, wb_read_data, wb_store_address, wb_store_data, wb_write_address, wb_write_data;
  wire [31:0] next_pc, write_address;
  wire [4:0]  src1_select, src2_select, dest_reg_sel, wb_dest_reg_sel, mext_event_rd_w;
  wire [31:0] mext_event_operand1_w, mext_event_operand2_w, mext_event_result_w, mext_event_pc_w;
  wire [2:0]  alu_operation, wb_alu_operation, mext_event_func3_w;
  wire [1:0]  dmem_read_offset, wb_read_address;
  wire [3:0]  wb_write_byte;
  wire [7:0]  mext_event_unit_cycles_w;
  wire        immediate_sel, arithsubtype, mem_write, mem_to_reg, illegal_inst, is_m_ext, alu, lui, jal, jalr, branch;
  wire        wb_stall, mul_stall, div_stall, branch_taken, flush_decode, mext_event_valid_w, wb_alu_to_reg, wb_mem_write, wb_mem_to_reg;
  wire        if_id_hold, load_use_stall, ex_hold, pc_hold;

  reg  [31:0] fetch_pc, cycle_counter;
  reg         program_done;
  reg  [31:0] regs [31:1];

  // 1. IF/ID Stage
  IF_ID IF_ID_stage (
      .clk(clk), .reset(reset), .stall(dmem_stall_i), .exception(exception),
      .inst_mem_is_valid(inst_mem_is_valid), .inst_mem_read_data(inst_mem_read_data),
      .stall_read_i(if_id_hold), .bubble_id_ex_i(load_use_stall | flush_decode), .flush_i(flush_decode),
      .inst_fetch_pc(inst_fetch_pc), .instruction_i(instruction), .wb_stall(wb_stall),
      .wb_alu_to_reg(wb_alu_to_reg), .wb_mem_to_reg(wb_mem_to_reg), .wb_dest_reg_sel(wb_dest_reg_sel),
      .wb_result(wb_result), .wb_read_data(wb_read_data), .inst_mem_offset(inst_mem_address[1:0]),
      .execute_immediate_w(execute_immediate), .immediate_sel_w(immediate_sel), .alu_w(alu),
      .lui_w(lui), .jal_w(jal), .jalr_w(jalr), .branch_w(branch), .mem_write_w(mem_write),
      .mem_to_reg_w(mem_to_reg), .arithsubtype_w(arithsubtype), .pc_w(pc), .src1_select_w(src1_select),
      .src2_select_w(src2_select), .dest_reg_sel_w(dest_reg_sel), .alu_operation_w(alu_operation),
      .illegal_inst_w(illegal_inst), .is_m_ext_w(is_m_ext), .instruction_o(instruction)
  );

  // 2. Execute Stage
  execute execute_unit (
      .clk(clk), .reset(reset), .reg_rdata1(reg_rdata1), .reg_rdata2(reg_rdata2),
      .execute_imm(execute_immediate), .pc(pc), .fetch_pc(fetch_pc), .immediate_sel(immediate_sel),
      .mem_write(mem_write), .jal(jal), .jalr(jalr), .lui(lui), .alu(alu), .branch(branch),
      .arithsubtype(arithsubtype), .mem_to_reg(mem_to_reg), .stall_read(ex_hold), .mul_stall(mul_stall),
      .div_stall(div_stall), .dest_reg_sel(dest_reg_sel), .alu_op(alu_operation), .dmem_raddr(dmem_read_offset),
      .is_m_ext(is_m_ext), .alu_operand1(alu_operand1), .alu_operand2(alu_operand2), .write_address(write_address),
      .next_pc(next_pc), .branch_taken(branch_taken), .wb_result(wb_result), .wb_mem_write(wb_mem_write),
      .wb_alu_to_reg(wb_alu_to_reg), .wb_dest_reg_sel(wb_dest_reg_sel), .wb_mem_to_reg(wb_mem_to_reg),
      .wb_store_address(wb_store_address), .wb_store_data(wb_store_data), .wb_read_address(wb_read_address),
      .mem_alu_operation(wb_alu_operation), .mext_done(mext_event_valid_w), .mext_func3(mext_event_func3_w),
      .mext_operand1(mext_event_operand1_w), .mext_operand2(mext_event_operand2_w), .mext_result(mext_event_result_w),
      .mext_pc(mext_event_pc_w), .mext_rd(mext_event_rd_w), .mext_unit_cycles(mext_event_unit_cycles_w)
  );

  // 3. Write-Back Stage
  wb wb_stage_inst (
      .clk(clk), .reset(reset), .fetch_pause_i(mul_stall | div_stall), .stall_read_i(dmem_stall_i),
      .fetch_pc_i(fetch_pc), .wb_mem_to_reg_i(wb_mem_to_reg), .wb_mem_write_i(wb_mem_write),
      .wb_store_address_i(wb_store_address), .wb_store_data_i(wb_store_data), .wb_alu_operation_i(wb_alu_operation),
      .wb_read_address_i(wb_read_address), .dmem_read_data_i(dmem_read_data_temp), .dmem_read_valid_i(dmem_read_valid),
      .dmem_write_valid_i(dmem_write_valid), .inst_mem_address_o(inst_mem_address), .inst_mem_is_ready_o(inst_mem_is_ready),
      .wb_stall_o(wb_stall), .wb_write_address_o(wb_write_address), .wb_write_data_o(wb_write_data),
      .wb_write_byte_o(wb_write_byte), .wb_read_data_o(wb_read_data), .inst_fetch_pc_o(inst_fetch_pc)
  );

endmodule