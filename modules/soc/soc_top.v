`timescale 1ns / 1ps

// ============================================================
//  soc_top.v
//  RISC-V 32IM SoC - Top-level integration
//
//  Components
//  ----------
//  • pipe        - 5-stage RISC-V 32IM pipeline
//  • instr_mem   - Synchronous block-RAM instruction memory (IMEM)
//  • data_mem    - Synchronous block-RAM data memory (DMEM)
//  • uart_peripheral - Memory-mapped UART (TX + RX)
//  • bus_interconnect - Address decode + valid/ready handshake
//
//  Memory Map
//  ----------
//  0x0000_0000 - 0x0000_0FFF  IMEM (4 KB)
//  0x2000_0000 - 0x2000_0FFF  DMEM (4 KB)
//  0x1000_0000 - 0x1000_000F  UART registers
// ============================================================

`include "opcode.vh"

module soc_top #(
    parameter [31:0] RESET_ADDR   = 32'h0000_0000,
    parameter        HALT_ON_ZERO = 1'b0,
    parameter        SYS_CLK_FREQ = 100_000_000,
    parameter        BAUD_RATE    = 115_200
)(
    input  wire clk,
    input  wire rst_n,      // active-low reset (board button)

    // UART physical pins
    input  wire uart_rx,
    output wire uart_tx,

    // Optional debug / status LEDs
    output wire [15:0] dbg_leds
);
    // The CPU pipeline treats reset as an active-low run enable:
    //   0 = reset/clear state
    //   1 = normal execution
    wire reset = rst_n;

    // ----------------------------------------------------------
    //  CPU ↔ Bus wires (instruction fetch port)
    // ----------------------------------------------------------
    wire [31:0] cpu_imem_addr;
    wire        cpu_imem_valid;
    wire [31:0] cpu_imem_rdata;
    wire        cpu_imem_ready;

    // ----------------------------------------------------------
    //  CPU ↔ Bus wires (data port)
    // ----------------------------------------------------------
    wire [31:0] cpu_dmem_raddr;
    wire        cpu_dmem_re;          // read enable (mem_to_reg)
    wire [31:0] cpu_dmem_rdata;
    wire        cpu_dmem_rvalid;      // bus: read data valid

    wire [31:0] cpu_dmem_waddr;
    wire        cpu_dmem_we;          // write enable
    wire [31:0] cpu_dmem_wdata;
    wire [ 3:0] cpu_dmem_wstrb;
    wire        cpu_dmem_wvalid;      // bus: write accepted
    // ----------------------------------------------------------
    //  Bus ↔ IMEM slave
    // ----------------------------------------------------------
    wire [31:0] s_imem_addr;
    wire        s_imem_en;
    wire [31:0] s_imem_rdata;

    // ----------------------------------------------------------
    //  Bus ↔ DMEM slave
    // ----------------------------------------------------------
    wire [31:0] s_dmem_raddr;
    wire [31:0] s_dmem_waddr;
    wire        s_dmem_re;
    wire        s_dmem_we;
    wire [ 3:0] s_dmem_wstrb;
    wire [31:0] s_dmem_wdata;
    wire [31:0] s_dmem_rdata;

    // ----------------------------------------------------------
    //  Bus ↔ UART peripheral slave
    // ----------------------------------------------------------
    wire [31:0] s_uart_raddr;
    wire [31:0] s_uart_waddr;
    wire        s_uart_re;
    wire        s_uart_we;
    wire [31:0] s_uart_wdata;
    wire [31:0] s_uart_rdata;
    wire        s_uart_ready;
    wire        bus_error;

    // ----------------------------------------------------------
    //  CPU pipeline stall
    //  Stall when the bus isn't ready (e.g. UART busy).
    //  Currently the memories are 1-cycle latency so no stall needed
    //  from DMEM; UART peripheral always acknowledges in 1 cycle.
    // ----------------------------------------------------------
    // Stall if IMEM requests an instruction but it isn't ready, OR 
// if DMEM is reading/writing but hasn't received an ack.
wire imem_stall = cpu_imem_valid & ~cpu_imem_ready;
wire dmem_stall =
    (cpu_dmem_re && !cpu_dmem_rvalid) ||
    (cpu_dmem_we && !cpu_dmem_wvalid);

wire cpu_stall = imem_stall | dmem_stall;
wire cpu_exception;
wire [31:0] cpu_pc_debug;
wire mext_event_valid;

    // ----------------------------------------------------------
    //  CPU instantiation
    // ----------------------------------------------------------
    pipe #(
        .RESET(RESET_ADDR),
        .HALT_ON_ZERO(HALT_ON_ZERO)
    ) cpu (
        .clk     (clk),
        .reset   (reset),
        .imem_stall_i(imem_stall),
        .dmem_stall_i(dmem_stall),

        // Exception / PC debug
        .exception (cpu_exception),
        .pc_out    (cpu_pc_debug),

        // Instruction memory port
        .inst_mem_address   (cpu_imem_addr),
        .inst_mem_is_valid  (cpu_imem_ready),   // bus says data is valid
        .inst_mem_read_data (cpu_imem_rdata),
        .inst_mem_is_ready  (cpu_imem_valid),   // CPU says it wants an instruction

        // Data memory - read
        .dmem_read_address   (cpu_dmem_raddr),
        .dmem_read_ready     (cpu_dmem_re),
        .dmem_read_data_temp (cpu_dmem_rdata),
        .dmem_read_valid     (cpu_dmem_rvalid),

        // Data memory - write
        .dmem_write_address (cpu_dmem_waddr),
        .dmem_write_ready   (cpu_dmem_we),
        .dmem_write_data    (cpu_dmem_wdata),
        .dmem_write_byte    (cpu_dmem_wstrb),
        .dmem_write_valid   (cpu_dmem_wvalid),

        // M-extension event (unused at SoC level; tie off)
            .mext_event_valid       (mext_event_valid),
            .mext_event_func3       (),
            .mext_event_operand1    (),
        .mext_event_operand2    (),
        .mext_event_result      (),
        .mext_event_pc          (),
        .mext_event_rd          (),
        .mext_event_unit_cycles (),
        .mext_event_total_cycles()
    );

    // ----------------------------------------------------------
    //  Bus interconnect
    // ----------------------------------------------------------
    bus_interconnect bus (
        .clk  (clk),
        .rst_n(rst_n),

        // CPU instruction fetch port
        .imem_addr  (cpu_imem_addr),
        .imem_valid (cpu_imem_valid),
        .imem_rdata (cpu_imem_rdata),
        .imem_ready (cpu_imem_ready),

        // CPU data port
        .dmem_raddr       (cpu_dmem_raddr),
        .dmem_waddr       (cpu_dmem_waddr),
        .dmem_we          (cpu_dmem_we),
        .dmem_wstrb       (cpu_dmem_wstrb),
        .dmem_wdata       (cpu_dmem_wdata),
        .dmem_read_valid  (cpu_dmem_re),
        .dmem_write_valid (cpu_dmem_we),
        .dmem_rdata       (cpu_dmem_rdata),
        .dmem_read_ready  (cpu_dmem_rvalid),
        .dmem_write_ready (cpu_dmem_wvalid),

        // IMEM slave
        .s_imem_addr  (s_imem_addr),
        .s_imem_en    (s_imem_en),
        .s_imem_rdata (s_imem_rdata),

        // DMEM slave
        .s_dmem_raddr (s_dmem_raddr),
        .s_dmem_waddr (s_dmem_waddr),
        .s_dmem_re    (s_dmem_re),
        .s_dmem_we    (s_dmem_we),
        .s_dmem_wstrb (s_dmem_wstrb),
        .s_dmem_wdata (s_dmem_wdata),
        .s_dmem_rdata (s_dmem_rdata),

        // UART slave
        .s_uart_raddr (s_uart_raddr),
        .s_uart_waddr (s_uart_waddr),
        .s_uart_re    (s_uart_re),
        .s_uart_we    (s_uart_we),
        .s_uart_wdata (s_uart_wdata),
        .s_uart_rdata (s_uart_rdata),
        .s_uart_ready (s_uart_ready),
        .bus_error    (bus_error)
    );

    // ----------------------------------------------------------
    //  Instruction Memory (IMEM)
    // ----------------------------------------------------------
    instr_mem u_imem (
        .clk  (clk),
        .pc   (s_imem_addr),
        .instr(s_imem_rdata)
    );

    // ----------------------------------------------------------
    //  Data Memory (DMEM)
    // ----------------------------------------------------------
    data_mem u_dmem (
        .clk  (clk),
        .re   (s_dmem_re),
        .raddr(s_dmem_raddr),
        .rdata(s_dmem_rdata),
        .we   (s_dmem_we),
        .waddr(s_dmem_waddr),
        .wdata(s_dmem_wdata),
        .wstrb(s_dmem_wstrb)
    );

    // ----------------------------------------------------------
    //  UART Peripheral
    // ----------------------------------------------------------
    uart_peripheral #(
        .SYS_CLK_FREQ(SYS_CLK_FREQ),
        .BAUD_RATE   (BAUD_RATE)
    ) u_uart (
        .clk    (clk),
        .rst_n  (rst_n),
        .raddr  (s_uart_raddr),
        .waddr  (s_uart_waddr),
        .we     (s_uart_we),
        .re     (s_uart_re),
        .wdata  (s_uart_wdata),
        .rdata  (s_uart_rdata),
        .ready  (s_uart_ready),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx)
    );

    // ----------------------------------------------------------
    //  Debug LEDs (heartbeat + reset indicator)
    // ----------------------------------------------------------
    reg [25:0] heartbeat_cnt;
    reg [23:0] uart_led_hold;
    reg [23:0] imem_stall_hold;
    reg [23:0] dmem_stall_hold;
    reg [23:0] stall_hold;
    reg [23:0] mext_hold;
    reg [23:0] uart_rx_hold;
    reg [23:0] fetch_hold;
    reg [23:0] dread_hold;
    reg [23:0] dwrite_hold;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) heartbeat_cnt <= 26'd0;
        else        heartbeat_cnt <= heartbeat_cnt + 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_led_hold <= 24'd0;
            imem_stall_hold <= 24'd0;
            dmem_stall_hold <= 24'd0;
            stall_hold <= 24'd0;
            mext_hold <= 24'd0;
            uart_rx_hold <= 24'd0;
            fetch_hold <= 24'd0;
            dread_hold <= 24'd0;
            dwrite_hold <= 24'd0;
        end else begin
            if (s_uart_we)
                uart_led_hold <= 24'd8_000_000;
            else if (uart_led_hold != 24'd0)
                uart_led_hold <= uart_led_hold - 1'b1;

            if (imem_stall)
                imem_stall_hold <= 24'd8_000_000;
            else if (imem_stall_hold != 24'd0)
                imem_stall_hold <= imem_stall_hold - 1'b1;

            if (dmem_stall)
                dmem_stall_hold <= 24'd8_000_000;
            else if (dmem_stall_hold != 24'd0)
                dmem_stall_hold <= dmem_stall_hold - 1'b1;

            if (cpu_stall)
                stall_hold <= 24'd8_000_000;
            else if (stall_hold != 24'd0)
                stall_hold <= stall_hold - 1'b1;

            if (mext_event_valid)
                mext_hold <= 24'd8_000_000;
            else if (mext_hold != 24'd0)
                mext_hold <= mext_hold - 1'b1;

            if (s_uart_re)
                uart_rx_hold <= 24'd8_000_000;
            else if (uart_rx_hold != 24'd0)
                uart_rx_hold <= uart_rx_hold - 1'b1;

            if (cpu_imem_valid)
                fetch_hold <= 24'd8_000_000;
            else if (fetch_hold != 24'd0)
                fetch_hold <= fetch_hold - 1'b1;

            if (cpu_dmem_re)
                dread_hold <= 24'd8_000_000;
            else if (dread_hold != 24'd0)
                dread_hold <= dread_hold - 1'b1;

            if (cpu_dmem_we)
                dwrite_hold <= 24'd8_000_000;
            else if (dwrite_hold != 24'd0)
                dwrite_hold <= dwrite_hold - 1'b1;
        end
    end

    assign dbg_leds[0]  = heartbeat_cnt[25];
    assign dbg_leds[1]  = rst_n;
    assign dbg_leds[2]  = (uart_led_hold != 24'd0);
    assign dbg_leds[3]  = (uart_rx_hold != 24'd0);
    assign dbg_leds[4]  = (imem_stall_hold != 24'd0);
    assign dbg_leds[5]  = (dmem_stall_hold != 24'd0);
    assign dbg_leds[6]  = (stall_hold != 24'd0);
    assign dbg_leds[7]  = cpu_exception;
    assign dbg_leds[8]  = (fetch_hold != 24'd0);
    assign dbg_leds[9]  = (dread_hold != 24'd0);
    assign dbg_leds[10] = (dwrite_hold != 24'd0);
    assign dbg_leds[11] = bus_error;
    assign dbg_leds[12] = cpu_pc_debug[2];
    assign dbg_leds[13] = cpu_pc_debug[3];
    assign dbg_leds[14] = cpu_pc_debug[4];
    assign dbg_leds[15] = (mext_hold != 24'd0);

endmodule
