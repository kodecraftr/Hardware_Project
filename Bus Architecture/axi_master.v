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
    output reg         m_axi_rready,  // Your "My hands are open"

    //AXI Write Address Channel (AW) "Where"
    output reg [31:0] m_axi_awaddr, // This carries the destination address from the CPU.
    output reg        m_axi_awvalid, // You raise this to say, "I am now driving a valid write address."
    input  wire       m_axi_awready, // The Slave raises this to say, "I have captured the address."

    //AXI Write Data Channel (W) "What"
    output reg [31:0] m_axi_wdata, // This carries the actual data the CPU wants to store (cpu_mem_wdata).
    output reg        m_axi_wvalid, // You raise this to say, "The data on the bus is the real value to be saved."
    input  wire       m_axi_wready, // The Slave raises this to say, "I have received the data."

    //AXI Write Response Channel (B) "Result"
    input  wire       m_axi_bvalid, // The Slave raises this to say, "The write to the actual memory hardware is finished and successful."
    output reg        m_axi_bready // You raise this to say, "I am ready to hear your success message."
);



assign axi_stall = (state != IDLE) || ((cpu_mem_read || cpu_mem_write) && state == IDLE);
localparam IDLE      = 3'b000; // doing nothing waiting for the cpu to send address
localparam READ_ADDR = 3'b001; // Sending Address
localparam READ_DATA = 3'b010; // Waiting for Data
localparam WRITE_DATA = 3'b011; // Sending Address and Data
localparam WRITE_RESP = 3'b100; // Waiting for B-channel response
reg [2:0] state;
reg aw_done,w_done;
always @(posedge clk) begin 


if(reset) begin 
  state<=IDLE;
  m_axi_arvalid<=1'b0; // Stop shouting "I have an address"
  m_axi_rready<=1'b0; // Close your hands (not ready for data yet)
   m_axi_araddr<=32'b0;  // Clear the address pins
  cpu_mem_rdata<=32'b0; // Clear the data returned to CPU 
    m_axi_awvalid <= 1'b0;
    m_axi_wvalid  <= 1'b0;
    m_axi_bready  <= 1'b0;
    aw_done<=1'b0;
    w_done<=1'b0;
 end 
else begin
    case (state) 

    IDLE: begin 
        m_axi_rready <= 0;
      //  m_axi_wready <=0;
        if(cpu_mem_read&&!cpu_mem_write) begin 
            m_axi_araddr  <= cpu_mem_addr;
            m_axi_arvalid <= 1'b1;
            state         <= READ_ADDR;
        end
        else if(cpu_mem_write) begin 
             m_axi_awvalid<=1'b1; // valid write address
              m_axi_wvalid <=1'b1; // real valued data is given 
               m_axi_awaddr<= cpu_mem_addr; // address where data is to be stored
               m_axi_wdata <=cpu_mem_wdata; // data that need to be stored
               aw_done <=1'b0; // reset trackers
               w_done <= 1'b0; // reset trackers
               state <= WRITE_DATA; // move the handshake phase

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
    WRITE_DATA : begin 
        if(m_axi_awvalid&& m_axi_awready) begin 
            m_axi_awvalid <=1'b0;
            aw_done<=1'b1;
        end
        if(m_axi_wvalid && m_axi_wready) begin 
            m_axi_wvalid<=1'b0;
            w_done<=1'b1;
        end
            // Check if both channels have finished their handshake
        if (aw_done && w_done) begin
        state        <= WRITE_RESP;
        m_axi_bready <= 1'b1; // Start listening for the response
            
        end

    end
    WRITE_RESP : begin
        if(m_axi_bvalid&&m_axi_bready) begin 
            m_axi_bready <=1'b0;
            state <=IDLE; // write is complete
        end
     end
    endcase
end
end 

endmodule
