`timescale 1ns / 1ps

module axi_master (
    input wire clk,
    input wire reset, // Active Low to match pipeline
    
    // CPU Pipeline Interface
    input wire cpu_mem_read,
    input wire cpu_mem_write,
    input wire [31:0] cpu_addr,
    input wire [31:0] cpu_wdata,
    input wire [3:0] cpu_wstrb,
    
    output reg [31:0] cpu_rdata,
    output reg axi_bus_stall,
    
    // AXI4-Lite Master Interface
    output reg [31:0] m_axi_awaddr,
    output reg m_axi_awvalid,
    input wire m_axi_awready,
    
    output reg [31:0] m_axi_wdata,
    output reg [3:0] m_axi_wstrb,
    output reg m_axi_wvalid,
    input wire m_axi_wready,
    
    input wire m_axi_bvalid,
    output reg m_axi_bready,
    
    output reg [31:0] m_axi_araddr,
    output reg m_axi_arvalid,
    input wire m_axi_arready,
    
    input wire [31:0] m_axi_rdata,
    input wire m_axi_rvalid,
    output reg m_axi_rready
);

    reg [2:0] state, next_state;
    localparam IDLE = 0, W_ADDR = 1, W_RESP = 2, R_ADDR = 3, R_WAIT = 4;

    always @(posedge clk or negedge reset) begin
        if (!reset) state <= IDLE;
        else state <= next_state;
    end

    always @(*) begin
        next_state = state;
        axi_bus_stall = 0;
        
        m_axi_awvalid = 0; m_axi_wvalid = 0; m_axi_bready = 0;
        m_axi_arvalid = 0; m_axi_rready = 0;
        
        m_axi_awaddr = cpu_addr; 
        m_axi_wdata = cpu_wdata; 
        m_axi_wstrb = cpu_wstrb; 
        m_axi_araddr = cpu_addr;

        case (state)
            IDLE: begin
                if (cpu_mem_write) begin
                    next_state = W_ADDR;
                    axi_bus_stall = 1;
                end else if (cpu_mem_read) begin
                    next_state = R_ADDR;
                    axi_bus_stall = 1;
                end
            end
            W_ADDR: begin
                axi_bus_stall = 1;
                m_axi_awvalid = 1; m_axi_wvalid = 1;
                if (m_axi_awready && m_axi_wready) next_state = W_RESP;
            end
            W_RESP: begin
                axi_bus_stall = 1;
                m_axi_bready = 1;
                if (m_axi_bvalid) next_state = IDLE;
            end
            R_ADDR: begin
                axi_bus_stall = 1;
                m_axi_arvalid = 1;
                if (m_axi_arready) next_state = R_WAIT;
            end
            R_WAIT: begin
                axi_bus_stall = 1;
                m_axi_rready = 1;
                if (m_axi_rvalid) begin
                    cpu_rdata = m_axi_rdata;
                    next_state = IDLE;
                end
            end
            default: next_state = IDLE;
        endcase
    end
endmodule