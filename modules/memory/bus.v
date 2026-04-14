`timescale 1ns / 1ps

// ============================================================
//  bus_interconnect.v (Day 1 - Basic Version)
//  Simple address decoding + routing (no pipelining)
// ============================================================

module bus_interconnect (
    input  wire        clk,
    input  wire        rst_n,

    // ---- CPU Instruction-fetch port ----
    input  wire [31:0] imem_addr,
    input  wire        imem_valid,
    output wire [31:0] imem_rdata,
    output wire        imem_ready,

    // ---- CPU Data port ----
    input  wire [31:0] dmem_raddr,
    input  wire [31:0] dmem_waddr,
    input  wire        dmem_we,
    input  wire [ 3:0] dmem_wstrb,
    input  wire [31:0] dmem_wdata,
    input  wire        dmem_read_valid,
    input  wire        dmem_write_valid,
    output reg  [31:0] dmem_rdata,
    output reg         dmem_read_ready,
    output reg         dmem_write_ready,

    // ---- IMEM ----
    output wire [31:0] s_imem_addr,
    output wire        s_imem_en,
    input  wire [31:0] s_imem_rdata,

    // ---- DMEM ----
    output wire [31:0] s_dmem_raddr,
    output wire [31:0] s_dmem_waddr,
    output wire        s_dmem_re,
    output wire        s_dmem_we,
    output wire [ 3:0] s_dmem_wstrb,
    output wire [31:0] s_dmem_wdata,
    input  wire [31:0] s_dmem_rdata,

    // ---- UART ----
    output wire [31:0] s_uart_raddr,
    output wire [31:0] s_uart_waddr,
    output wire        s_uart_re,
    output wire        s_uart_we,
    output wire [31:0] s_uart_wdata,
    input  wire [31:0] s_uart_rdata,
    input  wire        s_uart_ready
);

    // ----------------------------------------------------------
    // Address Map
    // ----------------------------------------------------------
    localparam IMEM_BASE = 32'h0000_0000;
    localparam IMEM_MASK = 32'hFFFF_F000;

    localparam DMEM_BASE = 32'h2000_0000;
    localparam DMEM_MASK = 32'hFFFF_F000;

    localparam UART_BASE = 32'h1000_0000;
    localparam UART_MASK = 32'hFFFF_FFF0;

    localparam ERROR_RDATA = 32'hDEAD_BEEF;

    // ----------------------------------------------------------
    // IMEM
    // ----------------------------------------------------------
    wire imem_sel = ((imem_addr & IMEM_MASK) == IMEM_BASE);

    assign s_imem_addr = imem_addr;
    assign s_imem_en   = imem_valid & imem_sel;

    assign imem_rdata = imem_sel ? s_imem_rdata : ERROR_RDATA;
    assign imem_ready = imem_valid;

    // ----------------------------------------------------------
    // DMEM / UART decode
    // ----------------------------------------------------------
    wire dmem_read_sel  = ((dmem_raddr & DMEM_MASK) == DMEM_BASE);
    wire uart_read_sel  = ((dmem_raddr & UART_MASK) == UART_BASE);

    wire dmem_write_sel = ((dmem_waddr & DMEM_MASK) == DMEM_BASE);
    wire uart_write_sel = ((dmem_waddr & UART_MASK) == UART_BASE);

    // ----------------------------------------------------------
    // Slave connections
    // ----------------------------------------------------------
    assign s_dmem_raddr = dmem_raddr;
    assign s_dmem_waddr = dmem_waddr;
    assign s_dmem_re    = dmem_read_valid  & dmem_read_sel;
    assign s_dmem_we    = dmem_write_valid & dmem_write_sel;
    assign s_dmem_wstrb = dmem_wstrb;
    assign s_dmem_wdata = dmem_wdata;

    assign s_uart_raddr = dmem_raddr;
    assign s_uart_waddr = dmem_waddr;
    assign s_uart_re    = dmem_read_valid  & uart_read_sel;
    assign s_uart_we    = dmem_write_valid & uart_write_sel;
    assign s_uart_wdata = dmem_wdata;

    // ----------------------------------------------------------
    // Read Logic (simple combinational)
    // ----------------------------------------------------------
    always @(*) begin
        dmem_rdata       = ERROR_RDATA;
        dmem_read_ready  = 1'b0;
        dmem_write_ready = 1'b0;

        // READ
        if (dmem_read_valid) begin
            if (dmem_read_sel) begin
                dmem_rdata      = s_dmem_rdata;
                dmem_read_ready = 1'b1;
            end else if (uart_read_sel) begin
                dmem_rdata      = s_uart_rdata;
                dmem_read_ready = 1'b1;
            end else begin
                dmem_rdata      = ERROR_RDATA;
                dmem_read_ready = 1'b1;
            end
        end

        // WRITE
        if (dmem_write_valid) begin
            if (dmem_write_sel) begin
                dmem_write_ready = 1'b1;
            end else if (uart_write_sel) begin
                dmem_write_ready = s_uart_ready;
            end else begin
                dmem_write_ready = 1'b1;
            end
        end
    end

endmodule