`timescale 1ns / 1ps

module axi4_lite_master (
    input  wire        clk,
    input  wire        reset, // Active High

    // CPU Interface (REQ/ACK Style)
    input  wire        mmio_read_req,
    input  wire [31:0] mmio_read_addr,
    input  wire        mmio_write_req,
    input  wire [31:0] mmio_write_addr,
    input  wire [31:0] mmio_write_data,
    input  wire [ 3:0] mmio_write_byte,
    output reg  [31:0] axi_read_data,
    output wire        bus_stall,

    // AXI4-Lite Master Interface
    output reg  [31:0] m_axi_awaddr,
    output wire [ 2:0] m_axi_awprot,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,
    
    output reg  [31:0] m_axi_wdata,
    output reg  [ 3:0] m_axi_wstrb,
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready,
    
    input  wire [ 1:0] m_axi_bresp,
    input  wire        m_axi_bvalid,
    output reg         m_axi_bready,
    
    output reg  [31:0] m_axi_araddr,
    output wire [ 2:0] m_axi_arprot,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,
    
    input  wire [31:0] m_axi_rdata,
    input  wire [ 1:0] m_axi_rresp,
    input  wire        m_axi_rvalid,
    output reg         m_axi_rready
);

    // State Machine
    localparam IDLE   = 3'd0;
    localparam WADDR  = 3'd1;
    localparam WRESP  = 3'd2;
    localparam RADDR  = 3'd3;
    localparam RDATA  = 3'd4;
    localparam ACK    = 3'd5; // The Pipeline Shift State

    reg [2:0] state;

    // AXI4 spec requires protection bits, defaulting to unprivileged/secure data
    assign m_axi_awprot = 3'b000;
    assign m_axi_arprot = 3'b000;

    // CPU Stall Logic: Stall whenever a request exists OR we're still processing it (not back in IDLE).
    // This ensures the pipeline stays frozen until the entire AXI transaction completes.
    assign bus_stall = (mmio_read_req | mmio_write_req) || (state != IDLE);

    always @(posedge clk) begin
        if (reset) begin
            state         <= IDLE;
            m_axi_awvalid <= 0;
            m_axi_wvalid  <= 0;
            m_axi_bready  <= 0;
            m_axi_arvalid <= 0;
            m_axi_rready  <= 0;
            axi_read_data <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (mmio_write_req) begin
                        m_axi_awaddr  <= mmio_write_addr;
                        m_axi_wdata   <= mmio_write_data;
                        m_axi_wstrb   <= mmio_write_byte;
                        m_axi_awvalid <= 1;
                        m_axi_wvalid  <= 1;
                        m_axi_bready  <= 1; // Aggressive BREADY 
                        state         <= WADDR;
                    end else if (mmio_read_req) begin
                        m_axi_araddr  <= mmio_read_addr;
                        m_axi_arvalid <= 1;
                        m_axi_rready  <= 1;
                        state         <= RADDR;
                    end
                end

                // --- WRITE FSM ---
                WADDR: begin
                    // Drop valid signals once accepted by the slave
                    if (m_axi_awready) m_axi_awvalid <= 0;
                    if (m_axi_wready)  m_axi_wvalid  <= 0;
                    
                    // Proceed when both Address and Data are fully handshaked
                    if ((!m_axi_awvalid || m_axi_awready) && (!m_axi_wvalid || m_axi_wready)) begin
                        // Catch Xilinx / Custom UART early BVALID pulses instantly
                        if (m_axi_bvalid) begin
                            m_axi_bready <= 0;
                            state        <= ACK;
                        end else begin
                            state        <= WRESP;
                        end
                    end
                end

                WRESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 0;
                        state        <= ACK;
                    end
                end

                // --- READ FSM ---
                RADDR: begin
                    if (m_axi_arready) m_axi_arvalid <= 0;
                    
                    if (!m_axi_arvalid || m_axi_arready) begin
                        state <= RDATA;
                    end
                end

                RDATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        axi_read_data <= m_axi_rdata;
                        m_axi_rready  <= 0;
                        state         <= ACK;
                    end
                end

                // --- THE HARDWARE HANDSHAKE ---
                ACK: begin
                    // In this state, bus_stall evaluates to 0. 
                    // The pipeline registers will shift to the next instruction on this clock edge.
                    // Only advance to IDLE once the request has been deasserted.
                    // This prevents spurious re-entry into WADDR/RADDR states.
                    if (~mmio_read_req && ~mmio_write_req) begin
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule