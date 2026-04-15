`timescale 1ns / 1ps

module multi_cycle_divider (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire        is_signed,
    input  wire        is_rem,      // 1 for REM/REMU, 0 for DIV/DIVU
    input  wire [31:0] dividend,
    input  wire [31:0] divisor,

    output reg         ready,
    output reg  [31:0] result
);

    localparam [1:0] IDLE   = 2'b00;
    localparam [1:0] DIVIDE = 2'b01;
    localparam [1:0] DONE   = 2'b10;

    reg [1:0]  state;
    reg [5:0]  count;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            state <= IDLE;
            count <= 6'd0;
            ready <= 1'b0;
            result <= 32'd0;
        end else begin
            case (state)
                IDLE: begin
                    ready <= 1'b0;
                    if (start) begin
                        // Just start the 32-cycle timer, no math yet
                        count <= 6'd32;
                        state <= DIVIDE;
                    end
                end

                DIVIDE: begin
                    count <= count - 1'b1;

                    if (count == 6'd1) begin
                        result <= 32'd0; // Dummy result for stage 1
                        ready  <= 1'b1;
                        state  <= DONE;
                    end
                end

                DONE: begin
                    ready <= 1'b1;
                    if (!start) begin
                        ready <= 1'b0;
                        state <= IDLE;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule