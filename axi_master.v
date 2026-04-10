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

endmodule
