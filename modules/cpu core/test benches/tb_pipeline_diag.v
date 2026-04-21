`timescale 1ns / 1ps

module tb_pipeline_diag;

  localparam integer MAX_CYCLES = 30000;

  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg uart_rx = 1'b1;
  wire uart_tx;
  wire [3:0] dbg_leds;

  integer cycle = 0;
  integer uart_write_count = 0;
  reg [7:0] uart_bytes [0:3];

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

  function automatic [31:0] enc_i;
    input integer imm;
    input integer rs1;
    input integer funct3;
    input integer rd;
    input integer opcode;
    reg [11:0] imm12;
    begin
      imm12 = imm[11:0];
      enc_i = {imm12, rs1[4:0], funct3[2:0], rd[4:0], opcode[6:0]};
    end
  endfunction

  function automatic [31:0] enc_r;
    input integer funct7;
    input integer rs2;
    input integer rs1;
    input integer funct3;
    input integer rd;
    input integer opcode;
    begin
      enc_r = {funct7[6:0], rs2[4:0], rs1[4:0], funct3[2:0], rd[4:0], opcode[6:0]};
    end
  endfunction

  function automatic [31:0] enc_s;
    input integer imm;
    input integer rs2;
    input integer rs1;
    input integer funct3;
    input integer opcode;
    reg [11:0] imm12;
    begin
      imm12 = imm[11:0];
      enc_s = {imm12[11:5], rs2[4:0], rs1[4:0], funct3[2:0], imm12[4:0], opcode[6:0]};
    end
  endfunction

  function automatic [31:0] enc_b;
    input integer imm;
    input integer rs2;
    input integer rs1;
    input integer funct3;
    input integer opcode;
    reg [12:0] imm13;
    begin
      imm13 = imm[12:0];
      enc_b = {
        imm13[12], imm13[10:5], rs2[4:0], rs1[4:0], funct3[2:0],
        imm13[4:1], imm13[11], opcode[6:0]
      };
    end
  endfunction

  function automatic [31:0] enc_u;
    input integer imm20;
    input integer rd;
    input integer opcode;
    begin
      enc_u = {imm20[19:0], rd[4:0], opcode[6:0]};
    end
  endfunction

  function automatic [31:0] enc_j;
    input integer imm;
    input integer rd;
    input integer opcode;
    reg [20:0] imm21;
    begin
      imm21 = imm[20:0];
      enc_j = {
        imm21[20], imm21[10:1], imm21[11], imm21[19:12], rd[4:0], opcode[6:0]
      };
    end
  endfunction

  task automatic expect_reg;
    input integer reg_idx;
    input [31:0] expected;
    begin
      if (dut.cpu.regs[reg_idx] !== expected) begin
        $display("TB_PIPELINE_DIAG FAIL: x%0d expected 0x%08x got 0x%08x",
                 reg_idx, expected, dut.cpu.regs[reg_idx]);
        $fatal(1);
      end
    end
  endtask

  task automatic init_program;
    integer i;
    begin
      for (i = 0; i < 1024; i = i + 1) begin
        dut.u_imem.imem[i] = 32'h0000_0013;
        dut.u_dmem.dmem[i] = 32'h0000_0000;
      end

      // Base pointers
      dut.u_imem.imem[0]  = enc_u(20'h20000, 20, 7'b0110111);  // x20 = 0x2000_0000
      dut.u_imem.imem[1]  = enc_u(20'h10000, 21, 7'b0110111);  // x21 = 0x1000_0000

      // Basic ALU + RAW
      dut.u_imem.imem[2]  = enc_i(5,  0, 3'b000,  1, 7'b0010011); // x1 = 5
      dut.u_imem.imem[3]  = enc_i(7,  0, 3'b000,  2, 7'b0010011); // x2 = 7
      dut.u_imem.imem[4]  = enc_r(7'b0000000, 2, 1, 3'b000, 3, 7'b0110011); // x3 = x1 + x2 = 12
      dut.u_imem.imem[5]  = enc_i(1,  3, 3'b000,  4, 7'b0010011); // x4 = x3 + 1 = 13

      // Store/load + load-use
      dut.u_imem.imem[6]  = enc_s(0,  4, 20, 3'b010, 7'b0100011); // sw x4, 0(x20)
      dut.u_imem.imem[7]  = enc_i(0, 20, 3'b010,  5, 7'b0000011); // lw x5, 0(x20)
      dut.u_imem.imem[8]  = enc_i(2,  5, 3'b000,  6, 7'b0010011); // x6 = x5 + 2 = 15
      dut.u_imem.imem[9]  = enc_i(15, 0, 3'b000,  7, 7'b0010011); // x7 = 15

      // Branch not taken, then taken
      dut.u_imem.imem[10] = enc_b(8,  7, 6, 3'b001, 7'b1100011); // bne x6, x7, +8 (not taken)
      dut.u_imem.imem[11] = enc_i(1,  0, 3'b000,  8, 7'b0010011); // x8 = 1
      dut.u_imem.imem[12] = enc_b(8,  7, 6, 3'b000, 7'b1100011); // beq x6, x7, +8 (taken)
      dut.u_imem.imem[13] = enc_i(1,  0, 3'b000,  9, 7'b0010011); // x9 = 1 (must flush)

      // JAL / JALR
      dut.u_imem.imem[14] = enc_j(8, 10, 7'b1101111);            // jal x10, +8
      dut.u_imem.imem[15] = enc_i(1,  0, 3'b000, 11, 7'b0010011); // x11 = 1 (must flush)
      dut.u_imem.imem[16] = enc_i(3,  0, 3'b000, 12, 7'b0010011); // x12 = 3
      dut.u_imem.imem[17] = enc_i(76, 0, 3'b000, 13, 7'b0010011); // x13 = byte addr 76 (index 19)
      dut.u_imem.imem[18] = enc_i(0, 13, 3'b000, 14, 7'b1100111); // jalr x14, x13, 0
      dut.u_imem.imem[19] = enc_i(4,  0, 3'b000, 15, 7'b0010011); // x15 = 4

      // M-extension + dependent consumer
      dut.u_imem.imem[20] = enc_r(7'b0000001, 2, 1, 3'b000, 16, 7'b0110011); // mul x16, x1, x2 = 35
      dut.u_imem.imem[21] = enc_i(1, 16, 3'b000, 17, 7'b0010011); // x17 = x16 + 1 = 36
      dut.u_imem.imem[22] = enc_r(7'b0000001, 1, 16, 3'b100, 18, 7'b0110011); // div x18, x16, x1 = 7
      dut.u_imem.imem[23] = enc_r(7'b0000001, 1, 16, 3'b110, 19, 7'b0110011); // rem x19, x16, x1 = 0

      // UART backpressure: back-to-back writes should serialize, not drop
      dut.u_imem.imem[24] = enc_i(65, 0, 3'b000, 24, 7'b0010011); // x24 = 'A'
      dut.u_imem.imem[25] = enc_s(0, 24, 21, 3'b010, 7'b0100011); // sw x24, 0(x21)
      dut.u_imem.imem[26] = enc_i(66, 0, 3'b000, 25, 7'b0010011); // x25 = 'B'
      dut.u_imem.imem[27] = enc_s(0, 25, 21, 3'b010, 7'b0100011); // sw x25, 0(x21)

      // Store/load after long dmem/uart activity
      dut.u_imem.imem[28] = enc_s(4, 18, 20, 3'b010, 7'b0100011); // sw x18, 4(x20)
      dut.u_imem.imem[29] = enc_i(4, 20, 3'b010, 22, 7'b0000011); // lw x22, 4(x20)
      dut.u_imem.imem[30] = enc_b(8,  2, 22, 3'b000, 7'b1100011); // beq x22, x2, +8 (taken)
      dut.u_imem.imem[31] = enc_i(1,  0, 3'b000, 23, 7'b0010011); // x23 = 1 (must flush)
      dut.u_imem.imem[32] = enc_i(9,  0, 3'b000, 26, 7'b0010011); // x26 = 9

      // Explicit stop marker
      dut.u_imem.imem[33] = 32'h0000_0000;
    end
  endtask

  initial begin
    init_program();
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
  end

  always @(posedge clk) begin
    cycle <= cycle + 1;

    if (dut.s_uart_we && dut.s_uart_ready && uart_write_count < 4) begin
      uart_bytes[uart_write_count] <= dut.s_uart_wdata[7:0];
      uart_write_count <= uart_write_count + 1;
    end

    if (cycle <= 220 || dut.s_uart_we || (dut.cpu.fetch_pc >= 32'h0000_0070) || dut.cpu.fetch_pc == 32'h0000_1000) begin
      $display("cy=%0d pc=%08x instr=%08x next=%08x ifhold=%0b exhold=%0b loaduse=%0b exraw=%0b branch=%0b muls=%0b divs=%0b re=%0b rv=%0b we=%0b wv=%0b x3=%08x x4=%08x x5=%08x x6=%08x x8=%08x x9=%08x x10=%08x x11=%08x x12=%08x x14=%08x x15=%08x x16=%08x x17=%08x x18=%08x x19=%08x x22=%08x x23=%08x x24=%08x x25=%08x x26=%08x",
               cycle, dut.cpu.fetch_pc, dut.cpu.instruction, dut.cpu.next_pc,
               dut.cpu.if_id_hold, dut.cpu.ex_hold, dut.cpu.load_use_stall, dut.cpu.ex_raw_stall,
               dut.cpu.branch_taken, dut.cpu.mul_stall, dut.cpu.div_stall,
               dut.cpu_dmem_re, dut.cpu_dmem_rvalid, dut.cpu_dmem_we, dut.cpu_dmem_wvalid,
               dut.cpu.regs[3], dut.cpu.regs[4], dut.cpu.regs[5], dut.cpu.regs[6],
               dut.cpu.regs[8], dut.cpu.regs[9], dut.cpu.regs[10], dut.cpu.regs[11],
               dut.cpu.regs[12], dut.cpu.regs[14], dut.cpu.regs[15], dut.cpu.regs[16],
               dut.cpu.regs[17], dut.cpu.regs[18], dut.cpu.regs[19], dut.cpu.regs[22],
               dut.cpu.regs[23], dut.cpu.regs[24], dut.cpu.regs[25], dut.cpu.regs[26]);
    end

    if (dut.s_uart_we && dut.s_uart_ready)
      $display("UARTWRITE cy=%0d data=%02x", cycle, dut.s_uart_wdata[7:0]);

    if (cycle > MAX_CYCLES) begin
      $display("TB_PIPELINE_DIAG FAIL: timeout pc=0x%08x instr=0x%08x x9=0x%08x x11=0x%08x x23=0x%08x uart_count=%0d",
               dut.cpu.fetch_pc, dut.cpu.instruction, dut.cpu.regs[9], dut.cpu.regs[11],
               dut.cpu.regs[23], uart_write_count);
      $fatal(1);
    end
  end

  initial begin
    wait (rst_n);
    wait (dut.cpu.program_done);
    repeat (5) @(posedge clk);

    expect_reg(3,  32'd12);
    expect_reg(4,  32'd13);
    expect_reg(5,  32'd13);
    expect_reg(6,  32'd15);
    expect_reg(8,  32'd1);
    expect_reg(9,  32'd0);
    expect_reg(10, 32'd60);
    expect_reg(11, 32'd0);
    expect_reg(12, 32'd3);
    expect_reg(14, 32'd76);
    expect_reg(15, 32'd4);
    expect_reg(16, 32'd35);
    expect_reg(17, 32'd36);
    expect_reg(18, 32'd7);
    expect_reg(19, 32'd0);
    expect_reg(22, 32'd7);
    expect_reg(23, 32'd0);
    expect_reg(24, 32'd65);
    expect_reg(25, 32'd66);
    expect_reg(26, 32'd9);

    if (dut.u_dmem.dmem[0] !== 32'd13) begin
      $display("TB_PIPELINE_DIAG FAIL: DMEM[0] expected 13 got 0x%08x", dut.u_dmem.dmem[0]);
      $fatal(1);
    end
    if (dut.u_dmem.dmem[1] !== 32'd7) begin
      $display("TB_PIPELINE_DIAG FAIL: DMEM[1] expected 7 got 0x%08x", dut.u_dmem.dmem[1]);
      $fatal(1);
    end
    if (uart_write_count < 2) begin
      $display("TB_PIPELINE_DIAG FAIL: expected two UART writes, saw %0d", uart_write_count);
      $fatal(1);
    end
    if (uart_bytes[0] !== 8'h41 || uart_bytes[1] !== 8'h42) begin
      $display("TB_PIPELINE_DIAG FAIL: expected UART bytes 41/42, got %02x/%02x", uart_bytes[0], uart_bytes[1]);
      $fatal(1);
    end

    $display("TB_PIPELINE_DIAG PASS");
    $finish;
  end

endmodule
