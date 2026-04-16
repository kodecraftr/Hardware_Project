`timescale 1ns / 1ps

// ============================================================
//  uart_peripheral.v
//  Memory-mapped UART peripheral for RISC-V SoC
//
//  Register Map (byte offsets from peripheral base)
//  ------------------------------------------------
//  0x00  TX_DATA   [7:0]   W  - Write a byte into the TX FIFO
//  0x04  TX_STATUS [0]     R  - 1 = TX FIFO can accept another byte
//                    [1]   R  - 1 = TX path is fully empty
//                  [6:2]   R  - TX FIFO occupancy bits [4:0]
//  0x08  RX_DATA   [7:0]   R  - Next received byte (read pops FIFO)
//  0x0C  RX_STATUS [0]     R  - 1 = RX FIFO not empty
//                    [1]   R  - 1 = RX overflow has occurred
//                    [2]   R  - 1 = RX FIFO is full
//                  [9:3]   R  - RX FIFO occupancy bits [6:0]
//  0x10  CONTROL   [0]     W  - Pulse to reset TX FIFO / TX state
//                    [1]   W  - Pulse to reset RX FIFO / RX status
//
//  Bus interface: valid/ready handshake (single-cycle for regs).
// ============================================================

module uart_peripheral #(
    parameter SYS_CLK_FREQ = 100_000_000,
    parameter BAUD_RATE    = 115_200
)(
    input  wire        clk,
    input  wire        rst_n,

    // Bus slave interface
    input  wire [31:0] raddr,        // byte read address (low 4 bits used)
    input  wire [31:0] waddr,        // byte write address (low 4 bits used)
    input  wire        we,           // write enable
    input  wire        re,           // read enable
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    output wire        ready,        // transaction acknowledged

    // Physical UART pins
    input  wire        uart_rx,
    output wire        uart_tx
);

    localparam CLKS_PER_BIT = SYS_CLK_FREQ / BAUD_RATE;
    localparam integer RX_FIFO_DEPTH = 32;
    localparam integer RX_FIFO_AW    = 5;
    localparam integer TX_FIFO_DEPTH = 16;
    localparam integer TX_FIFO_AW    = 4;

    localparam [4:0] REG_TX_DATA   = 5'h00;
    localparam [4:0] REG_TX_STATUS = 5'h04;
    localparam [4:0] REG_RX_DATA   = 5'h08;
    localparam [4:0] REG_RX_STATUS = 5'h0c;
    localparam [4:0] REG_CONTROL   = 5'h10;

    // ----------------------------------------------------------
    //  Internal UART TX/RX wires
    // ----------------------------------------------------------
    wire        tx_busy;
    reg         tx_start;
    
    reg  [ 7:0] tx_data_reg;
    reg         tx_start_pending;
    reg         tx_serializer_active;
    reg         tx_busy_d;

    wire [ 7:0] rx_data_w;
    wire        rx_valid_w;

    wire uart_tx_rst_n;
    wire uart_rx_rst_n;

    assign uart_tx_rst_n = rst_n && !control_rst_tx;
    assign uart_rx_rst_n = rst_n && !control_rst_rx;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk     (clk),
        .rst_n   (uart_tx_rst_n),
        .tx_start(tx_start),
        .tx_data (tx_data_reg),
        .tx      (uart_tx),
        .tx_busy (tx_busy)
    );

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk     (clk),
        .rst_n   (uart_rx_rst_n),
        .rx      (uart_rx),
        .rx_data (rx_data_w),
        .rx_valid(rx_valid_w)
    );

    // ----------------------------------------------------------
    //  RX FIFO
    // ----------------------------------------------------------
    (* ram_style = "distributed" *) reg [7:0] rx_fifo [0:RX_FIFO_DEPTH-1];
    reg [7:0] rx_data_buf;
    reg [RX_FIFO_AW-1:0] rx_rd_ptr;
    reg [RX_FIFO_AW-1:0] rx_wr_ptr;
    reg [6:0]            rx_fifo_count;
    reg                  rx_overflow;
    wire                 rx_fifo_empty;
    wire                 rx_fifo_full;
    wire                 rx_status_read;
    wire                 rx_data_read;
    wire                 control_write;
    wire                 control_rst_tx;
    wire                 control_rst_rx;
    wire                 rx_pop;
    wire                 rx_push;
    reg                  rx_status_clear_pending;
    reg                  rx_pop_pending;
    assign rx_fifo_empty = (rx_fifo_count == 7'd0);
    assign rx_fifo_full  = (rx_fifo_count == RX_FIFO_DEPTH);
    assign rx_status_read = re && (raddr[4:0] == REG_RX_STATUS);
    assign rx_data_read   = re && (raddr[4:0] == REG_RX_DATA);
    assign control_write  = we && (waddr[4:0] == REG_CONTROL);
    assign control_rst_tx = control_write && wdata[0];
    assign control_rst_rx = control_write && wdata[1];
    assign rx_pop         = rx_pop_pending && !rx_fifo_empty;
    assign rx_push        = rx_valid_w;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_data_buf   <= 8'h00;
            rx_rd_ptr    <= {RX_FIFO_AW{1'b0}};
            rx_wr_ptr    <= {RX_FIFO_AW{1'b0}};
            rx_fifo_count <= 7'd0;
            rx_overflow  <= 1'b0;
            rx_status_clear_pending <= 1'b0;
            rx_pop_pending          <= 1'b0;
        end else if (control_rst_rx) begin
            rx_data_buf   <= 8'h00;
            rx_rd_ptr    <= {RX_FIFO_AW{1'b0}};
            rx_wr_ptr    <= {RX_FIFO_AW{1'b0}};
            rx_fifo_count <= 7'd0;
            rx_overflow  <= 1'b0;
            rx_status_clear_pending <= 1'b0;
            rx_pop_pending          <= 1'b0;
        end else begin
            rx_status_clear_pending <= rx_status_read;
            rx_pop_pending          <= rx_data_read;

            if (rx_push && rx_fifo_full)
                rx_overflow <= 1'b1;

            case ({(rx_push && !rx_fifo_full), rx_pop})
                2'b00: begin
                end

                2'b01: begin
                    if (rx_fifo_count > 7'd1) begin
                        rx_data_buf <= rx_fifo[rx_rd_ptr];
                        rx_rd_ptr   <= rx_rd_ptr + 1'b1;
                    end
                    rx_fifo_count <= rx_fifo_count - 1'b1;
                end

                2'b10: begin
                    if (rx_fifo_count == 7'd0) begin
                        rx_data_buf <= rx_data_w;
                    end else begin
                        rx_fifo[rx_wr_ptr] <= rx_data_w;
                        rx_wr_ptr          <= rx_wr_ptr + 1'b1;
                    end
                    rx_fifo_count <= rx_fifo_count + 1'b1;
                end

                2'b11: begin
                    if (rx_fifo_count <= 7'd1) begin
                        rx_data_buf   <= rx_data_w;
                        rx_fifo_count <= 7'd1;
                    end else begin
                        rx_data_buf         <= rx_fifo[rx_rd_ptr];
                        rx_rd_ptr           <= rx_rd_ptr + 1'b1;
                        rx_fifo[rx_wr_ptr]  <= rx_data_w;
                        rx_wr_ptr           <= rx_wr_ptr + 1'b1;
                        rx_fifo_count       <= rx_fifo_count;
                    end
                end
            endcase

            if (rx_status_clear_pending || rx_pop)
                rx_overflow <= 1'b0;
        end
    end

    // ----------------------------------------------------------
    //  TX FIFO
    // ----------------------------------------------------------
    (* ram_style = "distributed" *) reg [7:0] tx_fifo [0:TX_FIFO_DEPTH-1];
    reg [7:0] tx_data_buf;
    reg [TX_FIFO_AW-1:0] tx_rd_ptr;
    reg [TX_FIFO_AW-1:0] tx_wr_ptr;
    reg [4:0]            tx_fifo_count;
    wire                 tx_fifo_empty;
    wire                 tx_fifo_full;
    wire                 tx_write_req;
    wire                 tx_write_ready;
    wire                 tx_push;
    wire                 tx_launch;

    assign tx_fifo_empty = (tx_fifo_count == 5'd0);
    assign tx_fifo_full  = (tx_fifo_count == TX_FIFO_DEPTH);
    assign tx_write_req   = we && (waddr[4:0] == REG_TX_DATA);
    assign tx_write_ready = !tx_fifo_full;
    assign tx_push        = tx_write_req && tx_write_ready;
    assign tx_launch      = !tx_serializer_active && !tx_fifo_empty;

    // ----------------------------------------------------------
    //  Write path - TX FIFO / TX launch
    // ----------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_start    <= 1'b0;
            tx_data_reg <= 8'h00;
            tx_start_pending <= 1'b0;
            tx_serializer_active <= 1'b0;
            tx_busy_d   <= 1'b0;
            tx_data_buf <= 8'h00;
            tx_rd_ptr   <= {TX_FIFO_AW{1'b0}};
            tx_wr_ptr   <= {TX_FIFO_AW{1'b0}};
            tx_fifo_count <= 5'd0;
        end else if (control_rst_tx) begin
            tx_start    <= 1'b0;
            tx_data_reg <= 8'h00;
            tx_start_pending <= 1'b0;
            tx_serializer_active <= 1'b0;
            tx_busy_d   <= 1'b0;
            tx_data_buf <= 8'h00;
            tx_rd_ptr   <= {TX_FIFO_AW{1'b0}};
            tx_wr_ptr   <= {TX_FIFO_AW{1'b0}};
            tx_fifo_count <= 5'd0;
        end else begin
            tx_start <= 1'b0;   // default: pulse for one cycle
            tx_busy_d <= tx_busy;

            if (tx_start_pending) begin
                tx_start    <= 1'b1;
                tx_start_pending <= 1'b0;
            end

            if (tx_launch) begin
                tx_data_reg <= tx_data_buf;
                tx_start_pending <= 1'b1;
                tx_serializer_active <= 1'b1;
            end

            if (tx_serializer_active && tx_busy_d && !tx_busy)
                tx_serializer_active <= 1'b0;

            case ({tx_launch, tx_push})
                2'b01: begin
                    if (tx_fifo_count == 5'd0) begin
                        tx_data_buf   <= wdata[7:0];
                        tx_fifo_count <= 5'd1;
                    end else begin
                        tx_fifo[tx_wr_ptr] <= wdata[7:0];
                        tx_wr_ptr          <= tx_wr_ptr + 1'b1;
                        tx_fifo_count      <= tx_fifo_count + 1'b1;
                    end
                end

                2'b10: begin
                    if (tx_fifo_count > 5'd1) begin
                        tx_data_buf   <= tx_fifo[tx_rd_ptr];
                        tx_rd_ptr     <= tx_rd_ptr + 1'b1;
                        tx_fifo_count <= tx_fifo_count - 1'b1;
                    end else begin
                        tx_fifo_count <= 5'd0;
                    end
                end

                2'b11: begin
                    if (tx_fifo_count == 5'd1) begin
                        tx_data_buf   <= wdata[7:0];
                        tx_fifo_count <= 5'd1;
                    end else begin
                        tx_data_buf         <= tx_fifo[tx_rd_ptr];
                        tx_rd_ptr           <= tx_rd_ptr + 1'b1;
                        tx_fifo[tx_wr_ptr]  <= wdata[7:0];
                        tx_wr_ptr           <= tx_wr_ptr + 1'b1;
                        tx_fifo_count       <= tx_fifo_count;
                    end
                end

                default: begin
                end
            endcase
        end
    end

    // ----------------------------------------------------------
    //  Read path
    // ----------------------------------------------------------
    always @(*) begin
        case (raddr[4:0])
            REG_TX_DATA:   rdata = {24'h0, tx_data_reg};
            REG_TX_STATUS: rdata = {25'h0, tx_fifo_count, (tx_fifo_empty && !tx_busy), tx_write_ready};
            REG_RX_DATA:   rdata = {24'h0, rx_data_buf};
            REG_RX_STATUS: rdata = {22'h0, rx_fifo_count, rx_fifo_full, rx_overflow, ~rx_fifo_empty};
            REG_CONTROL:   rdata = 32'h0000_0000;
            default: rdata = 32'hDEAD_BEEF;
        endcase
    end

    // ----------------------------------------------------------
    //  Ready:
    //  - reads always acknowledge in 1 cycle
    //  - TX_DATA writes acknowledge only when the TX FIFO is not full
    //  - other writes acknowledge in 1 cycle
    // ----------------------------------------------------------
    assign ready = re | (we && ((waddr[4:0] != REG_TX_DATA) || tx_write_ready));

endmodule
