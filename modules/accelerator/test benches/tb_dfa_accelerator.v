`timescale 1ns / 1ps

module tb_dfa_accelerator;

  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg [31:0] raddr = 32'h0;
  reg [31:0] waddr = 32'h0;
  reg        re    = 1'b0;
  reg        we    = 1'b0;
  reg [31:0] wdata = 32'h0;
  wire [31:0] rdata;
  wire ready;
  wire irq;

  dfa_accelerator #(
      .NUM_STATES(4),
      .SYMBOL_BITS(1)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .raddr(raddr),
      .waddr(waddr),
      .re(re),
      .we(we),
      .wdata(wdata),
      .rdata(rdata),
      .ready(ready),
      .irq(irq)
  );

  always #5 clk = ~clk;

  task automatic write_reg;
    input [31:0] addr;
    input [31:0] data;
    begin
      @(posedge clk);
      waddr <= addr;
      wdata <= data;
      we    <= 1'b1;
      @(posedge clk);
      we    <= 1'b0;
    end
  endtask

  task automatic read_reg;
    input [31:0] addr;
    begin
      @(posedge clk);
      raddr <= addr;
      re    <= 1'b1;
      @(posedge clk);
      re    <= 1'b0;
    end
  endtask

  task automatic expect_status;
    input busy_exp;
    input done_exp;
    input accept_exp;
    input reject_exp;
    begin
      read_reg(32'h04);
      if (rdata[0] !== busy_exp || rdata[1] !== done_exp ||
          rdata[2] !== accept_exp || rdata[3] !== reject_exp) begin
        $display("TB_DFA_ACCELERATOR FAIL status=0x%08x expected busy=%0b done=%0b accept=%0b reject=%0b",
                 rdata, busy_exp, done_exp, accept_exp, reject_exp);
        $fatal(1);
      end
    end
  endtask

  initial begin
    // DFA for strings ending in "01"
    // state 0: start
    // state 1: saw trailing 0
    // state 2: accept (saw trailing 01)
    // state 3: dead/other trailing 1
    //
    // symbol 0 = '0', symbol 1 = '1'
    //
    // transitions:
    // s0: 0->1 1->3
    // s1: 0->1 1->2
    // s2: 0->1 1->3
    // s3: 0->1 1->3

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    write_reg(32'h08, 32'd0);      // start state
    write_reg(32'h0C, 32'b0100);   // only state 2 is accepting

    write_reg(32'h40, 32'd1);  // s0, sym0 -> s1
    write_reg(32'h44, 32'd3);  // s0, sym1 -> s3
    write_reg(32'h48, 32'd1);  // s1, sym0 -> s1
    write_reg(32'h4C, 32'd2);  // s1, sym1 -> s2
    write_reg(32'h50, 32'd1);  // s2, sym0 -> s1
    write_reg(32'h54, 32'd3);  // s2, sym1 -> s3
    write_reg(32'h58, 32'd1);  // s3, sym0 -> s1
    write_reg(32'h5C, 32'd3);  // s3, sym1 -> s3

    // Test accepted string: 1 0 1
    write_reg(32'h00, 32'b001); // START
    expect_status(1'b1, 1'b0, 1'b0, 1'b0);
    write_reg(32'h10, 32'b1);         // sym1
    write_reg(32'h10, 32'b0);         // sym0
    write_reg(32'h10, 32'b1 | (1<<8)); // sym1, LAST
    expect_status(1'b0, 1'b1, 1'b1, 1'b0);
    if (irq !== 1'b1) begin
      $display("TB_DFA_ACCELERATOR FAIL irq was not asserted on completion");
      $fatal(1);
    end
    write_reg(32'h00, 32'b100); // CLEAR_IRQ
    @(posedge clk);
    if (irq !== 1'b0) begin
      $display("TB_DFA_ACCELERATOR FAIL irq did not clear");
      $fatal(1);
    end

    // Test rejected string: 1 1
    write_reg(32'h00, 32'b001); // START
    write_reg(32'h10, 32'b1);         // sym1
    write_reg(32'h10, 32'b1 | (1<<8)); // sym1, LAST
    expect_status(1'b0, 1'b1, 1'b0, 1'b1);

    // Test input error when feeding without START
    write_reg(32'h00, 32'b010); // RESET_CTX
    write_reg(32'h10, 32'b0);
    read_reg(32'h04);
    if (rdata[9] !== 1'b1) begin
      $display("TB_DFA_ACCELERATOR FAIL input_err did not set");
      $fatal(1);
    end

    $display("TB_DFA_ACCELERATOR PASS");
    $finish;
  end

endmodule
