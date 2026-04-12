`timescale 1ns / 1ps

module uart_tx #(
    // Default: 100 MHz clock / 115200 baud = 868
    parameter CLKS_PER_BIT = 868 
)(
    input  wire       clk,
    input  wire       rst_n,      // Active low reset
    input  wire       tx_start,   // Pulse high to start transmission
    input  wire [7:0] tx_data,    // Byte to transmit
    output reg        tx,         // UART TX pin
    output reg        tx_busy     // High when transmitting
);

    // State Machine Encoding
    localparam s_IDLE  = 3'b000;
    localparam s_START = 3'b001;
    localparam s_DATA  = 3'b010;
    localparam s_STOP  = 3'b011;

    reg [2:0]  state;
    reg [15:0] clk_count;
    reg [2:0]  bit_index;
    reg [7:0]  data_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= s_IDLE;
            tx        <= 1'b1; // Idle state for UART is high
            tx_busy   <= 1'b0;
            clk_count <= 16'd0;
            bit_index <= 3'd0;
            data_reg  <= 8'd0;
        end else begin
            case (state)
                s_IDLE: begin
                    tx        <= 1'b1;
                    tx_busy   <= 1'b0;
                    clk_count <= 16'd0;
                    bit_index <= 3'd0;
                    
                    if (tx_start) begin
                        data_reg  <= tx_data;
                        tx_busy   <= 1'b1;
                        state     <= s_START;
                    end
                end

                s_START: begin
                    tx <= 1'b0; // Start bit is low
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= 16'd0;
                        state     <= s_DATA;
                    end
                end

                s_DATA: begin
                    tx <= data_reg[bit_index]; // LSB first
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= 16'd0;
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1'b1;
                        end else begin
                            bit_index <= 3'd0;
                            state     <= s_STOP;
                        end
                    end
                end

                s_STOP: begin
                    tx <= 1'b1; // Stop bit is high
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= 16'd0;
                        state     <= s_IDLE;
                    end
                end

                default: state <= s_IDLE;
            endcase
        end
    end
endmodule