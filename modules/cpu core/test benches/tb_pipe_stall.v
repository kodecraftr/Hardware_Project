`timescale 1ns / 1ps

module tb_pipe_stall;

  localparam [31:0] RESET_ADDR = 32'h0000_0000;
  localparam integer MAX_CYCLES = 400;

  reg clk;
  reg reset;
  wire stall;

  wire exception;
  wire [31:0] pc_out;

  wire [31:0] inst_mem_address;
  reg         inst_mem_is_valid;
  reg  [31:0] inst_mem_read_data;
  wire        inst_mem_is_ready;

  wire [31:0] dmem_read_address;
  wire        dmem_read_ready;
  reg  [31:0] dmem_read_data_temp;
  reg         dmem_read_valid;

  wire [31:0] dmem_write_address;
  wire        dmem_write_ready;
  wire [31:0] dmem_write_data;
  wire [3:0]  dmem_write_byte;
  reg         dmem_write_valid;

  reg [31:0] imem [0:255];
  reg [31:0] dmem [0:255];

  integer cycle_count;

  assign stall = (inst_mem_is_ready  && !inst_mem_is_valid) ||
                 (dmem_read_ready    && !dmem_read_valid)   ||
                 (dmem_write_ready   && !dmem_write_valid);

  pipe #(
      .RESET(RESET_ADDR)
  ) dut (
      .clk(clk),
      .reset(reset),
      .stall(stall),
      .exception(exception),
      .pc_out(pc_out),
      .inst_mem_address(inst_mem_address),
      .inst_mem_is_valid(inst_mem_is_valid),
      .inst_mem_read_data(inst_mem_read_data),
      .inst_mem_is_ready(inst_mem_is_ready),
      .dmem_read_address(dmem_read_address),
      .dmem_read_ready(dmem_read_ready),
      .dmem_read_data_temp(dmem_read_data_temp),
      .dmem_read_valid(dmem_read_valid),
      .dmem_write_address(dmem_write_address),
      .dmem_write_ready(dmem_write_ready),
      .dmem_write_data(dmem_write_data),
      .dmem_write_byte(dmem_write_byte),
      .dmem_write_valid(dmem_write_valid),

      // Unused for Day 1
      .mext_event_valid(),
      .mext_event_func3(),
      .mext_event_operand1(),
      .mext_event_operand2(),
      .mext_event_result(),
      .mext_event_pc(),
      .mext_event_rd(),
      .mext_event_unit_cycles(),
      .mext_event_total_cycles()
  );

  // -------------------------
  // Encoding functions
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

  // -------------------------
  // Program init
  // -------------------------
  task automatic init_program;
    integer i;
    begin
      for (i = 0; i < 256; i = i + 1) begin
        imem[i] = 32'h0000_0013;
        dmem[i] = 32'h0000_0000;
      end

      imem[0] = 32'h20000537; // lui x10
      imem[1] = enc_i(5, 0, 3'b000, 1, 7'b0010011);
      imem[2] = enc_i(7, 0, 3'b000, 2, 7'b0010011);
      imem[3] = enc_r(7'b0000000, 2, 1, 3'b000, 3, 7'b0110011);
      imem[4] = enc_s(0, 3, 10, 3'b010, 7'b0100011);
      imem[5] = enc_i(0, 10, 3'b010, 4, 7'b0000011);
      imem[6] = enc_i(1, 4, 3'b000, 5, 7'b0010011);

      imem[7] = 32'h00000000;
    end
  endtask

  // Clock
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Reset and init
  initial begin
    init_program();

    reset = 0;
    inst_mem_is_valid = 0;
    dmem_read_valid = 0;
    dmem_write_valid = 0;
    cycle_count = 0;

    repeat(4) @(posedge clk);
    reset = 1;
  end

  // Simple instant IMEM
  always @(posedge clk) begin
    if (reset) begin
      inst_mem_read_data <= imem[inst_mem_address[11:2]];
      inst_mem_is_valid <= inst_mem_is_ready;
    end
  end

  // Simple instant DMEM read
  always @(posedge clk) begin
    if (reset) begin
      dmem_read_data_temp <= dmem[dmem_read_address[11:2]];
      dmem_read_valid <= dmem_read_ready;
    end
  end

  // Simple instant DMEM write
  always @(posedge clk) begin
    if (reset) begin
      if (dmem_write_ready) begin
        dmem[dmem_write_address[11:2]] <= dmem_write_data;
      end
      dmem_write_valid <= dmem_write_ready;
    end
  end

  // Monitor
  always @(posedge clk) begin
    if (reset) begin
      cycle_count <= cycle_count + 1;

      $display("cy=%0d pc=%08x x3=%0d x4=%0d x5=%0d",
                cycle_count, pc_out,
                dut.regs[3], dut.regs[4], dut.regs[5]);

      if (cycle_count > MAX_CYCLES) begin
        $display("FAIL: timeout");
        $fatal(1);
      end
    end
  end

  // Final check
  initial begin
    wait(reset);
    wait(dut.program_done);
    repeat(5) @(posedge clk);

    if (dut.regs[3] != 12) $fatal("x3 failed");
    if (dut.regs[4] != 12) $fatal("x4 failed");
    if (dut.regs[5] != 13) $fatal("x5 failed");
    if (dmem[0] != 12) $fatal("dmem failed");

    $display("TB_PIPE_STALL DAY1 PASS");
    $finish;
  end

endmodule