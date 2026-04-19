`timescale 1ns / 1ps

module tb_execute_unit;
  reg clk = 0;
  reg reset = 0;
  reg [31:0] reg_rdata1 = 0, reg_rdata2 = 0, execute_imm = 0, pc = 0, fetch_pc = 0;
  reg immediate_sel = 0, mem_write = 0, jal = 0, jalr = 0, lui = 0, alu = 0, branch = 0, arithsubtype = 0, mem_to_reg = 0, stall_read = 0;
  reg [4:0] dest_reg_sel = 0;
  reg [2:0] alu_op = 0;
  reg [1:0] dmem_raddr = 0;
  reg is_m_ext = 0;
  wire mul_stall, div_stall;
  wire [31:0] alu_operand1, alu_operand2, write_address, wb_result, wb_store_address, wb_store_data;
  wire [31:0] next_pc;
  wire branch_taken;
  wire wb_mem_write, wb_alu_to_reg, wb_mem_to_reg;
  wire [4:0] wb_dest_reg_sel;
  wire [1:0] wb_read_address;
  wire [2:0] mem_alu_operation;
  wire mext_done;
  wire [2:0] mext_func3;
  wire [31:0] mext_operand1, mext_operand2, mext_result, mext_pc;
  wire [4:0] mext_rd;
  wire [7:0] mext_unit_cycles;

  execute dut (
    .clk(clk), .reset(reset), .reg_rdata1(reg_rdata1), .reg_rdata2(reg_rdata2),
    .execute_imm(execute_imm), .pc(pc), .fetch_pc(fetch_pc), .immediate_sel(immediate_sel),
    .mem_write(mem_write), .jal(jal), .jalr(jalr), .lui(lui), .alu(alu), .branch(branch),
    .arithsubtype(arithsubtype), .mem_to_reg(mem_to_reg), .stall_read(stall_read),
    .dest_reg_sel(dest_reg_sel), .alu_op(alu_op), .dmem_raddr(dmem_raddr), .is_m_ext(is_m_ext),
    .mul_stall(mul_stall), .div_stall(div_stall), .alu_operand1(alu_operand1), .alu_operand2(alu_operand2),
    .write_address(write_address), .next_pc(next_pc), .branch_taken(branch_taken),
    .wb_result(wb_result), .wb_mem_write(wb_mem_write), .wb_alu_to_reg(wb_alu_to_reg),
    .wb_dest_reg_sel(wb_dest_reg_sel), .wb_mem_to_reg(wb_mem_to_reg),
    .wb_store_address(wb_store_address), .wb_store_data(wb_store_data), .wb_read_address(wb_read_address),
    .mem_alu_operation(mem_alu_operation), .mext_done(mext_done), .mext_func3(mext_func3),
    .mext_operand1(mext_operand1), .mext_operand2(mext_operand2), .mext_result(mext_result),
    .mext_pc(mext_pc), .mext_rd(mext_rd), .mext_unit_cycles(mext_unit_cycles)
  );

  always #5 clk = ~clk;
  task step; begin @(posedge clk); #1; end endtask

  initial begin
    step;
    reset = 1;

    // ADD
    reg_rdata1 = 10; reg_rdata2 = 7; alu = 1; alu_op = 3'b000; arithsubtype = 0; pc = 32'h20; fetch_pc = 32'h20; dest_reg_sel = 5'd9;
    step;
    if (wb_result !== 32'd17 || wb_dest_reg_sel !== 5'd9 || !wb_alu_to_reg) begin
      $display("TB_EXECUTE_UNIT FAIL: ADD path incorrect");
      $fatal(1);
    end

    // SUB
    arithsubtype = 1;
    step;
    if (wb_result !== 32'd3) begin
      $display("TB_EXECUTE_UNIT FAIL: SUB path incorrect");
      $fatal(1);
    end

    // JAL
    alu = 0; arithsubtype = 0; jal = 1; execute_imm = 32'd16; pc = 32'h40; fetch_pc = 32'h40;
    step;
    if (!branch_taken || next_pc !== 32'h50 || wb_result !== 32'h44) begin
      $display("TB_EXECUTE_UNIT FAIL: JAL path incorrect");
      $fatal(1);
    end

    // JALR
    jal = 0; jalr = 1; reg_rdata1 = 32'h1003; execute_imm = 32'd5; pc = 32'h80; fetch_pc = 32'h80;
    step;
    if (!branch_taken || next_pc !== 32'h1008) begin
      $display("TB_EXECUTE_UNIT FAIL: JALR target incorrect");
      $fatal(1);
    end

    // BEQ taken
    jalr = 0; branch = 1; alu_op = 3'b000; reg_rdata1 = 32'd9; reg_rdata2 = 32'd9; execute_imm = 32'd8; pc = 32'h100; fetch_pc = 32'h100;
    step;
    if (!branch_taken || next_pc !== 32'h108) begin
      $display("TB_EXECUTE_UNIT FAIL: BEQ path incorrect");
      $fatal(1);
    end

    // Store path
    branch = 0; mem_write = 1; reg_rdata1 = 32'h2000_0010; reg_rdata2 = 32'hA5A5_1234; execute_imm = 32'd4; alu_op = 3'b010;
    step;
    if (!wb_mem_write || wb_store_address !== 32'h2000_0014 || wb_store_data !== 32'hA5A5_1234) begin
      $display("TB_EXECUTE_UNIT FAIL: store forwarding incorrect");
      $fatal(1);
    end

    $display("TB_EXECUTE_UNIT PASS");
    $finish;
  end
endmodule
