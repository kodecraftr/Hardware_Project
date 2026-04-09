module hazard_unit (
    //[4:0] is used because risv has 32 registers which requires 5 bits addresss
    input wire [4:0] rs1_ex, // (Execute)The first source register the ALU needs right now.
    input wire [4:0] rs2_ex, // (Execute)The second source register the ALU needs right now.
    input wire [4:0] rd_mem, // (Memory) The destination register of the instruction one step ahead.
    input wire reg_mem_write, // (Memory) Is the instruction in MEM actually going to write to a register?
    input wire [4:0] rd_wb, // (WriteBack) The destination register of the instruction two steps ahead.
    input wire reg_write_wb, // (WriteBack) Is the instruction in WB actually going to write to a register?

    output reg [1:0] forward_a, // Controls the multiplexer for the first operand (usually $rs1$).
    output reg [1:0] forward_b //  Controls the multiplexer for the second operand (usually $rs2$).
    // These signals are typically 2 bits wide because they need to choose between three possible "sources" of data.
    //2'b00	No Hazard	The ALU takes the data normally from the Register File (the value it got during the Decode stage).
    //2'b10	EX/MEM Hazard	The ALU "snatches" the data from the Memory Stage. This is the result of the instruction that was just ahead of it.
    //2'b01	MEM/WB Hazard	The ALU "snatches" the data from the Writeback Stage. This is the result of the instruction that was two steps ahead.



);

always @(*) begin

        //  source register 1
        // 1. EX/MEM Hazard: Data is in the Memory Stage
        if(reg_mem_write&&(rd_mem!=0)&&(rd_mem==rs1_ex)) begin forward_a  = 2'b10; end // Select data from MEM stage
        // 2. MEM/WB Hazard: Data is in the Writeback Stage
        else if(reg_write_wb&&(rd_wb!=0)&&(rd_wb==rs1_ex)) begin forward_a = 2'b01 end // Select data from WB stage
        // 3. No Hazard: Use the value from the Register File
        else begin forward_a=2'b00; end // default value zero

         //  source register 2
        // 1. EX/MEM Hazard: Data is in the Memory Stage
        if(reg_mem_write&&(rd_mem!=0)&&(rd_mem==rs2_ex)) begin forward_b  = 2'b10; end // Select data from MEM stage
        // 2. MEM/WB Hazard: Data is in the Writeback Stage
        else if(reg_write_wb&&(rd_wb!=0)&&(rd_wb==rs2_ex)) begin forward_b = 2'b01 end // Select data from WB stage
        // 3. No Hazard: Use the value from the Register File
        else begin forward_b=2'b00; end // default value zero

end

endmodule 
