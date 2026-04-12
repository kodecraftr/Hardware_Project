`timescale 1ns / 1ps

module uart_rx #(
    // Default: 100 MHz clock / 115200 baud = 868
    parameter CLKS_PER_BIT = 868 
)(
    input  wire       clk,
    input  wire       rst_n,      // Active low reset
    input  wire       rx,         // UART RX pin
    output reg  [7:0] rx_data,    // Received byte
    output reg        rx_valid    // Pulses high for 1 clock cycle when data is ready
);

    // State Machine Encoding
    localparam s_IDLE  = 3'b000;
    localparam s_START = 3'b001;
    localparam s_DATA  = 3'b010;
    localparam s_STOP  = 3'b011;


    reg [2:0]  state;
    reg [15:0] clk_count;
    reg [2:0]  bit_index;
    
    // Double-flop synchronizer for asynchronous RX input
    (* ASYNC_REG = "TRUE" *) reg rx_r1;
    (* ASYNC_REG = "TRUE" *) reg rx_sync;
    reg rx_sync_d;
    reg rx_sync_dd;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_r1   <= 1'b1;
            rx_sync <= 1'b1;
            rx_sync_d <= 1'b1;
            rx_sync_dd <= 1'b1;
        end else begin
            rx_r1   <= rx;
            rx_sync <= rx_r1;
            rx_sync_d <= rx_sync;
            rx_sync_dd <= rx_sync_d;
        end
    end

    wire rx_filt = (rx_sync & rx_sync_d) | (rx_sync & rx_sync_dd) | (rx_sync_d & rx_sync_dd);
    reg rx_filt_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rx_filt_d <= 1'b1;
        else
            rx_filt_d <= rx_filt;
    end

    wire start_edge = rx_filt_d && !rx_filt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= s_IDLE;
            rx_data   <= 8'd0;
            rx_valid  <= 1'b0;
            clk_count <= 16'd0;
            bit_index <= 3'd0;
        end else begin
            // Default pulse low
            rx_valid <= 1'b0;

            case (state)
                s_IDLE: begin
                    clk_count <= 16'd0;
                    bit_index <= 3'd0;
                    // Detect a real falling edge into the start bit.
                    if (start_edge) begin
                        state <= s_START;
                    end
                end

                s_START: begin
                    // Wait to reach the middle of the start bit
                    if (clk_count == (CLKS_PER_BIT / 2) - 1) begin
                        if (rx_filt == 1'b0) begin // Confirm it's still low
                            clk_count <= 16'd0;
                            state     <= s_DATA;
                        end else begin
                            state <= s_IDLE; // False alarm (glitch)
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                s_DATA: begin
                    // Wait one full bit period
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= 16'd0;
                        rx_data[bit_index] <= rx_filt; // Sample data
                        
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1'b1;
                        end else begin
                            bit_index <= 3'd0;
                            state     <= s_STOP;
                        end
                    end
                end

                s_STOP: begin
                    // Wait one full bit period to finish the stop bit
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= 16'd0;
                        // Only accept the byte if the stop bit is high.
                        if (rx_filt == 1'b1)
                            rx_valid  <= 1'b1;
                        state     <= s_IDLE;
                    end
                end

                default: state <= s_IDLE;
            endcase
        end
    end
endmodule
