`timescale 1ns / 1ps

module uart_tx #(parameter CLKS_PER_BIT = 868) (
    input clk, input reset, input tx_start, input [7:0] tx_data,
    output reg tx_pin, output reg tx_busy
);
    reg [15:0] clk_count; reg [2:0] bit_index; reg [9:0] shift_reg; reg state;
    always @(posedge clk or negedge reset) begin
        if (!reset) begin tx_pin <= 1; tx_busy <= 0; state <= 0; end 
        else begin
            case (state)
                0: if (tx_start) begin
                    shift_reg <= {1'b1, tx_data, 1'b0}; clk_count <= 0; bit_index <= 0; tx_busy <= 1; state <= 1;
                end
                1: begin
                    tx_pin <= shift_reg[0];
                    if (clk_count < CLKS_PER_BIT - 1) clk_count <= clk_count + 1;
                    else begin
                        clk_count <= 0;
                        if (bit_index < 9) begin shift_reg <= shift_reg >> 1; bit_index <= bit_index + 1; end 
                        else begin tx_busy <= 0; state <= 0; end
                    end
                end
            endcase
        end
    end
endmodule

module uart_rx #(parameter CLKS_PER_BIT = 868) (
    input clk, input reset, input rx_pin, input rx_clear,
    output reg [7:0] rx_data, output reg rx_ready
);
    reg [15:0] clk_count; reg [2:0] bit_index; reg [1:0] state;
    always @(posedge clk or negedge reset) begin
        if (!reset) begin rx_ready <= 0; rx_data <= 0; state <= 0; end 
        else begin
            if (rx_clear) rx_ready <= 0;
            case (state)
                0: if (rx_pin == 0) begin clk_count <= 0; state <= 1; end
                1: begin
                    if (clk_count < CLKS_PER_BIT/2) clk_count <= clk_count + 1;
                    else begin clk_count <= 0; bit_index <= 0; state <= 2; end
                end
                2: begin
                    if (clk_count < CLKS_PER_BIT - 1) clk_count <= clk_count + 1;
                    else begin
                        clk_count <= 0; rx_data[bit_index] <= rx_pin;
                        if (bit_index < 7) bit_index <= bit_index + 1; else state <= 3;
                    end
                end
                3: begin
                    if (clk_count < CLKS_PER_BIT - 1) clk_count <= clk_count + 1;
                    else begin rx_ready <= 1; state <= 0; end
                end
            endcase
        end
    end
endmodule

module uart_axi_ip (
    input clk, input reset,
    input [31:0] AWADDR, input AWVALID, output reg AWREADY,
    input [31:0] WDATA, input WVALID, output reg WREADY, output reg BVALID, input BREADY,
    input [31:0] ARADDR, input ARVALID, output reg ARREADY, output reg [31:0] RDATA, output reg RVALID, input RREADY,
    output tx_pin, input rx_pin
);
    wire tx_busy, rx_ready; wire [7:0] rx_byte;
    reg tx_start; reg [7:0] tx_byte; reg rx_clear;

    uart_tx my_tx (.clk(clk), .reset(reset), .tx_start(tx_start), .tx_data(tx_byte), .tx_pin(tx_pin), .tx_busy(tx_busy));
    uart_rx my_rx (.clk(clk), .reset(reset), .rx_pin(rx_pin), .rx_clear(rx_clear), .rx_data(rx_byte), .rx_ready(rx_ready));

    always @(posedge clk or negedge reset) begin
        if (!reset) begin AWREADY<=0; WREADY<=0; BVALID<=0; tx_start<=0; end
        else begin
            tx_start <= 0;
            if (AWVALID && WVALID && !AWREADY && !WREADY) begin
                if (AWADDR[15:0] == 16'h0000 && !tx_busy) begin tx_byte <= WDATA[7:0]; tx_start <= 1; end
                AWREADY <= 1; WREADY <= 1; BVALID <= 1;
            end else begin AWREADY <= 0; WREADY <= 0; if (BREADY && BVALID) BVALID <= 0; end
        end
    end

    always @(posedge clk or negedge reset) begin
        if (!reset) begin ARREADY<=0; RVALID<=0; rx_clear<=0; end
        else begin
            rx_clear <= 0;
            if (ARVALID && !ARREADY) begin
                if (ARADDR[15:0] == 16'h0004) begin RDATA <= {24'b0, rx_byte}; rx_clear <= 1; end
                else if (ARADDR[15:0] == 16'h0008) RDATA <= {30'b0, rx_ready, tx_busy};
                else RDATA <= 0;
                ARREADY <= 1; RVALID <= 1;
            end else begin ARREADY <= 0; if (RREADY && RVALID) RVALID <= 0; end
        end
    end
endmodule