`timescale 1ns / 1ps

module tb_bus_interconnect;

  reg clk;
  reg rst_n;

  reg  [31:0] imem_addr;
  reg         imem_valid;
  wire [31:0] imem_rdata;
  wire        imem_ready;

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

  wire [31:0] s_imem_addr;
  wire        s_imem_en;
  reg  [31:0] s_imem_rdata;

  wire [31:0] s_dmem_raddr;
  wire [31:0] s_dmem_waddr;
  wire        s_dmem_re;
  wire        s_dmem_we;
  wire [3:0]  s_dmem_wstrb;
  wire [31:0] s_dmem_wdata;
  reg  [31:0] s_dmem_rdata;

  wire [31:0] s_uart_raddr;
  wire [31:0] s_uart_waddr;
  wire        s_uart_re;
  wire        s_uart_we;
  wire [31:0] s_uart_wdata;
  reg  [31:0] s_uart_rdata;
  reg         s_uart_ready;

  wire bus_error;

  bus_interconnect dut (
      .clk(clk),
      .rst_n(rst_n),
      .imem_addr(imem_addr),
      .imem_valid(imem_valid),
      .imem_rdata(imem_rdata),
      .imem_ready(imem_ready),
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
      .s_imem_addr(s_imem_addr),
      .s_imem_en(s_imem_en),
      .s_imem_rdata(s_imem_rdata),
      .s_dmem_raddr(s_dmem_raddr),
      .s_dmem_waddr(s_dmem_waddr),
      .s_dmem_re(s_dmem_re),
      .s_dmem_we(s_dmem_we),
      .s_dmem_wstrb(s_dmem_wstrb),
      .s_dmem_wdata(s_dmem_wdata),
      .s_dmem_rdata(s_dmem_rdata),
      .s_uart_raddr(s_uart_raddr),
      .s_uart_waddr(s_uart_waddr),
      .s_uart_re(s_uart_re),
      .s_uart_we(s_uart_we),
      .s_uart_wdata(s_uart_wdata),
      .s_uart_rdata(s_uart_rdata),
      .s_uart_ready(s_uart_ready),
      .bus_error(bus_error)
  );

  task automatic fail;
    input string message;
    begin
      $display("TB_BUS_INTERCONNECT FAIL: %0s", message);
      $fatal(1);
    end
  endtask

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  always @(*) begin
    s_imem_rdata = 32'h1111_0000 | s_imem_addr[11:0];
    s_dmem_rdata = 32'hA500_0000 | s_dmem_raddr[11:0];
    s_uart_rdata = 32'h55AA_0000 | s_uart_raddr[3:0];
  end

  initial begin
    rst_n = 1'b0;
    imem_addr = 32'h0;
    imem_valid = 1'b0;
    dmem_raddr = 32'h0;
    dmem_waddr = 32'h0;
    dmem_we = 1'b0;
    dmem_wstrb = 4'h0;
    dmem_wdata = 32'h0;
    dmem_read_valid = 1'b0;
    dmem_write_valid = 1'b0;
    s_uart_ready = 1'b1;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    // IMEM fetch: one-cycle registered response
    imem_addr  <= 32'h0000_0010;
    imem_valid <= 1'b1;
    @(posedge clk);
    imem_valid <= 1'b0;
    if (s_imem_en !== 1'b1)
      fail("IMEM enable did not assert on valid IMEM address");
    @(posedge clk);
    if (imem_ready !== 1'b1 || imem_rdata !== 32'h1111_0010)
      fail($sformatf("IMEM response mismatch ready=%0b rdata=0x%08x", imem_ready, imem_rdata));

    // DMEM read: one-cycle registered response
    dmem_raddr      <= 32'h2000_0008;
    dmem_read_valid <= 1'b1;
    @(posedge clk);
    dmem_read_valid <= 1'b0;
    if (s_dmem_re !== 1'b1)
      fail("DMEM read select did not assert");
    @(posedge clk);
    if (dmem_read_ready !== 1'b1 || dmem_rdata !== 32'hA500_0008)
      fail($sformatf("DMEM read response mismatch ready=%0b rdata=0x%08x", dmem_read_ready, dmem_rdata));

    // UART read: bus must return the captured UART data even if addr changes before ready.
    dmem_raddr      <= 32'h1000_000C;
    dmem_read_valid <= 1'b1;
    @(posedge clk);
    dmem_read_valid <= 1'b0;
    dmem_raddr      <= 32'h2000_0000;
    @(posedge clk);
    if (dmem_read_ready !== 1'b1 || dmem_rdata !== 32'h55AA_000C)
      fail($sformatf("UART captured read mismatch ready=%0b rdata=0x%08x", dmem_read_ready, dmem_rdata));
    // UART write backpressure: ready should track the UART slave.
    dmem_waddr       <= 32'h1000_0000;
    dmem_wdata       <= 32'h0000_0042;
    dmem_wstrb       <= 4'hF;
    dmem_we          <= 1'b1;
    dmem_write_valid <= 1'b1;
    s_uart_ready     <= 1'b0;
    @(posedge clk);
    if (dmem_write_ready !== 1'b0)
      fail("UART write should have been back-pressured");
    s_uart_ready <= 1'b1;
    @(posedge clk);
    if (dmem_write_ready !== 1'b1 || s_uart_we !== 1'b1 || s_uart_wdata !== 32'h0000_0042)
      fail("UART write handshake/data mismatch");
    dmem_write_valid <= 1'b0;
    dmem_we          <= 1'b0;

    // Unmapped read: one-cycle ack with sentinel and bus_error pulse.
    dmem_raddr      <= 32'h3000_0000;
    dmem_read_valid <= 1'b1;
    @(posedge clk);
    dmem_read_valid <= 1'b0;
    #1;
    if (bus_error !== 1'b1)
      fail("Unmapped read did not raise bus_error");
    @(posedge clk);
    if (dmem_read_ready !== 1'b1 || dmem_rdata !== 32'hDEAD_BEEF)
      fail("Unmapped read did not return sentinel data");

    // Unmapped write: combinational ready and bus_error pulse.
    dmem_waddr       <= 32'h3000_0004;
    dmem_wdata       <= 32'hCAFE_BABE;
    dmem_wstrb       <= 4'hF;
    dmem_we          <= 1'b1;
    dmem_write_valid <= 1'b1;
    #1;
    if (dmem_write_ready !== 1'b1)
      fail("Unmapped write should acknowledge immediately");
    @(posedge clk);
    #1;
    if (bus_error !== 1'b1)
      fail("Unmapped write did not raise bus_error");
    dmem_write_valid <= 1'b0;
    dmem_we          <= 1'b0;

    $display("TB_BUS_INTERCONNECT PASS");
    $finish;
  end

endmodule
