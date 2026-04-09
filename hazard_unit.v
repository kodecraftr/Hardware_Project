module hazard_unit (
    //[4:0] is used because risv has 32 registers which requires 5 bits addresss
    input wire [4:0] rs1_ex, // (EXECUTE)The first source register the ALU needs right now.
    input wire [4:0] rs2_ex, // (EXECUTE)The second source register the ALU needs right now.
    input wire [4:0] rd_mem, // (MEMORY) The destination register of the instruction one step ahead.
    input wire reg_mem_write, // (MEMORY) Is the instruction in MEM actually going to write to a register?
    input wire [4:0] rd_wb, // (WRITEBACK) The destination register of the instruction two steps ahead.
    input wire reg_write_wb, // (WRITEBACK) Is the instruction in WB actually going to write to a register?

    output reg [1:0] forward_a, // Controls the multiplexer for the first operand (usually $rs1$).
    output reg [1:0] forward_b, //  Controls the multiplexer for the second operand (usually $rs2$).
    // These signals are typically 2 bits wide because they need to choose between three possible "sources" of data.
    //2'b00	No Hazard	The ALU takes the data normally from the Register File (the value it got during the Decode stage).
    //2'b10	EX/MEM Hazard	The ALU "snatches" the data from the MEMORY Stage. This is the result of the instruction that was just ahead of it.
    //2'b01	MEM/WB Hazard	The ALU "snatches" the data from the Writeback Stage. This is the result of the instruction that was two steps ahead.

    input wire [4:0] rs1_id,      // Source registers currently in DECODE
    input wire [4:0] rs2_id,
    input wire [4:0] rd_ex,       // Dest register currently in EXECUTE
    input wire mem_read_ex,       // High if the instruction in EX is a 'lw'
    input wire axi_stall,         // High if AXI Master is waiting for Ready

    output reg pc_write,          // Connect to PC Enable
    output reg if_id_write,       // Connect to IF/ID Register Enable
    output reg id_ex_write,       // Connect to ID/EX Register Enable
    output reg ex_mem_write,      // Connect to EX/MEM Register Enable
    output reg mem_wb_write,      //  Connect to MEM/WB Register Enable
    output reg stall_id_ex        // Connect to ID/EX Flush/Clear (Injects NOP)

);

wire load_use_hazard;
assign load_use_hazard = mem_read_ex && (rd_ex != 5'd0) && ((rs1_id == rd_ex) || (rs2_id == rd_ex));
always @(*) begin

        //  source register 1
        // 1. EX/MEM Hazard: Data is in the MEMORY Stage
        if(reg_mem_write&&(rd_mem!=5'd0)&&(rd_mem==rs1_ex)) begin forward_a  = 2'b10; end // Select data from MEM stage
        // 2. MEM/WB Hazard: Data is in the Writeback Stage
        else if(reg_write_wb&&(rd_wb!=5'd0)&&(rd_wb==rs1_ex)) begin forward_a = 2'b01; end // Select data from WB stage
        // 3. No Hazard: Use the value from the Register File
        else begin forward_a=2'b00; end // default value zero

         //  source register 2
        // 1. EX/MEM Hazard: Data is in the MEMORY Stage
        if(reg_mem_write&&(rd_mem!=5'd0)&&(rd_mem==rs2_ex)) begin forward_b  = 2'b10; end // Select data from MEM stage
        // 2. MEM/WB Hazard: Data is in the Writeback Stage
        else if(reg_write_wb&&(rd_wb!=5'd0)&&(rd_wb==rs2_ex)) begin forward_b = 2'b01; end // Select data from WB stage
        // 3. No Hazard: Use the value from the Register File
        else begin forward_b=2'b00; end // default value zero
      
        //STALL CONTROL (The Priority System)
        
        // Default 
        pc_write     = 1'b1;
        if_id_write  = 1'b1;
        id_ex_write  = 1'b1;
        ex_mem_write = 1'b1;
        mem_wb_write = 1'b1;
        stall_id_ex  = 1'b0;

        // PRIORITY 1: AXI Bus Stall (Global Freeze)
        if (axi_stall) begin
            pc_write     = 1'b0;  // counter is not increased 
            if_id_write  = 1'b0;  // instruction is not fetched
            id_ex_write  = 1'b0;  // Traps instruction entering EX
            ex_mem_write = 1'b0;  // Traps instruction entering MEM
            mem_wb_write = 1'b0;  // Traps instruction entering WB
            stall_id_ex  = 1'b0;  // Do NOT flush. We want to preserve the instructions!
        end
        // PRIORITY 2: Load-Use Hazard (Internal 1-Cycle Gap)
        else if (load_use_hazard) begin
            pc_write     = 1'b0;  // Freeze Fetch
            if_id_write  = 1'b0;  // Freeze Decode
            id_ex_write  = 1'b1;  // Let Execute run...
            ex_mem_write = 1'b1;  // Let Memory run...
            mem_wb_write = 1'b1;  // Let Writeback run...
            stall_id_ex  = 1'b1;  // ...but inject a Bubble into Execute
        end
end

endmodule 
