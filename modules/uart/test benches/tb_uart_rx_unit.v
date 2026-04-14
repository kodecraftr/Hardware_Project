`timescale 1ns / 1ps

module tb_uart_rx_unit;

    localparam integer CLK_PERIOD   = 10;
    localparam integer CLKS_PER_BIT = 3;  // 10 bits => ~30 cycles/byte

    reg clk;
    reg rst_n;
    reg rx;
    wire [7:0] rx_data;
    wire rx_valid;
    reg rx_seen;

    integer i;

    uart_rx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .rx(rx),
        .rx_data(rx_data),
        .rx_valid(rx_valid)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    task automatic fail(input [255:0] msg);
        begin
            $display("TB_UART_RX_UNIT FAIL: %0s", msg);
            $fatal(1);
        end
    endtask

    task automatic send_byte(input [7:0] data);
        begin
            rx = 1'b0;
            repeat (CLKS_PER_BIT) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx = data[i];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            rx = 1'b1;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        rx = 1'b1;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        send_byte(8'h5A);
        rx_seen = 1'b0;
        repeat (8) begin
            @(posedge clk);
            if (rx_valid)
                rx_seen = 1'b1;
        end

        if (!rx_seen)
            fail("rx_valid did not pulse");
        if (rx_data !== 8'h5A)
            fail("received byte mismatch");

        @(posedge clk);
        if (rx_valid)
            fail("rx_valid should be a pulse");

        $display("TB_UART_RX_UNIT PASS");
        $finish;
    end

endmodule
