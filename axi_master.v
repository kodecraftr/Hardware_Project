module axi_master (
    input clk,
    input reset,

    input wire [31:0] cpu_mem_addr,   // 32-bit address
    input wire [31:0] cpu_mem_wdata,  // 32-bit data to write
    input wire        cpu_mem_read,   // CPU wants to read (lw)
    input wire        cpu_mem_write,  // CPU wants to write (sw)
    output reg [31:0] cpu_mem_rdata,  // Data sent back to CPU
    output wire       axi_stall,      // Connect to Priority 2 of Hazard Unit
    //AXI Read Address Channel (The "Shouting" wires)
    output reg [31:0] m_axi_araddr,  // The label
    output reg        m_axi_arvalid, // The "Hey!" signal
    input  wire       m_axi_arready, // The Slave's "I'm listening"

    //AXI Read Data Channel (The "Catching" wires)
    input  wire [31:0] m_axi_rdata,  // The actual package (data)
    input  wire        m_axi_rvalid, // The Slave's "Here it is!"
    output reg         m_axi_rready  // Your "My hands are open"

);



assign axi_stall = (state != IDLE) || ((cpu_mem_read || cpu_mem_write) && state == IDLE);
localparam IDLE      = 2'b00; // doing nothing waiting for the cpu to send address
localparam READ_ADDR = 2'b01; // Sending Address
localparam READ_DATA = 2'b10; // Waiting for Data

reg [1:0] state;

always @(posedge clk) begin 

if(reset) begin 
  state<=IDLE;
  m_axi_arvalid<=1'b0; // Stop shouting "I have an address"
  m_axi_rready<=1'b0; // Close your hands (not ready for data yet)
   m_axi_araddr<=32'b0;  // Clear the address pins
  cpu_mem_rdata<=32'b0; // Clear the data returned to CPU 

 
  



end 
else begin
    case (state) 

    IDLE: begin 
        m_axi_rready <= 0;
        if(cpu_mem_read) begin 
            m_axi_araddr  <= cpu_mem_addr;
            m_axi_arvalid <= 1'b1;
            state         <= READ_ADDR;
        end
    end

    READ_ADDR: begin
        if(m_axi_arvalid && m_axi_arready) begin 
            m_axi_arvalid <= 0;
            m_axi_rready  <= 1'b1;
            state         <= READ_DATA;
        end
    end

    READ_DATA: begin 
        if(m_axi_rvalid && m_axi_rready) begin
            cpu_mem_rdata <= m_axi_rdata;
            m_axi_rready  <= 0;
            state         <= IDLE;
        end
    end 

    endcase
end
end 

endmodule
