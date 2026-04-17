`timescale 1ns / 1ps

module tb_uart_peripheral_basic;

    localparam integer CLK_PERIOD   = 10;
    localparam integer CLKS_PER_BIT = 3;  // 10 bits => ~30 cycles/byte

    reg clk;
    reg rst_n;
    reg [31:0] raddr;
    reg [31:0] waddr;
    reg we;
    reg re;
    reg [31:0] wdata;
    wire [31:0] rdata;
    wire ready;
    reg uart_rx;
    wire uart_tx;

    wire [7:0] mon_data;
    wire mon_valid;
    reg mon_seen;
    integer i;

    uart_peripheral #(
        .SYS_CLK_FREQ(30),
        .BAUD_RATE(10)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .raddr(raddr),
        .waddr(waddr),
        .we(we),
        .re(re),
        .wdata(wdata),
        .rdata(rdata),
        .ready(ready),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx)
    );

    uart_rx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) monitor (
        .clk(clk),
        .rst_n(rst_n),
        .rx(uart_tx),
        .rx_data(mon_data),
        .rx_valid(mon_valid)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    task automatic fail(input [255:0] msg);
        begin
            $display("TB_UART_PERIPHERAL_BASIC FAIL: %0s", msg);
            $fatal(1);
        end
    endtask

    task automatic send_serial_byte(input [7:0] data);
        begin
            uart_rx = 1'b0;
            repeat (CLKS_PER_BIT) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            uart_rx = 1'b1;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        raddr = 32'h0;
        waddr = 32'h0;
        we = 1'b0;
        re = 1'b0;
        wdata = 32'h0;
        uart_rx = 1'b1;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // RX side: inject one byte and read it back.
        send_serial_byte(8'h5A);
        repeat (3) @(posedge clk);

        raddr = 32'h1000_000C;
        re    = 1'b1;
        #1;
        if (!ready || !rdata[0])
            fail("RX status did not report available byte");
        @(posedge clk);
        re = 1'b0;

        raddr = 32'h1000_0008;
        re    = 1'b1;
        #1;
        if (!ready || rdata[7:0] !== 8'h5A)
            fail("RX data mismatch");
        @(posedge clk);
        re = 1'b0;

        // TX side: write one byte and decode it on the serial output.
        waddr = 32'h1000_0000;
        wdata = 32'h0000_0033;
        we    = 1'b1;
        #1;
        if (!ready)
            fail("TX write was not accepted");
        @(posedge clk);
        we = 1'b0;

        mon_seen = 1'b0;
        repeat (40) begin
            @(posedge clk);
            if (mon_valid)
                mon_seen = 1'b1;
        end
        if (!mon_seen || mon_data !== 8'h33)
            fail("TX serial output mismatch");

        $display("TB_UART_PERIPHERAL_BASIC PASS");
        $finish;
    end

endmodule
