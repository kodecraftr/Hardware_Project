`timescale 1ns / 1ps

// ============================================================
//  fpga_top.v
//  FPGA wrapper for RISC-V 32IM SoC
//
//  Target : Xilinx Artix-7 (Basys3 / Arty A7-35T / A7-100T)
//  Clock  : 100 MHz on-board oscillator
//  UART   : 115200 8N1
//
//  Pinout is set in constraints.xdc.
// ============================================================

module fpga_top (
    // Board oscillator
    input  wire CLK100MHZ,        // 100 M   Hz on Basys3/Arty A7

    // Active-low reset (push-button)
    input  wire CPU_RESETN,     // BTN0 on Arty A7; btnC on Basys3 (see XDC)

    // UART
    input  wire UART_RXD_OUT,   // USB-UART RX (board → FPGA)
    output wire UART_TXD_IN,    // USB-UART TX (FPGA → board)

    // LEDs
    output wire [15:0] led      // LD0-LD15
);

    // ----------------------------------------------------------
    //  Divide the 100 MHz board clock to 50 MHz for the SoC.
    //  This keeps timing closure comfortable on the FPGA.
    // ----------------------------------------------------------
    reg clk_div2 = 1'b0;
    always @(posedge CLK100MHZ)
        clk_div2 <= ~clk_div2;
        
        

`ifdef SYNTHESIS
    wire clk_sys;
    BUFG u_clk_bufg (
        .I(clk_div2),
        .O(clk_sys)
        
    );
`else

    wire clk_sys = clk_div2;
`endif

    // ----------------------------------------------------------
    //  SoC instantiation
    // ----------------------------------------------------------
    soc_top #(
        .RESET_ADDR  (32'h0000_0000),
        .SYS_CLK_FREQ(50_000_000),
        .BAUD_RATE   (115200)
    ) u_soc (
        .clk     (clk_sys),
        .rst_n   (CPU_RESETN),
        .uart_rx (UART_RXD_OUT),
        .uart_tx (UART_TXD_IN),
        .dbg_leds(led)
    );

endmodule
