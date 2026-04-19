`timescale 1ns / 1ps

module tb_wb_unit;
  reg clk = 0;
  reg reset = 0;
  reg fetch_pause_i = 0;
  reg stall_read_i = 0;
  reg [31:0] fetch_pc_i = 0;
  reg wb_mem_to_reg_i = 0;
  reg wb_mem_write_i = 0;
  reg [31:0] wb_store_address_i = 0;
  reg [31:0] wb_store_data_i = 0;
  reg [2:0] wb_alu_operation_i = 0;
  reg [1:0] wb_read_address_i = 0;
  reg [31:0] dmem_read_data_i = 0;
  reg dmem_read_valid_i = 0;
  reg dmem_write_valid_i = 0;
  wire [31:0] inst_mem_address_o;
  wire inst_mem_is_ready_o;
  wire wb_stall_o;
  wire [31:0] wb_write_address_o, wb_write_data_o, wb_read_data_o, inst_fetch_pc_o;
  wire [3:0] wb_write_byte_o;
  wire wb_stall_first_o, wb_stall_second_o;

  wb dut (
    .clk(clk), .reset(reset), .fetch_pause_i(fetch_pause_i), .stall_read_i(stall_read_i),
    .fetch_pc_i(fetch_pc_i), .wb_mem_to_reg_i(wb_mem_to_reg_i), .wb_mem_write_i(wb_mem_write_i),
    .wb_store_address_i(wb_store_address_i), .wb_store_data_i(wb_store_data_i),
    .wb_alu_operation_i(wb_alu_operation_i), .wb_read_address_i(wb_read_address_i),
    .dmem_read_data_i(dmem_read_data_i), .dmem_read_valid_i(dmem_read_valid_i), .dmem_write_valid_i(dmem_write_valid_i),
    .inst_mem_address_o(inst_mem_address_o), .inst_mem_is_ready_o(inst_mem_is_ready_o), .wb_stall_o(wb_stall_o),
    .wb_write_address_o(wb_write_address_o), .wb_write_data_o(wb_write_data_o), .wb_write_byte_o(wb_write_byte_o),
    .wb_read_data_o(wb_read_data_o), .inst_fetch_pc_o(inst_fetch_pc_o),
    .wb_stall_first_o(wb_stall_first_o), .wb_stall_second_o(wb_stall_second_o)
  );

  always #5 clk = ~clk;
  task step; begin @(posedge clk); #1; end endtask

  initial begin
    step;
    reset = 1;
    fetch_pc_i = 32'h20;
    step;
    if (inst_mem_address_o !== 32'h20 || !inst_mem_is_ready_o || inst_fetch_pc_o !== 32'h20) begin
      $display("TB_WB_UNIT FAIL: fetch side incorrect");
      $fatal(1);
    end

    // SB
    wb_store_address_i = 32'h2000_0002;
    wb_store_data_i = 32'h1122_3344;
    wb_alu_operation_i = 3'b000;
    #1;
    if (wb_write_byte_o !== 4'b0100 || wb_write_data_o !== 32'h4444_4444) begin
      $display("TB_WB_UNIT FAIL: SB formatting incorrect");
      $fatal(1);
    end

    // SH
    wb_store_address_i = 32'h2000_0002;
    wb_store_data_i = 32'h1234_5678;
    wb_alu_operation_i = 3'b001;
    #1;
    if (wb_write_byte_o !== 4'b1100 || wb_write_data_o !== 32'h5678_5678) begin
      $display("TB_WB_UNIT FAIL: SH formatting incorrect");
      $fatal(1);
    end

    // SW
    wb_alu_operation_i = 3'b010;
    #1;
    if (wb_write_byte_o !== 4'b1111 || wb_write_data_o !== 32'h1234_5678) begin
      $display("TB_WB_UNIT FAIL: SW formatting incorrect");
      $fatal(1);
    end

    // Loads
    dmem_read_data_i = 32'h80FF_7F01;
    wb_alu_operation_i = 3'b000; wb_read_address_i = 2'b00; #1; // LB
    if (wb_read_data_o !== 32'h0000_0001) begin
      $display("TB_WB_UNIT FAIL: LB byte0 incorrect");
      $fatal(1);
    end
    wb_read_address_i = 2'b10; #1;
    if (wb_read_data_o !== 32'hFFFF_FFFF) begin
      $display("TB_WB_UNIT FAIL: LB byte2 incorrect");
      $fatal(1);
    end
    wb_alu_operation_i = 3'b001; wb_read_address_i = 2'b00; #1; // LH
    if (wb_read_data_o !== 32'h0000_7F01) begin
      $display("TB_WB_UNIT FAIL: LH low incorrect");
      $fatal(1);
    end
    wb_read_address_i = 2'b10; #1;
    if (wb_read_data_o !== 32'hFFFF_80FF) begin
      $display("TB_WB_UNIT FAIL: LH high incorrect");
      $fatal(1);
    end
    wb_alu_operation_i = 3'b100; wb_read_address_i = 2'b10; #1; // LBU
    if (wb_read_data_o !== 32'h0000_00FF) begin
      $display("TB_WB_UNIT FAIL: LBU incorrect");
      $fatal(1);
    end
    wb_alu_operation_i = 3'b101; wb_read_address_i = 2'b10; #1; // LHU
    if (wb_read_data_o !== 32'h0000_80FF) begin
      $display("TB_WB_UNIT FAIL: LHU incorrect");
      $fatal(1);
    end

    $display("TB_WB_UNIT PASS");
    $finish;
  end
endmodule
