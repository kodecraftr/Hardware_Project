`timescale 1ns / 1ps

module tb_div_module_unit;
  reg clk = 0;
  reg reset = 0;
  reg start = 0;
  reg is_signed = 0;
  reg is_rem = 0;
  reg [31:0] dividend = 0;
  reg [31:0] divisor = 0;
  wire ready;
  wire [31:0] result;

  multi_cycle_divider dut (
    .clk(clk), .reset(reset), .start(start), .is_signed(is_signed), .is_rem(is_rem),
    .dividend(dividend), .divisor(divisor), .ready(ready), .result(result)
  );

  always #5 clk = ~clk;
  task step; begin @(posedge clk); #1; end endtask
  task run_case(input [31:0] a, input [31:0] b, input sgn, input rem_mode);
    begin
      dividend = a; divisor = b; is_signed = sgn; is_rem = rem_mode; start = 1;
      step;
      repeat (35) step;
    end
  endtask

  initial begin
    step;
    reset = 1;

    run_case(32'd20, 32'd3, 1'b0, 1'b0);
    if (!ready || result !== 32'd6) begin
      $display("TB_DIV_MODULE_UNIT FAIL: 20/3 incorrect");
      $fatal(1);
    end
    start = 0; step;

    run_case(32'd20, 32'd3, 1'b0, 1'b1);
    if (!ready || result !== 32'd2) begin
      $display("TB_DIV_MODULE_UNIT FAIL: 20%%3 incorrect");
      $fatal(1);
    end
    start = 0; step;

    run_case(-32'sd20, 32'd3, 1'b1, 1'b0);
    if (!ready || $signed(result) !== -32'sd6) begin
      $display("TB_DIV_MODULE_UNIT FAIL: -20/3 incorrect");
      $fatal(1);
    end
    start = 0; step;

    run_case(-32'sd20, 32'd3, 1'b1, 1'b1);
    if (!ready || $signed(result) !== -32'sd2) begin
      $display("TB_DIV_MODULE_UNIT FAIL: -20%%3 incorrect");
      $fatal(1);
    end
    start = 0; step;

    run_case(32'd25, 32'd0, 1'b0, 1'b0);
    if (!ready || result !== 32'hFFFF_FFFF) begin
      $display("TB_DIV_MODULE_UNIT FAIL: divide by zero quotient incorrect");
      $fatal(1);
    end
    start = 0; step;

    run_case(32'd25, 32'd0, 1'b0, 1'b1);
    if (!ready || result !== 32'd25) begin
      $display("TB_DIV_MODULE_UNIT FAIL: divide by zero remainder incorrect");
      $fatal(1);
    end

    $display("TB_DIV_MODULE_UNIT PASS");
    $finish;
  end
endmodule
