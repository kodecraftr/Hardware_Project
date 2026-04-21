`timescale 1ns / 1ps

module tb_pipe_stall;

  localparam [31:0] RESET_ADDR = 32'h0000_0000;
  localparam [31:0] END_MARKER_PC = 32'h0000_0058;
  localparam integer MAX_CYCLES = 800;
  localparam integer DEADLOCK_LIMIT = 200;

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

  wire        mext_event_valid;
  wire [2:0]  mext_event_func3;
  wire [31:0] mext_event_operand1;
  wire [31:0] mext_event_operand2;
  wire [31:0] mext_event_result;
  wire [31:0] mext_event_pc;
  wire [4:0]  mext_event_rd;
  wire [7:0]  mext_event_unit_cycles;
  wire [31:0] mext_event_total_cycles;

  reg [31:0] imem [0:255];
  reg [31:0] dmem [0:255];

  reg        imem_pending;
  reg        imem_committed;
  reg [31:0] imem_latched_addr;
  integer    imem_delay;
  integer    imem_req_count;

  reg        dread_pending;
  reg        dread_committed;
  reg [31:0] dread_latched_addr;
  integer    dread_delay;
  integer    dread_req_count;

  reg        dwrite_pending;
  reg        dwrite_committed;
  reg [31:0] dwrite_latched_addr;
  reg [31:0] dwrite_latched_data;
  reg [3:0]  dwrite_latched_strb;
  integer    dwrite_delay;
  integer    dwrite_req_count;

  integer cycle_count;
  integer last_progress_cycle;
  integer mext_count;
  integer uart_write_count;
  reg [7:0] uart_last_byte;
  reg [31:0] prev_pc;
  reg        prev_internal_stall;
  reg [31:0] prev_imem_rsp_addr;

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
      .mext_event_valid(mext_event_valid),
      .mext_event_func3(mext_event_func3),
      .mext_event_operand1(mext_event_operand1),
      .mext_event_operand2(mext_event_operand2),
      .mext_event_result(mext_event_result),
      .mext_event_pc(mext_event_pc),
      .mext_event_rd(mext_event_rd),
      .mext_event_unit_cycles(mext_event_unit_cycles),
      .mext_event_total_cycles(mext_event_total_cycles)
  );

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

  function automatic integer get_imem_delay;
    input [31:0] addr;
    input integer req_idx;
    begin
      case (addr)
        32'h0000_0000: get_imem_delay = 2;
        32'h0000_0004: get_imem_delay = 1;
        32'h0000_0038: get_imem_delay = 3;
        32'h0000_004C: get_imem_delay = 2;
        default:      get_imem_delay = (req_idx == 6) ? 1 : 0;
      endcase
    end
  endfunction

  function automatic integer get_dread_delay;
    input [31:0] addr;
    input integer req_idx;
    begin
      case (addr)
        32'h2000_0000: get_dread_delay = 4;
        32'h2000_0004: get_dread_delay = 2;
        default:      get_dread_delay = (req_idx == 0) ? 1 : 0;
      endcase
    end
  endfunction

  function automatic integer get_dwrite_delay;
    input [31:0] addr;
    input integer req_idx;
    begin
      case (addr)
        32'h2000_0000: get_dwrite_delay = 2;
        32'h2000_0004: get_dwrite_delay = 1;
        32'h1000_0000: get_dwrite_delay = 3;
        default:      get_dwrite_delay = req_idx[0];
      endcase
    end
  endfunction

  task automatic apply_write;
    input [31:0] addr;
    input [31:0] data;
    input [3:0]  strb;
    integer idx;
    begin
      if (addr[31:28] == 4'h2) begin
        idx = addr[11:2];
        if (strb[0]) dmem[idx][7:0]   = data[7:0];
        if (strb[1]) dmem[idx][15:8]  = data[15:8];
        if (strb[2]) dmem[idx][23:16] = data[23:16];
        if (strb[3]) dmem[idx][31:24] = data[31:24];
      end
      if (addr == 32'h1000_0000) begin
        uart_last_byte  = data[7:0];
        uart_write_count = uart_write_count + 1;
      end
    end
  endtask

  task automatic fail;
    input string message;
    begin
      $display("TB_PIPE_STALL FAIL: %0s", message);
      $fatal(1);
    end
  endtask

  task automatic expect_reg;
    input integer reg_idx;
    input [31:0] expected;
    begin
      if (dut.regs[reg_idx] !== expected)
        fail($sformatf("x%0d expected 0x%08x got 0x%08x", reg_idx, expected, dut.regs[reg_idx]));
    end
  endtask

  task automatic init_program;
    integer i;
    begin
      for (i = 0; i < 256; i = i + 1) begin
        imem[i] = 32'h0000_0013;
        dmem[i] = 32'h0000_0000;
      end

      // Program body
      imem[0]  = enc_u(20'h20000, 10, 7'b0110111); // lui  x10,0x20000
      imem[1]  = enc_u(20'h10000, 12, 7'b0110111); // lui  x12,0x10000
      imem[2]  = enc_i(5,   0, 3'b000,  1, 7'b0010011); // addi x1,x0,5
      imem[3]  = enc_i(7,   0, 3'b000,  2, 7'b0010011); // addi x2,x0,7
      imem[4]  = enc_r(7'b0000001, 2, 1, 3'b000, 3, 7'b0110011); // mul x3,x1,x2
      imem[5]  = enc_i(1,   3, 3'b000,  4, 7'b0010011); // addi x4,x3,1
      imem[6]  = enc_s(0,   3,10, 3'b010, 7'b0100011); // sw x3,0(x10)
      imem[7]  = enc_i(0,  10, 3'b010,  5, 7'b0000011); // lw x5,0(x10)
      imem[8]  = enc_i(2,   5, 3'b000,  6, 7'b0010011); // addi x6,x5,2
      imem[9]  = enc_i(37,  0, 3'b000,  7, 7'b0010011); // addi x7,x0,37
      imem[10] = enc_b(8,   7, 6, 3'b001, 7'b1100011); // bne x6,x7,+8 (not taken)
      imem[11] = enc_i(1,   0, 3'b000, 16, 7'b0010011); // addi x16,x0,1
      imem[12] = enc_b(8,   7, 6, 3'b000, 7'b1100011); // beq x6,x7,+8 (taken)
      imem[13] = enc_i(1,   0, 3'b000,  8, 7'b0010011); // addi x8,x0,1 (skipped)
      imem[14] = enc_r(7'b0000001, 1, 3, 3'b100, 9, 7'b0110011); // div x9,x3,x1
      imem[15] = enc_s(4,   9,10, 3'b010, 7'b0100011); // sw x9,4(x10)
      imem[16] = enc_i(4,  10, 3'b010, 11, 7'b0000011); // lw x11,4(x10)
      imem[17] = enc_b(8,   2,11, 3'b000, 7'b1100011); // beq x11,x2,+8 (taken)
      imem[18] = enc_i(1,   0, 3'b000, 13, 7'b0010011); // addi x13,x0,1 (skipped)
      imem[19] = enc_s(0,  11,12, 3'b010, 7'b0100011); // sw x11,0(x12) -> UART
      imem[20] = enc_r(7'b0000001, 1, 3, 3'b110,14, 7'b0110011); // rem x14,x3,x1
      imem[21] = enc_i(9,  14, 3'b000, 15, 7'b0010011); // addi x15,x14,9
      imem[22] = 32'h0000_0000; // explicit program end marker
    end
  endtask

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    init_program();

    reset = 1'b0;
    inst_mem_is_valid  = 1'b0;
    inst_mem_read_data = 32'h0;
    dmem_read_data_temp = 32'h0;
    dmem_read_valid = 1'b0;
    dmem_write_valid = 1'b0;

    imem_pending = 1'b0;
    imem_committed = 1'b0;
    imem_latched_addr = 32'h0;
    imem_delay = 0;
    imem_req_count = 0;

    dread_pending = 1'b0;
    dread_committed = 1'b0;
    dread_latched_addr = 32'h0;
    dread_delay = 0;
    dread_req_count = 0;

    dwrite_pending = 1'b0;
    dwrite_committed = 1'b0;
    dwrite_latched_addr = 32'h0;
    dwrite_latched_data = 32'h0;
    dwrite_latched_strb = 4'h0;
    dwrite_delay = 0;
    dwrite_req_count = 0;

    cycle_count = 0;
    last_progress_cycle = 0;
    mext_count = 0;
    uart_write_count = 0;
    uart_last_byte = 8'h00;
    prev_pc = 32'h0;
    prev_internal_stall = 1'b0;
    prev_imem_rsp_addr = 32'hFFFF_FFFF;

    repeat (4) @(posedge clk);
    reset = 1'b1;
  end

  always @(posedge clk or negedge reset) begin
    if (!reset) begin
      inst_mem_is_valid  <= 1'b0;
      inst_mem_read_data <= 32'h0;
      imem_pending       <= 1'b0;
      imem_committed     <= 1'b0;
      imem_delay         <= 0;
      imem_req_count     <= 0;
    end else begin
      if (!imem_pending && inst_mem_is_ready) begin
        imem_pending      <= 1'b1;
        imem_committed    <= 1'b0;
        imem_latched_addr <= inst_mem_address;
        imem_delay        <= get_imem_delay(inst_mem_address, imem_req_count);
        imem_req_count    <= imem_req_count + 1;
        inst_mem_is_valid <= 1'b0;
      end else if (imem_pending) begin
        if (imem_delay != 0) begin
          imem_delay         <= imem_delay - 1;
          inst_mem_is_valid  <= 1'b0;
        end else begin
          if (!imem_committed) begin
            inst_mem_read_data <= imem[imem_latched_addr[11:2]];
            imem_committed     <= 1'b1;
          end
          inst_mem_is_valid <= 1'b1;

          if (!inst_mem_is_ready) begin
            imem_pending      <= 1'b0;
            imem_committed    <= 1'b0;
            inst_mem_is_valid <= 1'b0;
          end
        end
      end else begin
        inst_mem_is_valid <= 1'b0;
      end
    end
  end

  always @(posedge clk or negedge reset) begin
    if (!reset) begin
      dmem_read_valid     <= 1'b0;
      dmem_read_data_temp <= 32'h0;
      dread_pending       <= 1'b0;
      dread_delay         <= 0;
      dread_req_count     <= 0;
      dread_committed     <= 1'b0;
    end else begin
      if (!dread_pending && dmem_read_ready) begin
        dread_pending      <= 1'b1;
        dread_committed    <= 1'b0;
        dread_latched_addr <= dmem_read_address;
        dread_delay        <= get_dread_delay(dmem_read_address, dread_req_count);
        dread_req_count    <= dread_req_count + 1;
        dmem_read_valid    <= 1'b0;
      end else if (dread_pending) begin
        if (dread_delay != 0) begin
          dread_delay     <= dread_delay - 1;
          dmem_read_valid <= 1'b0;
        end else begin
          if (!dread_committed) begin
            dmem_read_data_temp <= dmem[dread_latched_addr[11:2]];
            dread_committed     <= 1'b1;
          end
          dmem_read_valid <= 1'b1;

          if (!dmem_read_ready) begin
            dread_pending    <= 1'b0;
            dread_committed  <= 1'b0;
            dmem_read_valid  <= 1'b0;
          end
        end
      end else begin
        dmem_read_valid <= 1'b0;
      end
    end
  end

  always @(posedge clk or negedge reset) begin
    if (!reset) begin
      dmem_write_valid    <= 1'b0;
      dwrite_pending      <= 1'b0;
      dwrite_delay        <= 0;
      dwrite_req_count    <= 0;
      dwrite_committed    <= 1'b0;
    end else begin
      if (!dwrite_pending && dmem_write_ready) begin
        dwrite_pending      <= 1'b1;
        dwrite_committed    <= 1'b0;
        dwrite_latched_addr <= dmem_write_address;
        dwrite_latched_data <= dmem_write_data;
        dwrite_latched_strb <= dmem_write_byte;
        dwrite_delay        <= get_dwrite_delay(dmem_write_address, dwrite_req_count);
        dwrite_req_count    <= dwrite_req_count + 1;
        dmem_write_valid    <= 1'b0;
      end else if (dwrite_pending) begin
        if (dwrite_delay != 0) begin
          dwrite_delay     <= dwrite_delay - 1;
          dmem_write_valid <= 1'b0;
        end else begin
          if (!dwrite_committed) begin
            apply_write(dwrite_latched_addr, dwrite_latched_data, dwrite_latched_strb);
            dwrite_committed <= 1'b1;
          end
          dmem_write_valid <= 1'b1;

          if (!dmem_write_ready) begin
            dwrite_pending   <= 1'b0;
            dwrite_committed <= 1'b0;
            dmem_write_valid <= 1'b0;
          end
        end
      end else begin
        dmem_write_valid <= 1'b0;
      end
    end
  end

  always @(posedge clk) begin
    if (!reset) begin
      cycle_count         <= 0;
      last_progress_cycle <= 0;
      mext_count          <= 0;
      prev_pc             <= 32'h0;
    end else begin
      cycle_count <= cycle_count + 1;

      if (pc_out !== prev_pc ||
          (inst_mem_is_valid && imem_latched_addr !== prev_imem_rsp_addr) ||
          dmem_read_valid ||
          dmem_write_valid ||
          mext_event_valid) begin
        last_progress_cycle <= cycle_count;
      end

      if (prev_internal_stall && (pc_out !== prev_pc))
        fail($sformatf("PC changed during internal stall: prev=0x%08x curr=0x%08x", prev_pc, pc_out));

      if (exception && !dut.program_done && pc_out !== END_MARKER_PC)
        fail("Unexpected exception asserted");

      if ((cycle_count - last_progress_cycle) > DEADLOCK_LIMIT) begin
        $display("Deadlock dump:");
        $display("  pc_out=0x%08x fetch_pc=0x%08x instruction=0x%08x", pc_out, dut.fetch_pc, dut.instruction);
        $display("  stall=%0b internal_stall=%0b wb_stall=%0b branch_stall=%0b", stall, dut.internal_stall, dut.wb_stall, dut.branch_stall);
        $display("  mem_write=%0b mem_to_reg=%0b wb_mem_write=%0b wb_mem_to_reg=%0b", dut.mem_write, dut.mem_to_reg, dut.wb_mem_write, dut.wb_mem_to_reg);
        $display("  dmem_read_ready=%0b dmem_read_valid=%0b dmem_read_addr=0x%08x", dmem_read_ready, dmem_read_valid, dmem_read_address);
        $display("  dmem_write_ready=%0b dmem_write_valid=%0b dmem_write_addr=0x%08x data=0x%08x strb=%0h",
                 dmem_write_ready, dmem_write_valid, dmem_write_address, dmem_write_data, dmem_write_byte);
        $display("  wb_write_addr=0x%08x wb_result=0x%08x wb_read_data=0x%08x", dut.wb_write_address, dut.wb_result, dut.wb_read_data);
        fail($sformatf("Deadlock/progress timeout at cycle %0d, pc=0x%08x", cycle_count, pc_out));
      end

      if (cycle_count > MAX_CYCLES) begin
        $display("Max-cycle dump:");
        $display("  pc_out=0x%08x fetch_pc=0x%08x instruction=0x%08x", pc_out, dut.fetch_pc, dut.instruction);
        $display("  stall=%0b internal_stall=%0b wb_stall=%0b branch_stall=%0b program_done=%0b", stall, dut.internal_stall, dut.wb_stall, dut.branch_stall, dut.program_done);
        $display("  mem_write=%0b mem_to_reg=%0b wb_mem_write=%0b wb_mem_to_reg=%0b", dut.mem_write, dut.mem_to_reg, dut.wb_mem_write, dut.wb_mem_to_reg);
        $display("  dmem_read_ready=%0b dmem_read_valid=%0b dmem_read_addr=0x%08x", dmem_read_ready, dmem_read_valid, dmem_read_address);
        $display("  dmem_write_ready=%0b dmem_write_valid=%0b dmem_write_addr=0x%08x data=0x%08x strb=%0h",
                 dmem_write_ready, dmem_write_valid, dmem_write_address, dmem_write_data, dmem_write_byte);
        fail("Simulation exceeded max cycle budget");
      end

      if (mext_event_valid) begin
        $display("MEXT event %0d: func3=%0h rd=%0d result=0x%08x op1=0x%08x op2=0x%08x pc=0x%08x cycles=%0d total=%0d",
                 mext_count, mext_event_func3, mext_event_rd, mext_event_result,
                 mext_event_operand1, mext_event_operand2, mext_event_pc,
                 mext_event_unit_cycles, mext_event_total_cycles);
        mext_count <= mext_count + 1;
        case (mext_count)
          0: begin
            if (mext_event_func3 !== 3'b000 || mext_event_result !== 32'd35 || mext_event_rd !== 5'd3)
              $display("WARN: unexpected MUL completion payload");
          end
          1: begin
            if (mext_event_func3 !== 3'b100 || mext_event_result !== 32'd7 || mext_event_rd !== 5'd9)
              $display("WARN: unexpected DIV completion payload");
          end
          2: begin
            if (mext_event_func3 !== 3'b110 || mext_event_result !== 32'd0 || mext_event_rd !== 5'd14)
              $display("WARN: unexpected REM completion payload");
          end
          default: $display("WARN: unexpected extra M-extension completion event");
        endcase
      end

      prev_pc <= pc_out;
      prev_internal_stall <= dut.internal_stall;
      if (inst_mem_is_valid)
        prev_imem_rsp_addr <= imem_latched_addr;
    end
  end

  initial begin
    $dumpfile("tb_pipe_stall.vcd");
    $dumpvars(0, tb_pipe_stall);

    wait(reset);
    wait(dut.program_done);
    repeat (5) @(posedge clk);

    expect_reg(1, 32'd5);
    expect_reg(2, 32'd7);
    expect_reg(3, 32'd35);
    expect_reg(4, 32'd36);
    expect_reg(5, 32'd35);
    expect_reg(6, 32'd37);
    expect_reg(7, 32'd37);
    expect_reg(8, 32'd0);
    expect_reg(9, 32'd7);
    expect_reg(10, 32'h2000_0000);
    expect_reg(11, 32'd7);
    expect_reg(12, 32'h1000_0000);
    expect_reg(13, 32'd0);
    expect_reg(14, 32'd0);
    expect_reg(15, 32'd9);
    expect_reg(16, 32'd1);

    if (dmem[0] !== 32'd35)
      fail($sformatf("DMEM[0] expected 35 got 0x%08x", dmem[0]));
    if (dmem[1] !== 32'd7)
      fail($sformatf("DMEM[1] expected 7 got 0x%08x", dmem[1]));
    if (uart_write_count !== 1 || uart_last_byte !== 8'd7)
      fail($sformatf("UART write tracking mismatch count=%0d byte=0x%02x", uart_write_count, uart_last_byte));
    if (mext_count !== 3)
      fail($sformatf("Expected 3 M-extension events, saw %0d", mext_count));

    $display("TB_PIPE_STALL PASS");
    $finish;
  end

endmodule
