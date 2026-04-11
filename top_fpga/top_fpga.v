`timescale 1ns / 1ps

module top_fpga (
    input wire clk,
    input wire reset,     // Active-Low reset (0 = reset)
    input wire uart_rx,   // From physical FPGA pin
    output wire uart_tx   // To physical FPGA pin
);

    // -------------------------------------------------------------
    // 1. MEMORY WIRES
    // -------------------------------------------------------------
    // IMEM
    wire [31:0] imem_addr;
    wire [31:0] imem_data;

    // DMEM
    wire [31:0] dmem_raddr, dmem_waddr, dmem_wdata, dmem_rdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we, dmem_re;


    // -------------------------------------------------------------
    // 2. MEMORY INSTANTIATIONS (From memory.v)
    // -------------------------------------------------------------
    
    // Instruction Memory
    instr_mem IMEM (
        .clk(clk),
        .pc(imem_addr),
        .instr(imem_data)
    );

    // Data Memory (With 1-cycle latency and RAW forwarding)
    data_mem DMEM (
        .clk(clk),
        .re(dmem_re),
        .raddr(dmem_raddr),
        .rdata(dmem_rdata),
        .we(dmem_we),
        .waddr(dmem_waddr),
        .wdata(dmem_wdata),
        .wstrb(dmem_wstrb)
    );


    // -------------------------------------------------------------
    // 3. AXI4-LITE BUS WIRES (CPU to UART)
    // -------------------------------------------------------------
    wire [31:0] b_awaddr, b_wdata, b_araddr, b_rdata;
    wire [3:0]  b_wstrb;
    wire b_awvalid, b_wvalid, b_bready, b_arvalid, b_rready;
    wire b_awready, b_wready, b_bvalid, b_arready, b_rvalid;


    // -------------------------------------------------------------
    // 4. CPU PIPELINE INSTANTIATION
    // -------------------------------------------------------------
    pipe cpu_core (
        .clk(clk),
        .reset(reset),
        .stall(1'b0),          
        .exception(),          
        .pc_out(),             

        // IMEM Interface
        .inst_mem_address(imem_addr),
        .inst_mem_is_valid(1'b1),
        .inst_mem_read_data(imem_data),
        .inst_mem_is_ready(),

        // DMEM Interface
        .dmem_read_address(dmem_raddr),
        .dmem_read_ready(dmem_re),
        .dmem_read_data_temp(dmem_rdata),
        .dmem_read_valid(1'b1),
        .dmem_write_address(dmem_waddr),
        .dmem_write_ready(dmem_we),
        .dmem_write_data(dmem_wdata),
        .dmem_write_byte(dmem_wstrb),
        .dmem_write_valid(1'b1),

        // AXI Master Interface (MMIO Only for UART)
        .m_axi_awaddr(b_awaddr), .m_axi_awvalid(b_awvalid), .m_axi_awready(b_awready),
        .m_axi_wdata(b_wdata), .m_axi_wstrb(b_wstrb), .m_axi_wvalid(b_wvalid), .m_axi_wready(b_wready),
        .m_axi_bvalid(b_bvalid), .m_axi_bready(b_bready),
        .m_axi_araddr(b_araddr), .m_axi_arvalid(b_arvalid), .m_axi_arready(b_arready),
        .m_axi_rdata(b_rdata), .m_axi_rvalid(b_rvalid), .m_axi_rready(b_rready)
    );


    // -------------------------------------------------------------
    // 5. UART PERIPHERAL INSTANTIATION
    // -------------------------------------------------------------
    uart_axi_ip UART (
        .clk(clk),
        .reset(reset),
        
        // Physical external pins
        .tx_pin(uart_tx),
        .rx_pin(uart_rx),
        
        // AXI Interface connection
        .AWADDR(b_awaddr), .AWVALID(b_awvalid), .AWREADY(b_awready),
        .WDATA(b_wdata), .WVALID(b_wvalid), .WREADY(b_wready),
        .BVALID(b_bvalid), .BREADY(b_bready),
        .ARADDR(b_araddr), .ARVALID(b_arvalid), .ARREADY(b_arready),
        .RDATA(b_rdata), .RVALID(b_rvalid), .RREADY(b_rready)
    );

endmodule