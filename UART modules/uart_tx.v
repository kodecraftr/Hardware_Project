module uart_tx #(parameter CLKS_PER_BIT = 868) ( // 100MHz / 115200 Baud
    input clk, input reset, input tx_start, input [7:0] tx_data,
    output reg tx_pin, output reg tx_busy
);
    reg [15:0] clk_count; reg [2:0] bit_index; reg [9:0] shift_reg; reg state;

    always @(posedge clk) begin
        if (reset) begin
            tx_pin <= 1; tx_busy <= 0; state <= 0;
        end else begin
            case (state)
                0: if (tx_start) begin // IDLE
                    shift_reg <= {1'b1, tx_data, 1'b0}; // Stop bit, Data, Start bit
                    clk_count <= 0; bit_index <= 0;
                    tx_busy <= 1; state <= 1;
                end
                1: begin // TRANSMIT
                    tx_pin <= shift_reg[0];
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        if (bit_index < 9) begin
                            shift_reg <= shift_reg >> 1;
                            bit_index <= bit_index + 1;
                        end else begin
                            tx_busy <= 0; state <= 0;
                        end
                    end
                end
            endcase
        end
    end
endmodule