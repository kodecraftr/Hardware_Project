`timescale 1ns / 1ps

module tb_mul_module_unit;
  reg clk = 0;
  reg reset = 0;
  reg start = 0;
  reg [31:0] multiplicand_M = 0;
  reg [31:0] multiplier_Q = 0;
  wire ready;
  wire [63:0] product;

  booth_radix4_multiplier dut (
    .clk(clk), .reset(reset), .start(start), .ready(ready),
    .multiplicand_M(multiplicand_M), .multiplier_Q(multiplier_Q), .product(product)
  );

  always #5 clk = ~clk;
  task step; begin @(posedge clk); #1; end endtask

  initial begin
    step;
    reset = 1;

    multiplicand_M = 32'd7;
    multiplier_Q   = 32'd9;
    start = 1;
    step;
    repeat (17) step;
    if (!ready || product[31:0] !== 32'd63) begin
      $display("TB_MUL_MODULE_UNIT FAIL: 7*9 incorrect");
      $fatal(1);
    end
    start = 0;
    step;

    multiplicand_M = -32'sd3;
    multiplier_Q   = 32'd5;
    start = 1;
    step;
    repeat (17) step;
    if (!ready || $signed(product[31:0]) !== -32'sd15) begin
      $display("TB_MUL_MODULE_UNIT FAIL: -3*5 incorrect");
      $fatal(1);
    end

    $display("TB_MUL_MODULE_UNIT PASS");
    $finish;
  end
endmodule
