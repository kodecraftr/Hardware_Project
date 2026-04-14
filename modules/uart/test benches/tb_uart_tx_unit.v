`timescale 1ns / 1ps

module tb_uart_tx_unit;

    localparam integer CLK_PERIOD   = 10;
    localparam integer CLKS_PER_BIT = 3;  // 10 bits => ~30 cycles/byte

    reg clk;
    reg rst_n;
    reg tx_start;
    reg [7:0] tx_data;
    wire tx;
    wire tx_busy;

    integer i;
    reg [7:0] sampled;

    uart_tx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx(tx),
        .tx_busy(tx_busy)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    task automatic fail(input [255:0] msg);
        begin
            $display("TB_UART_TX_UNIT FAIL: %0s", msg);
            $fatal(1);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        tx_start = 1'b0;
        tx_data = 8'h00;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        tx_data  = 8'hA5;
        tx_start = 1'b1;
        @(posedge clk);
        tx_start = 1'b0;

        @(posedge clk);
        if (!tx_busy)
            fail("tx_busy did not assert");

        repeat (CLKS_PER_BIT + (CLKS_PER_BIT/2)) @(posedge clk);
        for (i = 0; i < 8; i = i + 1) begin
            sampled[i] = tx;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end

        if (sampled !== 8'hA5)
            fail("serialized byte mismatch");

        repeat (CLKS_PER_BIT) @(posedge clk);
        if (tx !== 1'b1)
            fail("stop bit was not high");

        repeat (2) @(posedge clk);
        if (tx_busy)
            fail("tx_busy did not clear");

        $display("TB_UART_TX_UNIT PASS");
        $finish;
    end

endmodule
