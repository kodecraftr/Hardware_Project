`timescale 1ns / 1ps

module tb_pipeline_diag;

  localparam integer MAX_CYCLES = 10000;

  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg uart_rx = 1'b1;
  wire uart_tx;
  wire [3:0] dbg_leds;

  integer cycle = 0;

  soc_top #(
      .HALT_ON_ZERO(1'b1)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .uart_rx(uart_rx),
      .uart_tx(uart_tx),
      .dbg_leds(dbg_leds)
  );

  always #5 clk = ~clk;

  // -------------------------
  // Instruction Encoders
  // -------------------------
  function automatic [31:0] enc_i;
    input integer imm, rs1, funct3, rd, opcode;
    reg [11:0] imm12;
    begin
      imm12 = imm[11:0];
      enc_i = {imm12, rs1[4:0], funct3[2:0], rd[4:0], opcode[6:0]};
    end
  endfunction

  function automatic [31:0] enc_r;
    input integer funct7, rs2, rs1, funct3, rd, opcode;
    begin
      enc_r = {funct7[6:0], rs2[4:0], rs1[4:0], funct3[2:0], rd[4:0], opcode[6:0]};
    end
  endfunction

  function automatic [31:0] enc_s;
    input integer imm, rs2, rs1, funct3, opcode;
    reg [11:0] imm12;
    begin
      imm12 = imm[11:0];
      enc_s = {imm12[11:5], rs2[4:0], rs1[4:0], funct3[2:0], imm12[4:0], opcode[6:0]};
    end
  endfunction

  function automatic [31:0] enc_b;
    input integer imm, rs2, rs1, funct3, opcode;
    reg [12:0] imm13;
    begin
      imm13 = imm[12:0];
      enc_b = {
        imm13[12], imm13[10:5], rs2[4:0], rs1[4:0], funct3[2:0],
        imm13[4:1], imm13[11], opcode[6:0]
      };
    end
  endfunction

  // -------------------------
  // Register checker
  // -------------------------
  task automatic expect_reg;
    input integer reg_idx;
    input [31:0] expected;
    begin
      if (dut.cpu.regs[reg_idx] !== expected) begin
        $display("FAIL: x%0d expected %0d got %0d",
                 reg_idx, expected, dut.cpu.regs[reg_idx]);
        $fatal(1);
      end
    end
  endtask

  // -------------------------
  // Program Initialization
  // -------------------------
  task automatic init_program;
    integer i;
    begin
      for (i = 0; i < 1024; i = i + 1) begin
        dut.u_imem.imem[i] = 32'h0000_0013; // nop
        dut.u_dmem.dmem[i] = 32'h0000_0000;
      end

      // Base pointer
      dut.u_imem.imem[0] = 32'h20000A37; // lui x20,0x20000

      // ALU Operations
      dut.u_imem.imem[1] = enc_i(5, 0, 3'b000, 1, 7'b0010011); // x1=5
      dut.u_imem.imem[2] = enc_i(7, 0, 3'b000, 2, 7'b0010011); // x2=7
      dut.u_imem.imem[3] = enc_r(0, 2, 1, 3'b000, 3, 7'b0110011); // x3=12
      dut.u_imem.imem[4] = enc_i(1, 3, 3'b000, 4, 7'b0010011); // x4=13

      // Store / Load
      dut.u_imem.imem[5] = enc_s(0, 4, 20, 3'b010, 7'b0100011); // sw
      dut.u_imem.imem[6] = enc_i(0, 20, 3'b010, 5, 7'b0000011); // lw
      dut.u_imem.imem[7] = enc_i(2, 5, 3'b000, 6, 7'b0010011); // x6=15

      // Branch test
      dut.u_imem.imem[8]  = enc_i(15, 0, 3'b000, 7, 7'b0010011); // x7=15
      dut.u_imem.imem[9]  = enc_b(8, 7, 6, 3'b000, 7'b1100011); // beq
      dut.u_imem.imem[10] = enc_i(1, 0, 3'b000, 8, 7'b0010011); // flushed
      dut.u_imem.imem[11] = enc_i(9, 0, 3'b000, 9, 7'b0010011); // x9=9

      // Stop
      dut.u_imem.imem[12] = 32'h00000000;
    end
  endtask

  initial begin
    init_program();
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
  end

  always @(posedge clk) begin
    cycle <= cycle + 1;

    $display("cy=%0d pc=%08x instr=%08x x3=%0d x4=%0d x5=%0d x6=%0d",
              cycle, dut.cpu.fetch_pc, dut.cpu.instruction,
              dut.cpu.regs[3], dut.cpu.regs[4],
              dut.cpu.regs[5], dut.cpu.regs[6]);

    if (cycle > MAX_CYCLES) begin
      $display("FAIL: Timeout");
      $fatal(1);
    end
  end

  initial begin
    wait (rst_n);
    wait (dut.cpu.program_done);
    repeat (5) @(posedge clk);

    expect_reg(3, 12);
    expect_reg(4, 13);
    expect_reg(5, 13);
    expect_reg(6, 15);
    expect_reg(8, 0);
    expect_reg(9, 9);

    if (dut.u_dmem.dmem[0] !== 13) begin
      $display("FAIL: Memory mismatch");
      $fatal(1);
    end

    $display("TB_PIPELINE_DIAG DAY1 PASS");
    $finish;
  end

endmodule