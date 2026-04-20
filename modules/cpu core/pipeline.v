
`timescale 1ns / 1ps

module pipe #(
    parameter [31:0] RESET = 32'h0000_0000,
    parameter        HALT_ON_ZERO = 1'b0
) (
    input         clk,
    input         reset,
    input         imem_stall_i,
    input         dmem_stall_i,
    output        exception,
    output [31:0] pc_out,

    // IMEM Interface
    output [31:0] inst_mem_address,
    input         inst_mem_is_valid,
    input  [31:0] inst_mem_read_data,
    output        inst_mem_is_ready,

    // DMEM Interface
    output [31:0] dmem_read_address,
    output        dmem_read_ready,
    input  [31:0] dmem_read_data_temp,
    input         dmem_read_valid,
    output [31:0] dmem_write_address,
    output        dmem_write_ready,
    output [31:0] dmem_write_data,
    output [ 3:0] dmem_write_byte,
    input         dmem_write_valid,

    // Completed M-extension instruction event for UART reporting
    output        mext_event_valid,
    output [2:0]  mext_event_func3,
    output [31:0] mext_event_operand1,
    output [31:0] mext_event_operand2,
    output [31:0] mext_event_result,
    output [31:0] mext_event_pc,
    output [4:0]  mext_event_rd,
    output [7:0]  mext_event_unit_cycles,
    output [31:0] mext_event_total_cycles
);

  // -- Declaring Wires and Registers -- //

  // Data Memory Wires
  wire [31:0] dmem_read_data;
  wire [ 1:0] dmem_read_offset;

  // Instruction Fetch/Decode Stage
  reg  [31:0] immediate;
  wire        immediate_sel;
  wire [ 4:0] src1_select;
  wire [ 4:0] src2_select;
  wire [ 4:0] dest_reg_sel;
  wire [ 2:0] alu_operation;
  wire        arithsubtype;
  wire        mem_write;
  wire        mem_to_reg;
  wire        illegal_inst;
  wire        is_m_ext;
  wire [31:0] execute_immediate;
  wire        alu;
  wire        lui;
  wire        jal;
  wire        jalr;
  wire        branch;
  wire [31:0] instruction;
  wire [31:0] reg_rdata2;
  wire [31:0] reg_rdata1;
  reg  [31:0] regs                    [31:1];

  // PC
  wire [31:0] pc;
  wire [31:0] inst_fetch_pc;
  reg  [31:0] fetch_pc;

  // Stalls
  wire        wb_stall;
  wire        mul_stall;
  wire        div_stall;
  wire        internal_stall;
  wire        frontend_stall;
  wire        pc_hold;
  wire        if_id_hold;
  wire        ex_hold;
  wire        load_use_stall;
  wire        ex_raw_stall;
  wire        wb_raw_stall;
  reg  [31:0] cycle_counter;
  reg         program_done;

  // Execute Stage
  wire [31:0] next_pc;
  wire [31:0] write_address;
  wire        branch_taken;
  wire        flush_decode;
  wire [31:0] alu_operand1;
  wire [31:0] alu_operand2;

  // Write Back
  wire        wb_alu_to_reg;
  wire [31:0] wb_result;
  wire [ 2:0] wb_alu_operation;
  wire        wb_mem_write;
  wire        wb_mem_to_reg;
  wire [ 4:0] wb_dest_reg_sel;
  wire [31:0] wb_store_address;
  wire [31:0] wb_store_data;
  wire [31:0] wb_write_address;
  wire [ 1:0] wb_read_address;
  wire [ 3:0] wb_write_byte;
  wire [31:0] wb_write_data;
  wire [31:0] wb_read_data;
  wire        mext_event_valid_w;
  wire [2:0]  mext_event_func3_w;
  wire [31:0] mext_event_operand1_w;
  wire [31:0] mext_event_operand2_w;
  wire [31:0] mext_event_result_w;
  wire [31:0] mext_event_pc_w;
  wire [4:0]  mext_event_rd_w;
  wire [7:0]  mext_event_unit_cycles_w;
  localparam [6:0] OPCODE_JALR   = 7'b1100111;
  localparam [6:0] OPCODE_BRANCH = 7'b1100011;
  localparam [6:0] OPCODE_LOAD   = 7'b0000011;
  localparam [6:0] OPCODE_STORE  = 7'b0100011;
  localparam [6:0] OPCODE_ARITHI = 7'b0010011;
  localparam [6:0] OPCODE_ARITHR = 7'b0110011;

  wire [6:0]  decode_opcode = instruction[6:0];
  wire [4:0]  decode_rs1    = instruction[19:15];
  wire [4:0]  decode_rs2    = instruction[24:20];
  wire        decode_uses_rs1 =
      (decode_opcode == OPCODE_JALR)   ||
      (decode_opcode == OPCODE_BRANCH) ||
      (decode_opcode == OPCODE_LOAD)   ||
      (decode_opcode == OPCODE_STORE)  ||
      (decode_opcode == OPCODE_ARITHI) ||
      (decode_opcode == OPCODE_ARITHR);
  wire        decode_uses_rs2 =
      (decode_opcode == OPCODE_BRANCH) ||
      (decode_opcode == OPCODE_STORE)  ||
      (decode_opcode == OPCODE_ARITHR);
  //------------------------------------------------------//
  assign dmem_write_address = wb_write_address; 
  assign dmem_read_address = alu_operand1 + execute_immediate;
  assign dmem_read_offset = dmem_read_address[1:0];
  assign dmem_read_ready = mem_to_reg;
  assign dmem_write_ready = wb_mem_write;
  assign dmem_write_data = wb_write_data;
  assign dmem_write_byte = wb_write_byte;
  assign dmem_read_data = dmem_read_data_temp;
  // -----------------------------------------------------//

  // Instantiating IF module
  IF_ID IF_ID_stage (
      .clk      (clk),
      .reset    (reset),
      .stall    (dmem_stall_i),
      .exception(exception),

      // IMEM interface
      .inst_mem_is_valid (inst_mem_is_valid),
      .inst_mem_read_data(inst_mem_read_data),

      .stall_read_i (if_id_hold),
      .bubble_id_ex_i(load_use_stall | flush_decode),
      .flush_i      (flush_decode),
      .inst_fetch_pc(inst_fetch_pc),
      .instruction_i(instruction),

      // WB-stage signals
      .wb_stall       (wb_stall),
      .wb_alu_to_reg  (wb_alu_to_reg),
      .wb_mem_to_reg  (wb_mem_to_reg),
      .wb_dest_reg_sel(wb_dest_reg_sel),
      .wb_result      (wb_result),
      .wb_read_data   (wb_read_data),

      // Instruction memory address offset
      .inst_mem_offset(inst_mem_address[1:0]),

      // Output wires (write-only)
      .execute_immediate_w(execute_immediate),
      .immediate_sel_w    (immediate_sel),
      .alu_w              (alu),
      .lui_w              (lui),
      .jal_w              (jal),
      .jalr_w             (jalr),
      .branch_w           (branch),
      .mem_write_w        (mem_write),
      .mem_to_reg_w       (mem_to_reg),
      .arithsubtype_w     (arithsubtype),
      .pc_w               (pc),
      .src1_select_w      (src1_select),
      .src2_select_w      (src2_select),
      .dest_reg_sel_w     (dest_reg_sel),
      .alu_operation_w    (alu_operation),
      .illegal_inst_w     (illegal_inst),
      .is_m_ext_w         (is_m_ext),
      .instruction_o      (instruction)
  );

  // Keep WB bypass only for non-load results.
  // Load data is written into the register file when dmem_read_valid asserts,
  // and the dependent instruction reads it from regs on the following cycle.
  // This removes the long combinational path from bus/UART readback through
  // WB formatting and decode back into execute-stage address/result logic.
  assign reg_rdata1 = (src1_select == 5'd0) ? 32'b0 :
      (!wb_stall && wb_alu_to_reg && !wb_mem_to_reg &&
       (wb_dest_reg_sel == src1_select))
        ? wb_result
        : regs[src1_select];

  assign reg_rdata2 =
      (src2_select == 5'd0) ? 32'b0 :
      (!wb_stall && wb_alu_to_reg && !wb_mem_to_reg &&
       (wb_dest_reg_sel == src2_select))
        ? wb_result
        : regs[src2_select];

  integer i;
  always @(posedge clk) begin
    if (!reset) begin
      for (i = 1; i < 32; i = i + 1) regs[i] <= 32'b0;
    end
    else if (wb_alu_to_reg && !wb_stall && wb_dest_reg_sel != 5'd0 &&
             (!wb_mem_to_reg || dmem_read_valid)) begin
      regs[wb_dest_reg_sel] <=
        	wb_mem_to_reg ? wb_read_data : wb_result;
    end
  end

  ////////////////////////////////////////////////////////////
  // Stall register
  ////////////////////////////////////////////////////////////

  // Stop the fetch PC once the program reaches the explicit 0x00000000 end marker.
  // This prevents the FPGA from running into uninitialized instruction memory and
  // emitting duplicate UART reports after the intended MUL/DIV/REM sequence finishes.
  always @(posedge clk) begin
    if (!reset) program_done <= 1'b0;
    else if (HALT_ON_ZERO && !program_done && !pc_hold &&
    
             (instruction == 32'h0000_0000) &&
             (fetch_pc != RESET)) begin
      program_done <= 1'b1;
    end
  end

  // FIXED BUG: Changed 'wire' to 'assign' because it was declared above
  assign load_use_stall =
      mem_to_reg &&
      (dest_reg_sel != 5'd0) &&
      (((decode_uses_rs1 && (decode_rs1 == dest_reg_sel))) ||
       ((decode_uses_rs2 && (decode_rs2 == dest_reg_sel))));
  assign ex_raw_stall = 1'b0;
  assign wb_raw_stall = 1'b0;

  assign frontend_stall = imem_stall_i | dmem_stall_i | mul_stall | div_stall;
  assign if_id_hold   = frontend_stall | load_use_stall | ex_raw_stall | wb_raw_stall;
  assign pc_hold      = if_id_hold;
  assign ex_hold      = (wb_mem_write && !dmem_write_valid) | mul_stall | div_stall;
  assign internal_stall = pc_hold;
  assign flush_decode = branch_taken;

  // instantiating execute module -----------------------------------
  execute execute (
      .clk  (clk),
      .reset(reset),

      .reg_rdata1   (reg_rdata1),
      .reg_rdata2   (reg_rdata2),
      .execute_imm  (execute_immediate),
      .pc           (pc),
      .fetch_pc     (fetch_pc),
      .immediate_sel(immediate_sel),
      .mem_write    (mem_write),
      .jal          (jal),
      .jalr         (jalr),
      .lui          (lui),
      .alu          (alu),
      .branch       (branch),
      .arithsubtype (arithsubtype),
      .mem_to_reg   (mem_to_reg),
      .stall_read   (ex_hold),
      .mul_stall    (mul_stall),
      .div_stall    (div_stall),
      .dest_reg_sel (dest_reg_sel),
      .alu_op       (alu_operation),
      .dmem_raddr   (dmem_read_offset),
      .is_m_ext     (is_m_ext),

      .alu_operand1 (alu_operand1),
      .alu_operand2 (alu_operand2),
      .write_address(write_address),
      .next_pc      (next_pc),
      .branch_taken (branch_taken),

      .wb_result        (wb_result),
      .wb_mem_write     (wb_mem_write),
      .wb_alu_to_reg    (wb_alu_to_reg),
      .wb_dest_reg_sel  (wb_dest_reg_sel),
      .wb_mem_to_reg    (wb_mem_to_reg),
      .wb_store_address (wb_store_address),
      .wb_store_data    (wb_store_data),
      .wb_read_address  (wb_read_address),
      .mem_alu_operation(wb_alu_operation),

      .mext_done        (mext_event_valid_w),
      .mext_func3       (mext_event_func3_w),
      .mext_operand1    (mext_event_operand1_w),
      .mext_operand2    (mext_event_operand2_w),
      .mext_result      (mext_event_result_w),
      .mext_pc          (mext_event_pc_w),
      .mext_rd          (mext_event_rd_w),
      .mext_unit_cycles (mext_event_unit_cycles_w)
  );

  always @(posedge clk) begin
    if (!reset) fetch_pc <= RESET;
    else if (!pc_hold && !program_done) fetch_pc <= next_pc;
  end

  wb wb_stage (
      .clk  (clk),
      .reset(reset),

      .fetch_pause_i      (mul_stall | div_stall),
      .stall_read_i      (dmem_stall_i),
      .fetch_pc_i        (fetch_pc),
      .wb_mem_to_reg_i   (wb_mem_to_reg),
      .wb_mem_write_i    (wb_mem_write),
      .wb_store_address_i(wb_store_address),
      .wb_store_data_i   (wb_store_data),
      .wb_alu_operation_i(wb_alu_operation),
      .wb_read_address_i (wb_read_address),
      .dmem_read_data_i  (dmem_read_data),
      .dmem_read_valid_i (dmem_read_valid),
      .dmem_write_valid_i(dmem_write_valid),

      .inst_mem_address_o (inst_mem_address),
      .inst_mem_is_ready_o(inst_mem_is_ready),
      .wb_stall_o         (wb_stall),
      .wb_write_address_o (wb_write_address),
      .wb_write_data_o    (wb_write_data),
      .wb_write_byte_o    (wb_write_byte),
      .wb_read_data_o     (wb_read_data),
      .inst_fetch_pc_o    (inst_fetch_pc),
      .wb_stall_first_o   (),
      .wb_stall_second_o  ()
  );

  always @(posedge clk) begin
    if (!reset) cycle_counter <= 32'd0;
    else if (!program_done) cycle_counter <= cycle_counter + 1'b1;
  end

  assign pc_out = fetch_pc;
  assign mext_event_valid        = mext_event_valid_w;
  assign mext_event_func3        = mext_event_func3_w;
  assign mext_event_operand1     = mext_event_operand1_w;
  assign mext_event_operand2     = mext_event_operand2_w;
  assign mext_event_result       = mext_event_result_w;
  assign mext_event_pc           = mext_event_pc_w;
  assign mext_event_rd           = mext_event_rd_w;
  assign mext_event_unit_cycles  = mext_event_unit_cycles_w;
  assign mext_event_total_cycles = cycle_counter;
  
// -------- Simulation monitor removed for synthesizable SoC build -------- //
// (Use the UART peripheral at 0x1000_0000 to emit results at runtime)
    
endmodule
