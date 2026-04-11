`timescale 1ns / 1ps

module IF_ID #(
    parameter [31:0] RESET = 32'h0000_0000
) (
    input      clk,
    input      reset,
    input      stall,            // Global Pipeline Stall
    output reg exception,

    // IMEM interface
    input [31:0] inst_mem_read_data,

    // Pipe/Fetch Signals
    input [31:0] inst_fetch_pc,  // The PC associated with the current instruction

    // WB-stage signals (For Register File Writing)
    input        wb_regwrite,    // High if the WB stage is writing to a register
    input [ 4:0] wb_dest_reg_sel,
    input [31:0] wb_data_to_write,

    // Outputs to EX Stage
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
    output        m_extension_sel_w, // NEW: Signal for MUL/DIV unit
    output [31:0] pc_w,
    output [31:0] reg_rdata1_w,      // NEW: Actual data from registers
    output [31:0] reg_rdata2_w,      // NEW: Actual data from registers
    output [ 4:0] dest_reg_sel_w,
    output [ 2:0] alu_operation_w,
    output        illegal_inst_w
);

  `include "opcode.vh"

  // Internal Wires for Decoder
  reg [31:0] immediate;
  reg        illegal_inst;
  wire [31:0] rf_rdata1, rf_rdata2;

  // --------------------------------------------------------------------------
  // 1. REGISTER FILE INSTANTIATION
  // --------------------------------------------------------------------------
  // We place the RF here so data is ready for the ID/EX register
  regfile rf (
      .clk(clk),
      .we(wb_regwrite),
      .rs1(inst_mem_read_data[19:15]),
      .rs2(inst_mem_read_data[24:20]),
      .rd(wb_dest_reg_sel),
      .wdata(wb_data_to_write),
      .rdata1(rf_rdata1),
      .rdata2(rf_rdata2)
  );

  // --------------------------------------------------------------------------
  // 2. DECODER & IMMEDIATE GENERATION
  // -------------------------------------------------------------------------- 

  // --------------------------------------------------------------------------
  // 2. DECODER & IMMEDIATE GENERATION
  // --------------------------------------------------------------------------
  always @(*) begin
    immediate    = 32'h0;
    illegal_inst = 1'b0;

    case (inst_mem_read_data[`OPCODE])
      JALR:   immediate = {{20{inst_mem_read_data[31]}}, inst_mem_read_data[31:20]};
      LOAD:   immediate = {{20{inst_mem_read_data[31]}}, inst_mem_read_data[31:20]};
      STORE:  immediate = {{20{inst_mem_read_data[31]}}, inst_mem_read_data[31:25], inst_mem_read_data[11:7]};
      LUI:    immediate = {inst_mem_read_data[31:12], 12'b0};
      
      BRANCH: immediate = {{20{inst_mem_read_data[31]}}, inst_mem_read_data[7], inst_mem_read_data[30:25], inst_mem_read_data[11:8], 1'b0};
      
      JAL:    immediate = {{12{inst_mem_read_data[31]}}, inst_mem_read_data[19:12], inst_mem_read_data[20], inst_mem_read_data[30:21], 1'b0};
      
      ARITHI: immediate = (inst_mem_read_data[`FUNC3] == SLL || inst_mem_read_data[`FUNC3] == SR)
                          ? {27'b0, inst_mem_read_data[24:20]}
                          : {{20{inst_mem_read_data[31]}}, inst_mem_read_data[31:20]};
      
      ARITHR: immediate = 32'h0; // R-types have no immediate
      
      default: illegal_inst = 1'b1;
    endcase
  end

  // --------------------------------------------------------------------------
  // 3. ID -> EX PIPELINE REGISTER
  // --------------------------------------------------------------------------

  // --------------------------------------------------------------------------
  // 3. ID -> EX PIPELINE REGISTER
  // --------------------------------------------------------------------------
  id_ex_reg u_id_ex (
      .clk(clk),
      .reset(reset),
      .stall(stall),

      // Control Signals
      .immediate_sel_i( (inst_mem_read_data[`OPCODE] == JALR) || (inst_mem_read_data[`OPCODE] == LOAD) || (inst_mem_read_data[`OPCODE] == ARITHI) || (inst_mem_read_data[`OPCODE] == STORE) ),
      .alu_i( (inst_mem_read_data[`OPCODE] == ARITHI) || (inst_mem_read_data[`OPCODE] == ARITHR) ),
      .lui_i(inst_mem_read_data[`OPCODE] == LUI),
      .jal_i(inst_mem_read_data[`OPCODE] == JAL),
      .jalr_i(inst_mem_read_data[`OPCODE] == JALR),
      .branch_i(inst_mem_read_data[`OPCODE] == BRANCH),
      .mem_write_i(inst_mem_read_data[`OPCODE] == STORE),
      .mem_to_reg_i(inst_mem_read_data[`OPCODE] == LOAD),
      
      // M-EXTENSION DETECTION: 
      // In RISC-V, M-extension uses the same opcode as ARITHR, but funct7 is 7'b0000001
      .m_extension_sel_i( (inst_mem_read_data[`OPCODE] == ARITHR) && (inst_mem_read_data[31:25] == 7'b0000001) ),
      
      // ARITHR only: bit 30 is subtype (ADD vs SUB, SRL vs SRA)
      // For ARITHI, bit 30 is part of the immediate value, NOT subtype
      .arithsubtype_i( inst_mem_read_data[30] && (inst_mem_read_data[`OPCODE] == ARITHR) ),
      
      // Data Signals
      .pc_i(inst_fetch_pc),
      .immediate_i(immediate),
      .reg_rdata1_i(rf_rdata1),
      .reg_rdata2_i(rf_rdata2),
      .dest_reg_sel_i(inst_mem_read_data[`RD]),
      .alu_op_i(inst_mem_read_data[`FUNC3]),
      .illegal_inst_i(illegal_inst),

      // To EX stage outputs
      .pc_o(pc_w),
      .execute_immediate_o(execute_immediate_w),
      .reg_rdata1_o(reg_rdata1_w),
      .reg_rdata2_o(reg_rdata2_w),
      .dest_reg_sel_o(dest_reg_sel_w),
      .alu_op_o(alu_operation_w),
      .immediate_sel_o(immediate_sel_w),
      .alu_o(alu_w),
      .lui_o(lui_w),
      .jal_o(jal_w),
      .jalr_o(jalr_w),
      .branch_o(branch_w),
      .mem_write_o(mem_write_w),
      .mem_to_reg_o(mem_to_reg_w),
      .arithsubtype_o(arithsubtype_w),
      .m_extension_sel_o(m_extension_sel_w),
      .illegal_inst_o(illegal_inst_w)
  );

endmodule

////////////////////////////////////////////////////////////// ID -> EX register module////////////////////////////////////////////////////////////

module id_ex_reg (
    input clk,
    input reset,
    input stall, // FIXED: Renamed for clarity, active high

    // Inputs from ID
    input [31:0] immediate_i,
    input        immediate_sel_i,
    input        alu_i,
    input        lui_i,
    input        jal_i,
    input        jalr_i,
    input        branch_i,
    input        mem_write_i,
    input        mem_to_reg_i,
    input        m_extension_sel_i,
    input        arithsubtype_i,
    input [31:0] pc_i,
    input [31:0] reg_rdata1_i,
    input [31:0] reg_rdata2_i,
    input [ 4:0] dest_reg_sel_i,
    input [ 2:0] alu_op_i,
    input        illegal_inst_i,

    // Outputs to EX
    output reg [31:0] execute_immediate_o,
    output reg        immediate_sel_o,
    output reg        alu_o,
    output reg        lui_o,
    output reg        jal_o,
    output reg        jalr_o,
    output reg        branch_o,
    output reg        mem_write_o,
    output reg        mem_to_reg_o,
    output reg        m_extension_sel_o,
    output reg        arithsubtype_o,
    output reg [31:0] pc_o,
    output reg [31:0] reg_rdata1_o,
    output reg [31:0] reg_rdata2_o,
    output reg [ 4:0] dest_reg_sel_o,
    output reg [ 2:0] alu_op_o,
    output reg        illegal_inst_o
);

  always @(posedge clk or negedge reset) begin
    if (!reset) begin
      execute_immediate_o <= 32'h0;
      immediate_sel_o     <= 1'b0;
      alu_o               <= 1'b0;
      lui_o               <= 1'b0;
      jal_o               <= 1'b0;
      jalr_o              <= 1'b0;
      branch_o            <= 1'b0;
      mem_write_o         <= 1'b0;
      mem_to_reg_o        <= 1'b0;
      m_extension_sel_o   <= 1'b0;
      arithsubtype_o      <= 1'b0;
      pc_o                <= 32'h0;
      reg_rdata1_o        <= 32'h0;
      reg_rdata2_o        <= 32'h0;
      dest_reg_sel_o      <= 5'h0;
      alu_op_o            <= 3'h0;
      illegal_inst_o      <= 1'b0;
    end else if (!stall) begin  // FIXED: Only updates when NOT stalled
      execute_immediate_o <= immediate_i;
      immediate_sel_o     <= immediate_sel_i;
      alu_o               <= alu_i;
      lui_o               <= lui_i;
      jal_o               <= jal_i;
      jalr_o              <= jalr_i;
      branch_o            <= branch_i;
      mem_write_o         <= mem_write_i;
      mem_to_reg_o        <= mem_to_reg_i;
      m_extension_sel_o   <= m_extension_sel_i;
      arithsubtype_o      <= arithsubtype_i;
      pc_o                <= pc_i;
      reg_rdata1_o        <= reg_rdata1_i;
      reg_rdata2_o        <= reg_rdata2_i;
      dest_reg_sel_o      <= dest_reg_sel_i;
      alu_op_o            <= alu_op_i;
      illegal_inst_o      <= illegal_inst_i;
    end
  end

endmodule