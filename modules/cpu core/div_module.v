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
    reg        is_rem_r;
    reg        quotient_neg_r;
    reg        remainder_neg_r;
    reg [31:0] divisor_abs_r;
    reg [32:0] remainder_work_r;
    reg [31:0] quotient_work_r;

    wire dividend_neg = is_signed && dividend[31];
    wire divisor_neg  = is_signed && divisor[31];

    wire [31:0] dividend_abs =
        dividend_neg ? (~dividend + 32'd1) : dividend;
    wire [31:0] divisor_abs =
        divisor_neg ? (~divisor + 32'd1) : divisor;

    wire div_by_zero_now = (divisor == 32'd0);
    wire overflow_now    = is_signed &&
                           (dividend == 32'h8000_0000) &&
                           (divisor  == 32'hFFFF_FFFF);

    wire [32:0] remainder_shift_w = {remainder_work_r[31:0], quotient_work_r[31]};
    wire [32:0] divisor_ext_w     = {1'b0, divisor_abs_r};
    wire        subtract_w        = (remainder_shift_w >= divisor_ext_w);
    wire [32:0] remainder_next_w  = subtract_w ? (remainder_shift_w - divisor_ext_w)
                                               : remainder_shift_w;
    wire [31:0] quotient_next_w   = {quotient_work_r[30:0], subtract_w};

    wire [31:0] quotient_signed_w =
        quotient_neg_r ? (~quotient_next_w + 32'd1) : quotient_next_w;
    wire [31:0] remainder_signed_w =
        remainder_neg_r ? (~remainder_next_w[31:0] + 32'd1) : remainder_next_w[31:0];

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            state            <= IDLE;
            count            <= 6'd0;
            ready            <= 1'b0;
            result           <= 32'd0;
            is_rem_r         <= 1'b0;
            quotient_neg_r   <= 1'b0;
            remainder_neg_r  <= 1'b0;
            divisor_abs_r    <= 32'd0;
            remainder_work_r <= 33'd0;
            quotient_work_r  <= 32'd0;
        end else begin
            case (state)
                IDLE: begin
                    ready <= 1'b0;
                    if (start) begin
                        is_rem_r <= is_rem;

                        if (div_by_zero_now) begin
                            result <= is_rem ? dividend : 32'hFFFF_FFFF;
                            state  <= DONE;
                        end else if (overflow_now) begin
                            result <= is_rem ? 32'd0 : 32'h8000_0000;
                            state  <= DONE;
                        end else begin
                            quotient_neg_r   <= dividend_neg ^ divisor_neg;
                            remainder_neg_r  <= dividend_neg;
                            divisor_abs_r    <= divisor_abs;
                            remainder_work_r <= 33'd0;
                            quotient_work_r  <= dividend_abs;
                            count            <= 6'd32;
                            state            <= DIVIDE;
                        end
                    end
                end

                DIVIDE: begin
                    remainder_work_r <= remainder_next_w;
                    quotient_work_r  <= quotient_next_w;
                    count            <= count - 1'b1;

                    if (count == 6'd1) begin
                        result <= is_rem_r ? remainder_signed_w : quotient_signed_w;
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
