`timescale 1ns / 1ps

module tb_memory_unit;
  reg clk = 0;
  reg [31:0] pc = 0;
  wire [31:0] instr;
  reg re = 0;
  reg [31:0] raddr = 0;
  wire [31:0] rdata;
  reg we = 0;
  reg [31:0] waddr = 0;
  reg [31:0] wdata = 0;
  reg [3:0] wstrb = 0;

  instr_mem u_imem(.clk(clk), .pc(pc), .instr(instr));
  data_mem  u_dmem(.clk(clk), .re(re), .raddr(raddr), .rdata(rdata), .we(we), .waddr(waddr), .wdata(wdata), .wstrb(wstrb));

  always #5 clk = ~clk;
  task step; begin @(posedge clk); #1; end endtask

  initial begin
    // Override memory contents for deterministic unit test
    u_imem.imem[0] = 32'h1234_5678;
    u_imem.imem[1] = 32'h89AB_CDEF;
    u_dmem.dmem[0] = 32'h0000_0000;

    pc = 0;
    step;
    if (instr !== 32'h1234_5678) begin
      $display("TB_MEMORY_UNIT FAIL: IMEM word0 incorrect");
      $fatal(1);
    end

    pc = 32'd4;
    step;
    if (instr !== 32'h89AB_CDEF) begin
      $display("TB_MEMORY_UNIT FAIL: IMEM word1 incorrect");
      $fatal(1);
    end

    // Full write
    we = 1; waddr = 0; wdata = 32'hAABB_CCDD; wstrb = 4'b1111; re = 0;
    step;
    we = 0; re = 1; raddr = 0;
    step;
    if (rdata !== 32'hAABB_CCDD) begin
      $display("TB_MEMORY_UNIT FAIL: DMEM full write/read incorrect");
      $fatal(1);
    end

    // Byte write
    re = 0; we = 1; waddr = 0; wdata = 32'h0000_0011; wstrb = 4'b0001;
    step;
    we = 0; re = 1; raddr = 0;
    step;
    if (rdata !== 32'hAABB_CC11) begin
      $display("TB_MEMORY_UNIT FAIL: DMEM byte write incorrect");
      $fatal(1);
    end

    // Same-cycle RAW forwarding
    we = 1; re = 1; waddr = 4; raddr = 4; wdata = 32'h1122_3344; wstrb = 4'b1111;
    step;
    if (rdata !== 32'h1122_3344) begin
      $display("TB_MEMORY_UNIT FAIL: DMEM RAW forwarding incorrect");
      $fatal(1);
    end

    $display("TB_MEMORY_UNIT PASS");
    $finish;
  end
endmodule
