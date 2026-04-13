`timescale 1ns / 1ps

module tb_if_id_unit;
  reg clk = 0;
  reg reset = 0;
  reg stall = 0;
  wire exception;
  reg inst_mem_is_valid = 0;
  reg [31:0] inst_mem_read_data = 0;
  reg stall_read_i = 0;
  reg bubble_id_ex_i = 0;
  reg flush_i = 0;
  reg [31:0] inst_fetch_pc = 32'h0;
  reg [31:0] instruction_i = 32'h0;
  reg wb_stall = 0;
  reg wb_alu_to_reg = 0;
  reg wb_mem_to_reg = 0;
  reg [4:0] wb_dest_reg_sel = 0;
  reg [31:0] wb_result = 0;
  reg [31:0] wb_read_data = 0;
  reg [1:0] inst_mem_offset = 2'b00;
  wire [31:0] execute_immediate_w;
  wire immediate_sel_w, alu_w, lui_w, jal_w, jalr_w, branch_w, mem_write_w, mem_to_reg_w;
  wire arithsubtype_w;
  wire [31:0] pc_w;
  wire [4:0] src1_select_w, src2_select_w, dest_reg_sel_w;
  wire [2:0] alu_operation_w;
  wire illegal_inst_w, is_m_ext_w;
  wire [31:0] instruction_o;

  IF_ID dut (
    .clk(clk), .reset(reset), .stall(stall), .exception(exception),
    .inst_mem_is_valid(inst_mem_is_valid), .inst_mem_read_data(inst_mem_read_data),
    .stall_read_i(stall_read_i), .bubble_id_ex_i(bubble_id_ex_i), .flush_i(flush_i),
    .inst_fetch_pc(inst_fetch_pc), .instruction_i(instruction_i),
    .wb_stall(wb_stall), .wb_alu_to_reg(wb_alu_to_reg), .wb_mem_to_reg(wb_mem_to_reg),
    .wb_dest_reg_sel(wb_dest_reg_sel), .wb_result(wb_result), .wb_read_data(wb_read_data),
    .inst_mem_offset(inst_mem_offset),
    .execute_immediate_w(execute_immediate_w), .immediate_sel_w(immediate_sel_w), .alu_w(alu_w),
    .lui_w(lui_w), .jal_w(jal_w), .jalr_w(jalr_w), .branch_w(branch_w), .mem_write_w(mem_write_w),
    .mem_to_reg_w(mem_to_reg_w), .arithsubtype_w(arithsubtype_w), .pc_w(pc_w),
    .src1_select_w(src1_select_w), .src2_select_w(src2_select_w), .dest_reg_sel_w(dest_reg_sel_w),
    .alu_operation_w(alu_operation_w), .illegal_inst_w(illegal_inst_w), .is_m_ext_w(is_m_ext_w),
    .instruction_o(instruction_o)
  );

  always #5 clk = ~clk;

  task step;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  initial begin
    // reset
    step;
    if (instruction_o !== 32'h0000_0013) begin
      $display("TB_IF_ID_UNIT FAIL: reset did not output NOP");
      $fatal(1);
    end

    reset = 1;

    // ADDI x3, x2, 5
    inst_mem_is_valid = 1;
    inst_mem_read_data = 32'h00510193;
    inst_fetch_pc = 32'h0000_0010;
    step;
    step;
    if (alu_w !== 1 || immediate_sel_w !== 1 || dest_reg_sel_w !== 5'd3 ||
        src1_select_w !== 5'd2 || execute_immediate_w !== 32'd5 || alu_operation_w !== 3'b000) begin
      $display("TB_IF_ID_UNIT FAIL: ADDI decode incorrect");
      $fatal(1);
    end

    // STORE word
    inst_mem_read_data = 32'h00b12023; // sw x11,0(x2)
    inst_fetch_pc = 32'h0000_0014;
    step;
    step;
    if (mem_write_w !== 1 || execute_immediate_w !== 32'd0 || src1_select_w !== 5'd2 || src2_select_w !== 5'd11) begin
      $display("TB_IF_ID_UNIT FAIL: STORE decode incorrect");
      $fatal(1);
    end

    // JAL
    inst_mem_read_data = 32'h008000ef;
    inst_fetch_pc = 32'h0000_0018;
    step;
    step;
    if (jal_w !== 1 || dest_reg_sel_w !== 5'd1) begin
      $display("TB_IF_ID_UNIT FAIL: JAL decode incorrect");
      $fatal(1);
    end

    // MUL x3,x4,x5
    inst_mem_read_data = 32'h025201b3;
    inst_fetch_pc = 32'h0000_001c;
    step;
    step;
    if (!alu_w || !is_m_ext_w || dest_reg_sel_w !== 5'd3 || src1_select_w !== 5'd4 || src2_select_w !== 5'd5) begin
      $display("TB_IF_ID_UNIT FAIL: MUL decode incorrect");
      $fatal(1);
    end

    // Bubble injects NOP controls
    bubble_id_ex_i = 1;
    inst_mem_read_data = 32'h00510193;
    step;
    bubble_id_ex_i = 0;
    if (alu_w !== 0 || mem_write_w !== 0 || branch_w !== 0 || dest_reg_sel_w !== 0) begin
      $display("TB_IF_ID_UNIT FAIL: bubble did not clear ID/EX outputs");
      $fatal(1);
    end

    // Misaligned fetch raises exception
    inst_mem_offset = 2'b01;
    step;
    if (!exception) begin
      $display("TB_IF_ID_UNIT FAIL: misaligned fetch did not raise exception");
      $fatal(1);
    end

    $display("TB_IF_ID_UNIT PASS");
    $finish;
  end
endmodule
