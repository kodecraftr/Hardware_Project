`timescale 1ns / 1ps

// ============================================================
//  bus_interconnect.v
//  Simple address-decoded bus for RISC-V SoC
//
//  Memory Map
//  ----------
//  0x0000_0000 - 0x0000_0FFF  : Instruction Memory (IMEM, 4 KB)
//  0x2000_0000 - 0x2000_0FFF  : Data Memory        (DMEM, 4 KB)
//  0x1000_0000 - 0x1000_000F  : UART Peripheral    (16 B)
//
//  Handshake (valid/ready)
//  -----------------------
//  Master drives valid + addr/wdata/we/wstrb.
//  Slave drives ready + rdata.
//  Transaction completes when valid & ready are both high.
//
//  Unmapped address handling
//  -------------------------
//  If the CPU accesses an address that does not belong to any
//  slave, the bus immediately acknowledges the transaction
//  (ready=1) and returns ERROR_RDATA (0xDEAD_BEEF) for reads.
//
//  Bug fixes applied (v2)
//  ----------------------
//  Bug 1: UART rdata is combinational but was sampled one cycle
//         late after addr changed. Fixed by registering rdata
//         in the same cycle as the request while addr is stable.
//  Bug 2: dmem_read_ready used live dmem_sel/uart_sel which
//         change when addr changes in cycle+1. Fixed by
//         registering the select signals alongside pending flags.
//  Bug 3: RX clear race in uart_peripheral - fixed there with
//         else-if priority (set beats clear).
// ============================================================

module bus_interconnect (
    input  wire        clk,
    input  wire        rst_n,

    // ---- CPU Instruction-fetch port (read-only) ----
    input  wire [31:0] imem_addr,
    input  wire        imem_valid,
    output wire [31:0] imem_rdata,
    output wire        imem_ready,

    // ---- CPU Data port (read + write) ----
    input  wire [31:0] dmem_raddr,
    input  wire [31:0] dmem_waddr,
    input  wire        dmem_we,
    input  wire [ 3:0] dmem_wstrb,
    input  wire [31:0] dmem_wdata,
    input  wire        dmem_read_valid,
    input  wire        dmem_write_valid,
    output wire [31:0] dmem_rdata,
    output wire        dmem_read_ready,
    output wire        dmem_write_ready,

    // ---- IMEM slave ----
    output wire [31:0] s_imem_addr,
    output wire        s_imem_en,
    input  wire [31:0] s_imem_rdata,

    // ---- DMEM slave ----
    output wire [31:0] s_dmem_raddr,
    output wire [31:0] s_dmem_waddr,
    output wire        s_dmem_re,
    output wire        s_dmem_we,
    output wire [ 3:0] s_dmem_wstrb,
    output wire [31:0] s_dmem_wdata,
    input  wire [31:0] s_dmem_rdata,

    // ---- UART slave ----
    output wire [31:0] s_uart_raddr,
    output wire [31:0] s_uart_waddr,
    output wire        s_uart_re,
    output wire        s_uart_we,
    output wire [31:0] s_uart_wdata,
    input  wire [31:0] s_uart_rdata,
    input  wire        s_uart_ready,

    // ---- Bus error indicator (pulses 1 cycle on unmapped access) ----
    output reg         bus_error
);

    // ----------------------------------------------------------
    //  Address decode constants
    // ----------------------------------------------------------
    localparam [31:0] IMEM_BASE  = 32'h0000_0000;
    localparam [31:0] IMEM_MASK  = 32'hFFFF_F000;
    localparam [31:0] DMEM_BASE  = 32'h2000_0000;
    localparam [31:0] DMEM_MASK  = 32'hFFFF_F000;
    localparam [31:0] UART_BASE  = 32'h1000_0000;
    localparam [31:0] UART_MASK  = 32'hFFFF_FFF0;
    localparam [31:0] ERROR_RDATA = 32'hDEAD_BEEF;

    // ----------------------------------------------------------
    //  Instruction-fetch decode (IMEM port)
    // ----------------------------------------------------------
    wire imem_sel = ((imem_addr & IMEM_MASK) == (IMEM_BASE & IMEM_MASK));

    assign s_imem_addr = imem_addr;
    assign s_imem_en   = imem_valid & imem_sel;

    // IMEM is synchronous block RAM - 1-cycle latency
    reg imem_pending;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) imem_pending <= 1'b0;
        else        imem_pending <= s_imem_en;

    assign imem_rdata = imem_pending ? s_imem_rdata : ERROR_RDATA;
    assign imem_ready = imem_pending & imem_sel;

    // ----------------------------------------------------------
    //  Data-bus combinational address decode
    // ----------------------------------------------------------
    wire dmem_read_sel      = ((dmem_raddr & DMEM_MASK) == (DMEM_BASE & DMEM_MASK));
    wire uart_read_sel      = ((dmem_raddr & UART_MASK) == (UART_BASE & UART_MASK));
    wire unmapped_read_addr = ~(dmem_read_sel | uart_read_sel);
    wire dmem_write_sel      = ((dmem_waddr & DMEM_MASK) == (DMEM_BASE & DMEM_MASK));
    wire uart_write_sel      = ((dmem_waddr & UART_MASK) == (UART_BASE & UART_MASK));
    wire unmapped_write_addr = ~(dmem_write_sel | uart_write_sel);

    // ----------------------------------------------------------
    //  DMEM slave wiring
    // ----------------------------------------------------------
    assign s_dmem_raddr = dmem_raddr;
    assign s_dmem_waddr = dmem_waddr;
    assign s_dmem_re    = dmem_read_valid  & dmem_read_sel;
    assign s_dmem_we    = dmem_write_valid & dmem_write_sel;
    assign s_dmem_wstrb = dmem_wstrb;
    assign s_dmem_wdata = dmem_wdata;

    // ----------------------------------------------------------
    //  UART slave wiring
    // ----------------------------------------------------------
    assign s_uart_raddr = dmem_raddr;
    assign s_uart_waddr = dmem_waddr;
    assign s_uart_re    = dmem_read_valid  & uart_read_sel;
    assign s_uart_we    = dmem_write_valid & uart_write_sel;
    assign s_uart_wdata = dmem_wdata;

    // ----------------------------------------------------------
    //  Registered pipeline stage
    //
    //  All pending flags AND their corresponding select signals
    //  are registered together in cycle 0 (when addr is stable).
    //  This means in cycle 1 (when ready fires) the correct
    //  select and data are available regardless of what addr is.
    //
    //  UART rdata is also captured in cycle 0 because the
    //  peripheral's read path is purely combinational - it depends
    //  on addr[3:0] which is only valid in cycle 0.
    // ----------------------------------------------------------
    reg        dmem_read_pending;
    reg        uart_read_pending;
    reg        unmap_read_pending;
    reg        dmem_sel_reg;       // registered copy of dmem_read_sel (cycle 0)
    reg        uart_sel_reg;       // registered copy of uart_read_sel (cycle 0)
    reg [31:0] uart_rdata_reg;     // captured UART rdata (cycle 0)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmem_read_pending  <= 1'b0;
            uart_read_pending  <= 1'b0;
            unmap_read_pending <= 1'b0;
            dmem_sel_reg       <= 1'b0;
            uart_sel_reg       <= 1'b0;
            uart_rdata_reg     <= 32'h0;
        end else begin
            // Pending flags
            dmem_read_pending  <= s_dmem_re;
            uart_read_pending  <= s_uart_re;
            unmap_read_pending <= dmem_read_valid & unmapped_read_addr;

            // Register select signals so ready is stable in cycle 1
            dmem_sel_reg       <= dmem_read_sel;
            uart_sel_reg       <= uart_read_sel;

            // Capture UART combinational rdata while addr is still valid
            // (s_uart_rdata is driven by addr[3:0] inside the peripheral)
            if (s_uart_re)
                uart_rdata_reg <= s_uart_rdata;
        end
    end

    // ----------------------------------------------------------
    //  Read-data mux - uses registered copies, not live signals
    // ----------------------------------------------------------
    assign dmem_rdata =
        dmem_read_pending  ? s_dmem_rdata  :   // DMEM: rdata is stable (BRAM output reg)
        uart_read_pending  ? uart_rdata_reg :   // UART: registered capture from cycle 0
        s_uart_re          ? s_uart_rdata  :   // also expose same-cycle UART read data
                             ERROR_RDATA;       // unmapped or idle

    // ----------------------------------------------------------
    //  Read ready - uses registered selects so it is stable
    //  in cycle 1 regardless of what addr is doing
    // ----------------------------------------------------------
    assign dmem_read_ready =
        (dmem_read_pending  & dmem_sel_reg) |   // DMEM read complete
        (uart_read_pending  & uart_sel_reg) |   // UART read complete
        unmap_read_pending;                     // unmapped: ack with sentinel

    // ----------------------------------------------------------
    //  Write ready - combinational, addr is still stable
    // ----------------------------------------------------------
    assign dmem_write_ready =
        (dmem_write_valid & dmem_write_sel)      ? 1'b1         :
        (dmem_write_valid & uart_write_sel)      ? s_uart_ready :
        (dmem_write_valid & unmapped_write_addr) ? 1'b1         :
                                             1'b0;

    // ----------------------------------------------------------
    //  Bus error - pulses 1 cycle on any unmapped access
    // ----------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bus_error <= 1'b0;
        else
            bus_error <= (dmem_read_valid  & unmapped_read_addr) |
                         (dmem_write_valid & unmapped_write_addr);
    end

endmodule
