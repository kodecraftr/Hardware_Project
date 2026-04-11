`timescale 1ns / 1ps

module IF_ID #(
    parameter [31:0] RESET = 32'h0000_0000
) (
    input      clk,
    input      reset,
    input      stall,
    output reg exception,

    // IMEM interface
    input        inst_mem_is_valid,
    input [31:0] inst_mem_read_data,

    // ----------------------------- // Signals previously read from pipe  // -----------------------------
    input        stall_read_i,
    input        bubble_id_ex_i,
    input        flush_i,
    input [31:0] inst_fetch_pc,
    input [31:0] instruction_i,

    // -----------------------------    // WB-stage signals (passed in)    // -----------------------------
    input        wb_stall,
    input        wb_alu_to_reg,
    input        wb_mem_to_reg,
    input [ 4:0] wb_dest_reg_sel,
    input [31:0] wb_result,
    input [31:0] wb_read_data,

    // -----------------------------    // Instruction memory address info    // -----------------------------
    input  [ 1:0] inst_mem_offset,
    output [31:0] execute_immediate_w,
    output        immediate_sel_w,
    output        alu_w,
    output        lui_w,
    output        jal_w,
    output        jalr_w,
    output        branch_w,
    output        mem_write_w,
    output        mem_to_reg_w,
    output        arithsubtype_w,
    output [31:0] pc_w,
    output [ 4:0] src1_select_w,
    output [ 4:0] src2_select_w,
    output [ 4:0] dest_reg_sel_w,
    output [ 2:0] alu_operation_w,
    output        illegal_inst_w,
    output        is_m_ext_w,        // <-- ADD THIS LINE
    output [31:0] instruction_o
);

  //////////////// Including OPCODES ////////////////////////////
  `include "opcode.vh"
  //////////////////////////////
  //////////////////////////////// LOCAL INTERNAL SIGNALS////////////////////////////////////////////////////////////

  reg [31:0] immediate;
  reg        illegal_inst;
  reg [31:0] saved_inst;
  reg [31:0] saved_inst_pc;
  reg        saved_inst_valid;
  reg        drop_fetch_resp;
  reg [31:0] if_id_inst_reg;
  reg [31:0] if_id_pc_reg;
  wire [31:0] next_if_id_inst;
  wire [31:0] next_if_id_pc;
  wire        next_if_id_valid;
  wire [31:0] decode_inst;
  wire        drop_incoming_resp;
  wire        fetch_resp_valid;

  ////////////////////////////////////////////////////////////// IF stage////////////////////////////////////////////////////////////


  // TODO-1:
  // Implement IF-stage instruction selection.
  // - On stall_read_i = 1, insert a NOP
  // - Otherwise, pass instruction/data from instruction memory

  // If an IMEM response arrives while the pipeline is stalled, buffer it and
  // replay it once the stall clears so fetch data is never dropped.
  always @(posedge clk) begin
    if (!reset) begin
      saved_inst       <= NOP;
      saved_inst_pc    <= RESET;
      saved_inst_valid <= 1'b0;
      drop_fetch_resp  <= 1'b0;
      if_id_inst_reg   <= NOP;
      if_id_pc_reg     <= RESET;
    end else begin
      if (flush_i) begin
        saved_inst_valid <= 1'b0;
        drop_fetch_resp  <= 1'b1;
        if_id_inst_reg   <= NOP;
        if_id_pc_reg     <= RESET;
      end else begin
        if (drop_fetch_resp && inst_mem_is_valid) begin
          drop_fetch_resp <= 1'b0;
        end

        if (stall_read_i && fetch_resp_valid) begin
          saved_inst       <= inst_mem_read_data;
          saved_inst_pc    <= inst_fetch_pc;
          saved_inst_valid <= 1'b1;
        end else if (!stall_read_i && next_if_id_valid && saved_inst_valid) begin
          saved_inst_valid <= 1'b0;
        end

        if (!stall_read_i) begin
          if_id_inst_reg <= next_if_id_inst;
          if_id_pc_reg   <= next_if_id_pc;
        end
      end
    end
  end

  assign drop_incoming_resp = flush_i | drop_fetch_resp;
  assign fetch_resp_valid = inst_mem_is_valid & ~drop_incoming_resp;
  assign next_if_id_valid = saved_inst_valid | fetch_resp_valid;
  assign next_if_id_inst  = saved_inst_valid ? saved_inst :
                            fetch_resp_valid ? inst_mem_read_data :
                            NOP;
  assign next_if_id_pc    = saved_inst_valid ? saved_inst_pc : inst_fetch_pc;
  assign decode_inst = if_id_inst_reg;
  assign instruction_o = decode_inst;

  // ----------------------------------------------------
  // ADD THIS LINE
  // ----------------------------------------------------
  // Decode if instruction is an M-Extension operation
  wire is_m_ext = (decode_inst[`OPCODE] == ARITHR) && (decode_inst[31:25] == FUNCT7_M);

  ////////////////////////////////////////////////////////////// Exception detection////////////////////////////////////////////////////////////

  // TODO-2:
  // Assert exception when:
  // - illegal instruction is detected
  // - instruction fetch is misaligned (inst_mem_offset != 2'b00)

  always @(posedge clk) begin
    if (!reset) exception <= 1'b0;
    else if (illegal_inst || inst_mem_offset != 2'b00) exception <= 1'b1;
    else exception <= 1'b0;
  end

  ////////////////////////////////////////////////////////////// ID stage: immediate generation ///////////////////////////////////////////////////////////

  // Generate 32-bit immediates for:
  // JAL, JALR, BRANCH, LOAD, STORE, ARITH-I, LUI
  // For unsupported opcodes, set illegal_inst = 1
  //
  // Definitions:
  // - instruction_i[31] is the sign bit
  // - "Sign-extend" means: replicate instruction_i[31] to fill all unused MSBs
  // - The number of replicated bits is implied by the immediate bit ranges below
  // - All immediates must be exactly 32 bits wide

  always @(*) begin
    immediate    = 32'h0;
    illegal_inst = 1'b0;

    case (decode_inst[`OPCODE])
      // JALR:
      // Lower 12 bits  = instruction_i[31:20]
      // Upper 20 bits  = Sign-extend
      JALR: immediate = {{20{decode_inst[31]}}, decode_inst[31:20]};

      // BRANCH:
      // immediate[12]   = instruction_i[31]   (sign bit)
      // immediate[11]   = instruction_i[7]
      // immediate[10:5] = instruction_i[30:25]
      // immediate[4:1]  = instruction_i[11:8]
      // immediate[0]	= 1'b0
      // immediate[31:13]= Sign-extend
      BRANCH:
      immediate = {
        {20{decode_inst[31]}}, decode_inst[7], decode_inst[30:25], decode_inst[11:8], 1'b0
      };

      // LOAD:
      // Lower 12 bits  = instruction_i[31:20]
      // Upper 20 bits  = Sign-extend
      LOAD: immediate = {{20{decode_inst[31]}}, decode_inst[31:20]};

      // STORE:
      // Lower 5 bits   = instruction_i[11:7]
      // Next 7 bits	= instruction_i[31:25]
      // Upper 20 bits  = Sign-extend
      STORE: immediate = {{20{decode_inst[31]}}, decode_inst[31:25], decode_inst[11:7]};

      // ARITH-I:
      // If FUNC3 is SLL or SR:
      //   immediate[4:0]  = instruction_i[24:20]
      //   immediate[31:5] = 0
      // Else:
      //   Lower 12 bits  = instruction_i[31:20]
      //   Upper 20 bits  = Sign-extend
      ARITHI:
      immediate =
                 (decode_inst[`FUNC3] == SLL ||
                  decode_inst[`FUNC3] == SR)
                 ? {27'b0, decode_inst[24:20]}
                 : {{20{decode_inst[31]}}, decode_inst[31:20]};

      // ARITH-R:
      // No immediate
      ARITHR: immediate = 32'h0;

      // LUI:
      // Upper 20 bits = instruction_i[31:12]
      // Lower 12 bits = 0
      LUI: immediate = {decode_inst[31:12], 12'b0};

      // JAL:
      // immediate[20]	= instruction_i[31]   (sign bit)
      // immediate[19:12] = instruction_i[19:12]
      // immediate[11]	= instruction_i[20]
      // immediate[10:1]  = instruction_i[30:21]
      // immediate[0] 	= 1'b0
      // immediate[31:21] = Sign-extend
      JAL:
      immediate = {
        {12{decode_inst[31]}}, decode_inst[19:12], decode_inst[20], decode_inst[30:21], 1'b0
      };

      default: illegal_inst = 1'b1;
    endcase
  end

  ////////////////////////////////////////////////////////////// ID -> EX Register////////////////////////////////////////////////////////////

  // TODO-4:
  // Generate control signals based on opcode
  // alu, lui, jal, jalr, branch, mem_write, mem_to_reg, arithsubtype

  id_ex_reg u_id_ex (
      .clk    (clk),
      .reset  (reset),
      .stall_n(~stall_read_i),
      .bubble_i(bubble_id_ex_i),

      // From ID
      .immediate_i(immediate),
      .immediate_sel_i(
        (decode_inst[`OPCODE] == JALR)  || (decode_inst[`OPCODE] == LOAD)  ||
        (decode_inst[`OPCODE] == ARITHI)
    ),
      .alu_i((decode_inst[`OPCODE] == ARITHI) || (decode_inst[`OPCODE] == ARITHR)),
      .lui_i(decode_inst[`OPCODE] == LUI),
      .jal_i(decode_inst[`OPCODE] == JAL),
      .jalr_i(decode_inst[`OPCODE] == JALR),
      .branch_i(decode_inst[`OPCODE] == BRANCH),
      .mem_write_i(decode_inst[`OPCODE] == STORE),
      .mem_to_reg_i(decode_inst[`OPCODE] == LOAD),
      .arithsubtype_i (
        decode_inst[`SUBTYPE] &&
        !(decode_inst[`OPCODE] == ARITHI &&
          decode_inst[`FUNC3] == ADD)
    ),
      .pc_i(if_id_pc_reg),
      .src1_sel_i(decode_inst[`RS1]),
      .src2_sel_i(decode_inst[`RS2]),
      .dest_reg_sel_i(decode_inst[`RD]),
      .alu_op_i(decode_inst[`FUNC3]),
      .illegal_inst_i(illegal_inst),
      .is_m_ext_i(is_m_ext),         // <-- ADD THIS LINE (Input)

      // To EX (WIRES)
      .execute_immediate_o(execute_immediate_w),
      .immediate_sel_o    (immediate_sel_w),
      .alu_o              (alu_w),
      .lui_o              (lui_w),
      .jal_o              (jal_w),
      .jalr_o             (jalr_w),
      .branch_o           (branch_w),
      .mem_write_o        (mem_write_w),
      .mem_to_reg_o       (mem_to_reg_w),
      .arithsubtype_o     (arithsubtype_w),
      .pc_o               (pc_w),
      .src1_sel_o         (src1_select_w),
      .src2_sel_o         (src2_select_w),
      .dest_reg_sel_o     (dest_reg_sel_w),
      .alu_op_o           (alu_operation_w),
      .illegal_inst_o     (illegal_inst_w),
      .is_m_ext_o         (is_m_ext_w)      // <-- ADD THIS LINE (Output)
  );
endmodule