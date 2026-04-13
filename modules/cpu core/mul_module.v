`timescale 1ns / 1ps

module booth_radix4_multiplier (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,          // execute.v tells us to start
    output reg         ready,          // we tell execute.v we are done
    input  wire [31:0] multiplicand_M,
    input  wire [31:0] multiplier_Q,
    output wire [63:0] product
);

    // State Machine states
    localparam IDLE     = 2'b00;
    localparam MULTIPLY = 2'b01;
    localparam DONE     = 2'b10;

    reg [1:0]  state;
    reg [4:0]  count; // Tracks 16 cycles for a 32-bit Q

    // 66-bit combined shifting register:
    // A is [65:33] (33 bits to handle addition overflow/sign bits)
    // Q is [32:1]  (32 bits)
    // Q-1 is [0]   (1 bit implied zero)
    reg [65:0] AQ;
    reg [32:0] M_reg; // 33 bits for sign extension

    // Output assignment: lower 32 bits of A and all 32 bits of Q
    assign product = AQ[64:1];

    // 3-bit Booth window looks at the bottom of the shifting register
    wire [2:0] booth_window = AQ[2:0];

    // Pre-computed Multiplicand values for Radix-4 addition
    wire [32:0] M_ext        = M_reg;
    wire [32:0] M_ext_neg    = ~M_reg + 1'b1;
    wire [32:0] M_ext_x2     = {M_reg[31:0], 1'b0};
    wire [32:0] M_ext_neg_x2 = {M_ext_neg[31:0], 1'b0};

    // Combinational recoder logic
    reg [32:0] add_val;
    always @(*) begin
        case(booth_window)
            3'b000, 3'b111: add_val = 33'd0;
            3'b001, 3'b010: add_val = M_ext;
            3'b011:         add_val = M_ext_x2;
            3'b100:         add_val = M_ext_neg_x2;
            3'b101, 3'b110: add_val = M_ext_neg;
            default:        add_val = 33'd0;
        endcase
    end

    // Next values for accumulation and shifting
    wire [32:0] A_next = AQ[65:33] + add_val;
    
    // Arithmetic shift right by 2 (replicate sign bit twice)
    wire [65:0] AQ_shifted = {A_next[32], A_next[32], A_next, AQ[32:2]};

    // Sequential state machine
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            state <= IDLE;
            ready <= 1'b0;
            AQ    <= 66'b0;
            M_reg <= 33'b0;
            count <= 5'b0;
        end else begin
            case (state)
                IDLE: begin
                    ready <= 1'b0;
                    if (start) begin
                        // Initialize Accumulator (0), Q, and implied 0
                        AQ    <= {33'b0, multiplier_Q, 1'b0};
                        // Sign extend M
                        M_reg <= {multiplicand_M[31], multiplicand_M};
                        count <= 5'd0;
                        state <= MULTIPLY;
                    end
                end

                MULTIPLY: begin
                    AQ    <= AQ_shifted;
                    count <= count + 1'b1;
                    // 16 iterations needed for 32 bits (shifting 2 bits per cycle)
                    if (count == 5'd15) begin
                        state <= DONE;
                    end
                end

                DONE: begin
                    ready <= 1'b1;
                    if (!start) begin // Handshake: Wait for execute stage to drop 'start'
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule
