`timescale 1ns / 1ps

// ============================================================
//  dfa_accelerator.v
//  Simple memory-mapped DFA accelerator
//
//  Goal
//  ----
//  Evaluate a stream of input symbol classes in hardware and
//  report whether the final DFA state is an accepting state.
//
//  Design choice
//  -------------
//  To keep the hardware small and explainable, this block does
//  not consume full 8-bit characters directly. Software maps
//  incoming characters into small symbol classes first, then
//  writes those class IDs into INPUT.
//
//  Register map
//  ------------
//  0x00 CONTROL
//       [0] START      - load start_state, clear don
e/reject/irq, enter busy
//       [1] RESET_CTX  - return to start_state, clear busy/done/reject/irq
//       [2] CLEAR_IRQ  - clear sticky irq flag
//  0x04 STATUS
//       [0] BUSY
//       [1] DONE
//       [2] ACCEPT
//       [3] REJECT
//       [4] IRQ_PENDING
//       [8:5] CURRENT_STATE
//       [9] INPUT_ERR   - input written while BUSY=0
//  0x08 START_STATE
//  0x0C ACCEPT_MASK
//       bit[i] = 1 if state i is an accepting state
//  0x10 INPUT
//       [SYMBOL_BITS-1:0] symbol class
//       [8] LAST        - marks final symbol in this string
//  0x40 + 4*n TRANSITION TABLE
//       n = state * NUM_SYMBOLS + symbol
//       value = next state
//
//  Notes
//  -----
//  - ready is always 1, so the block is easy to poll.
//  - irq is provided as a sticky completion pulse source, but
//    software can ignore it and poll STATUS instead.
// ============================================================

module dfa_accelerator #(
    parameter integer NUM_STATES  = 8,
    parameter integer SYMBOL_BITS = 2
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [31:0] raddr,
    input  wire [31:0] waddr,
    input  wire        re,
    input  wire        we,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    output wire        ready,
    output wire        irq
);

    localparam integer NUM_SYMBOLS = (1 << SYMBOL_BITS);
    localparam integer STATE_BITS  = (NUM_STATES <= 2)  ? 1 :
                                     (NUM_STATES <= 4)  ? 2 :
                                     (NUM_STATES <= 8)  ? 3 :
                                     (NUM_STATES <= 16) ? 4 : 5;
    localparam integer TRANS_COUNT = NUM_STATES * NUM_SYMBOLS;

    localparam [7:0] REG_CONTROL     = 8'h00;
    localparam [7:0] REG_STATUS      = 8'h04;
    localparam [7:0] REG_START_STATE = 8'h08;
    localparam [7:0] REG_ACCEPT_MASK = 8'h0C;
    localparam [7:0] REG_INPUT       = 8'h10;
    localparam [7:0] REG_TRANS_BASE  = 8'h40;

    reg [STATE_BITS-1:0] start_state;
    reg [NUM_STATES-1:0] accept_mask;
    reg [STATE_BITS-1:0] current_state;
    reg                  busy;
    reg                  done;
    reg                  reject;
    reg                  irq_pending;
    reg                  input_err;

    reg [STATE_BITS-1:0] trans_table [0:TRANS_COUNT-1];

    wire [7:0] raddr_lo = raddr[7:0];
    wire [7:0] waddr_lo = waddr[7:0];

    wire control_write = we && (waddr_lo == REG_CONTROL);
    wire input_write   = we && (waddr_lo == REG_INPUT);
    wire trans_write   = we && (waddr_lo >= REG_TRANS_BASE) &&
                         (waddr_lo < (REG_TRANS_BASE + (TRANS_COUNT * 4)));

    wire start_cmd     = control_write && wdata[0];
    wire reset_ctx_cmd = control_write && wdata[1];
    wire clear_irq_cmd = control_write && wdata[2];

    wire [SYMBOL_BITS-1:0] input_symbol = wdata[SYMBOL_BITS-1:0];
    wire                   input_last   = wdata[8];

    wire [STATE_BITS-1:0] next_state;
    wire                  next_accept;

    wire [7:0] trans_word_index = (waddr_lo - REG_TRANS_BASE) >> 2;
    wire [7:0] read_trans_index = (raddr_lo - REG_TRANS_BASE) >> 2;

    assign next_state = trans_table[{current_state, input_symbol}];
    assign next_accept = accept_mask[next_state];

    assign ready = 1'b1;
    assign irq   = irq_pending;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_state  <= {STATE_BITS{1'b0}};
            accept_mask  <= {NUM_STATES{1'b0}};
            current_state <= {STATE_BITS{1'b0}};
            busy         <= 1'b0;
            done         <= 1'b0;
            reject       <= 1'b0;
            irq_pending  <= 1'b0;
            input_err    <= 1'b0;
            for (i = 0; i < TRANS_COUNT; i = i + 1)
                trans_table[i] <= {STATE_BITS{1'b0}};
        end else begin
            if (clear_irq_cmd)
                irq_pending <= 1'b0;

            if (we && (waddr_lo == REG_START_STATE))
                start_state <= wdata[STATE_BITS-1:0];

            if (we && (waddr_lo == REG_ACCEPT_MASK))
                accept_mask <= wdata[NUM_STATES-1:0];

            if (trans_write)
                trans_table[trans_word_index] <= wdata[STATE_BITS-1:0];

            if (reset_ctx_cmd) begin
                current_state <= start_state;
                busy          <= 1'b0;
                done          <= 1'b0;
                reject        <= 1'b0;
                irq_pending   <= 1'b0;
                input_err     <= 1'b0;
            end

            if (start_cmd) begin
                current_state <= start_state;
                busy          <= 1'b1;
                done          <= 1'b0;
                reject        <= 1'b0;
                irq_pending   <= 1'b0;
                input_err     <= 1'b0;
            end

            if (input_write) begin
                if (!busy) begin
                    input_err <= 1'b1;
                end else begin
                    current_state <= next_state;
                    if (input_last) begin
                        busy        <= 1'b0;
                        done        <= 1'b1;
                        reject      <= !next_accept;
                        irq_pending <= 1'b1;
                    end
                end
            end
        end
    end

    always @(*) begin
        rdata = 32'h0000_0000;
        case (raddr_lo)
            REG_CONTROL: begin
                rdata = 32'h0000_0000;
            end
            REG_STATUS: begin
                rdata[0] = busy;
                rdata[1] = done;
                rdata[2] = accept_mask[current_state];
                rdata[3] = reject;
                rdata[4] = irq_pending;
                rdata[8:5] = current_state;
                rdata[9] = input_err;
            end
            REG_START_STATE: begin
                rdata[STATE_BITS-1:0] = start_state;
            end
            REG_ACCEPT_MASK: begin
                rdata[NUM_STATES-1:0] = accept_mask;
            end
            REG_INPUT: begin
                rdata[STATE_BITS-1:0] = current_state;
                rdata[8] = busy;
            end
            default: begin
                if ((raddr_lo >= REG_TRANS_BASE) &&
                    (raddr_lo < (REG_TRANS_BASE + (TRANS_COUNT * 4)))) begin
                    rdata[STATE_BITS-1:0] = trans_table[read_trans_index];
                end else begin
                    rdata = 32'hDEAD_BEEF;
                end
            end
        endcase
    end

endmodule
