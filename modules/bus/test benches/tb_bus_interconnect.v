`timescale 1ns / 1ps

module tb_bus_interconnect_basic;

  reg clk;
  reg rst_n;

  // CPU side
  reg  [31:0] dmem_raddr;
  reg  [31:0] dmem_waddr;
  reg         dmem_we;
  reg  [3:0]  dmem_wstrb;
  reg  [31:0] dmem_wdata;
  reg         dmem_read_valid;
  reg         dmem_write_valid;
  wire [31:0] dmem_rdata;
  wire        dmem_read_ready;
  wire        dmem_write_ready;

  // Slave side (mocked)
  wire [31:0] s_dmem_raddr;
  wire        s_dmem_re;
  reg  [31:0] s_dmem_rdata;

  wire [31:0] s_uart_raddr;
  wire        s_uart_re;
  reg  [31:0] s_uart_rdata;
  reg         s_uart_ready;

  // Dummy unused signals
  wire [31:0] imem_rdata;
  wire imem_ready;

  bus_interconnect dut (
      .clk(clk),
      .rst_n(rst_n),

      // IMEM (unused)
      .imem_addr(32'h0),
      .imem_valid(1'b0),
      .imem_rdata(imem_rdata),
      .imem_ready(imem_ready),

      // DMEM interface
      .dmem_raddr(dmem_raddr),
      .dmem_waddr(dmem_waddr),
      .dmem_we(dmem_we),
      .dmem_wstrb(dmem_wstrb),
      .dmem_wdata(dmem_wdata),
      .dmem_read_valid(dmem_read_valid),
      .dmem_write_valid(dmem_write_valid),
      .dmem_rdata(dmem_rdata),
      .dmem_read_ready(dmem_read_ready),
      .dmem_write_ready(dmem_write_ready),

      // DMEM slave
      .s_dmem_raddr(s_dmem_raddr),
      .s_dmem_waddr(),
      .s_dmem_re(s_dmem_re),
      .s_dmem_we(),
      .s_dmem_wstrb(),
      .s_dmem_wdata(),
      .s_dmem_rdata(s_dmem_rdata),

      // UART slave
      .s_uart_raddr(s_uart_raddr),
      .s_uart_waddr(),
      .s_uart_re(s_uart_re),
      .s_uart_we(),
      .s_uart_wdata(),
      .s_uart_rdata(s_uart_rdata),
      .s_uart_ready(s_uart_ready),

      .bus_error()
  );

  // Clock
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Simple slave behavior
  always @(*) begin
    s_dmem_rdata = 32'hAAAA_0000 | s_dmem_raddr[7:0];
    s_uart_rdata = 32'hBBBB_0000 | s_uart_raddr[3:0];
  end

  // Test sequence
  initial begin
    rst_n = 0;
    dmem_read_valid = 0;
    dmem_write_valid = 0;
    dmem_we = 0;
    dmem_wstrb = 4'hF;
    s_uart_ready = 1;

    #20;
    rst_n = 1;

    // -------------------------
    // Test 1: DMEM READ
    // -------------------------
    $display("Testing DMEM read...");
    dmem_raddr = 32'h2000_0004;
    dmem_read_valid = 1;

    #10;
    dmem_read_valid = 0;

    #10;
    $display("DMEM Data = %h", dmem_rdata);

    // -------------------------
    // Test 2: UART READ
    // -------------------------
    $display("Testing UART read...");
    dmem_raddr = 32'h1000_0008;
    dmem_read_valid = 1;

    #10;
    dmem_read_valid = 0;

    #10;
    $display("UART Data = %h", dmem_rdata);

    // -------------------------
    // Test 3: DMEM WRITE
    // -------------------------
    $display("Testing DMEM write...");
    dmem_waddr = 32'h2000_0000;
    dmem_wdata = 32'h12345678;
    dmem_we = 1;
    dmem_write_valid = 1;

    #10;
    dmem_write_valid = 0;
    dmem_we = 0;

    #20;

    $display("Basic TB Completed");
    $finish;
  end

endmodule