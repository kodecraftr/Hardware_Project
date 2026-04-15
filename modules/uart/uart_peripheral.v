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

    localparam integer RX_FIFO_DEPTH = 32;
    localparam integer RX_FIFO_AW    = 5;
    
    (* ram_style = "distributed" *) reg [7:0] rx_fifo [0:RX_FIFO_DEPTH-1];
    reg [7:0] rx_data_buf;
    reg [RX_FIFO_AW-1:0] rx_rd_ptr, rx_wr_ptr;
    reg [6:0] rx_fifo_count;
    reg rx_overflow, rx_status_clear_pending, rx_pop_pending;

    wire rx_fifo_empty = (rx_fifo_count == 7'd0);
    wire rx_fifo_full  = (rx_fifo_count == RX_FIFO_DEPTH);
    wire rx_pop        = rx_pop_pending && !rx_fifo_empty;
    wire rx_push       = rx_valid_w;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || control_rst_rx) begin
            {rx_rd_ptr, rx_wr_ptr, rx_fifo_count} <= 0;
            rx_overflow <= 1'b0;
            rx_pop_pending <= 1'b0;
        end else begin
            rx_status_clear_pending <= rx_status_read;
            rx_pop_pending <= rx_data_read;
            if (rx_push && rx_fifo_full) rx_overflow <= 1'b1;

            case ({(rx_push && !rx_fifo_full), rx_pop})
                2'b01: begin // Pop
                    if (rx_fifo_count > 7'd1) begin
                        rx_data_buf <= rx_fifo[rx_rd_ptr];
                        rx_rd_ptr <= rx_rd_ptr + 1'b1;
                    end
                    rx_fifo_count <= rx_fifo_count - 1'b1;
                end
                2'b10: begin // Push
                    if (rx_fifo_count == 7'd0) rx_data_buf <= rx_data_w;
                    else begin
                        rx_fifo[rx_wr_ptr] <= rx_data_w;
                        rx_wr_ptr <= rx_wr_ptr + 1'b1;
                    end
                    rx_fifo_count <= rx_fifo_count + 1'b1;
                end
                2'b11: begin // Both
                    if (rx_fifo_count <= 7'd1) rx_data_buf <= rx_data_w;
                    else begin
                        rx_data_buf <= rx_fifo[rx_rd_ptr];
                        rx_rd_ptr <= rx_rd_ptr + 1'b1;
                        rx_fifo[rx_wr_ptr] <= rx_data_w;
                        rx_wr_ptr <= rx_wr_ptr + 1'b1;
                    end
                end
            endcase
            if (rx_status_clear_pending || rx_pop) rx_overflow <= 1'b0;
        end
    end
endmodule