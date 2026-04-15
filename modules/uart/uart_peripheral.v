module uart_peripheral #(
    parameter SYS_CLK_FREQ = 100_000_000,
    parameter BAUD_RATE    = 115_200
)(
    input  wire        clk,
    input  wire        rst_n,

    // Bus slave interface
    input  wire [31:0] raddr, 
    input  wire [31:0] waddr,
    input  wire        we,
    input  wire        re,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    output wire        ready,

    // Physical UART pins
    input  wire        uart_rx,
    output wire        uart_tx
);

    localparam CLKS_PER_BIT = SYS_CLK_FREQ / BAUD_RATE;
    
    // Internal Control Wires
    wire uart_tx_rst_n, uart_rx_rst_n;
    wire [7:0] rx_data_w;
    wire rx_valid_w;
    reg  tx_start;
    reg [7:0] tx_data_reg;
    wire tx_busy;

    assign uart_tx_rst_n = rst_n && !control_rst_tx;
    assign uart_rx_rst_n = rst_n && !control_rst_rx;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .rst_n(uart_tx_rst_n), .tx_start(tx_start),
        .tx_data(tx_data_reg), .tx(uart_tx), .tx_busy(tx_busy)
    );

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk), .rst_n(uart_rx_rst_n), .rx(uart_rx),
        .rx_data(rx_data_w), .rx_valid(rx_valid_w)
    );