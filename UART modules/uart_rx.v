module uart_rx #(parameter CLKS_PER_BIT = 868) (
    input clk, input reset, input rx_pin, input rx_clear,
    output reg [7:0] rx_data, output reg rx_ready
);
    reg [15:0] clk_count; reg [2:0] bit_index; reg [1:0] state;

    always @(posedge clk) begin
        if (reset) begin
            rx_ready <= 0; rx_data <= 0; state <= 0;
        end else begin
            if (rx_clear) rx_ready <= 0;

            case (state)
                0: if (rx_pin == 0) begin // Detect Start Bit
                    clk_count <= 0; state <= 1;
                end
                1: begin // Wait half a bit period to sample center
                    if (clk_count < CLKS_PER_BIT/2) clk_count <= clk_count + 1;
                    else begin clk_count <= 0; bit_index <= 0; state <= 2; end
                end
                2: begin // Read Data Bits
                    if (clk_count < CLKS_PER_BIT - 1) clk_count <= clk_count + 1;
                    else begin
                        clk_count <= 0;
                        rx_data[bit_index] <= rx_pin;
                        if (bit_index < 7) bit_index <= bit_index + 1;
                        else state <= 3;
                    end
                end
                3: begin // Wait for Stop Bit
                    if (clk_count < CLKS_PER_BIT - 1) clk_count <= clk_count + 1;
                    else begin rx_ready <= 1; state <= 0; end
                end
            endcase
        end
    end
endmodule