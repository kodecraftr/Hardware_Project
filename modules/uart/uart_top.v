`timescale 1ns / 1ps

// ============================================================
//  uart_top.v
//  Standalone UART echo demo for FPGA bring-up
//
//  Behavior
//  --------
//  - Receives bytes from the USB-UART
//  - Echoes them back to the terminal
//  - Uses a tiny byte FIFO so characters are not lost while TX is busy
//  - Shows simple status on the LEDs
//
//  Target clock : 100 MHz
//  UART         : 115200 8N1
// ============================================================

module uart_top (
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,
    input  wire        UART_RXD_OUT,
    output wire        UART_TXD_IN,
    output wire [15:0] led
);

    localparam integer CLKS_PER_BIT = 868;  // 100 MHz / 115200
    localparam integer FIFO_DEPTH   = 16;
    localparam integer FIFO_AW      = 4;

    wire       rst_n = CPU_RESETN;
    wire [7:0] rx_data;
    wire       rx_valid;
    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx_busy;

    (* ram_style = "distributed" *) reg [7:0] fifo [0:FIFO_DEPTH-1];
    reg [FIFO_AW-1:0] wr_ptr;
    reg [FIFO_AW-1:0] rd_ptr;
    reg [4:0]         fifo_count;
    reg               overflow_seen;
    reg [7:0]         last_rx_byte;
    reg [23:0]        rx_hold;
    reg [23:0]        tx_hold;
    reg [25:0]        heartbeat;

    wire fifo_empty = (fifo_count == 5'd0);
    wire fifo_full  = (fifo_count == FIFO_DEPTH);
    wire pop_byte   = !tx_busy && !fifo_empty;

    uart_rx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) u_rx (
        .clk     (CLK100MHZ),
        .rst_n   (rst_n),
        .rx      (UART_RXD_OUT),
        .rx_data (rx_data),
        .rx_valid(rx_valid)
    );

    uart_tx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) u_tx (
        .clk     (CLK100MHZ),
        .rst_n   (rst_n),
        .tx_start(tx_start),
        .tx_data (tx_data),
        .tx      (UART_TXD_IN),
        .tx_busy (tx_busy)
    );

    always @(posedge CLK100MHZ or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr        <= {FIFO_AW{1'b0}};
            rd_ptr        <= {FIFO_AW{1'b0}};
            fifo_count    <= 5'd0;
            tx_start      <= 1'b0;
            tx_data       <= 8'h00;
            overflow_seen <= 1'b0;
            last_rx_byte  <= 8'h00;
            rx_hold       <= 24'd0;
            tx_hold       <= 24'd0;
            heartbeat     <= 26'd0;
        end else begin
            heartbeat <= heartbeat + 1'b1;
            tx_start  <= 1'b0;

            if (rx_valid) begin
                last_rx_byte <= rx_data;
                rx_hold      <= 24'd8_000_000;

                if (!fifo_full) begin
                    fifo[wr_ptr] <= rx_data;
                    wr_ptr       <= wr_ptr + 1'b1;
                    fifo_count   <= fifo_count + 1'b1;
                end else begin
                    overflow_seen <= 1'b1;
                end
            end else if (rx_hold != 24'd0) begin
                rx_hold <= rx_hold - 1'b1;
            end

            if (pop_byte) begin
                tx_data    <= fifo[rd_ptr];
                tx_start   <= 1'b1;
                rd_ptr     <= rd_ptr + 1'b1;
                fifo_count <= fifo_count - 1'b1;
                tx_hold    <= 24'd8_000_000;
            end else if (tx_hold != 24'd0) begin
                tx_hold <= tx_hold - 1'b1;
            end
        end
    end

    assign led[0]  = heartbeat[25];
    assign led[1]  = rst_n;
    assign led[2]  = (rx_hold != 24'd0);
    assign led[3]  = (tx_hold != 24'd0);
    assign led[4]  = !fifo_empty;
    assign led[5]  = fifo_full;
    assign led[6]  = overflow_seen;
    assign led[7]  = tx_busy;
    assign led[15:8] = last_rx_byte;

endmodule
