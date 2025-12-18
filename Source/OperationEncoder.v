/* [OPERATION ENCODER]
 * Encoding operations based on the key pressed on the keyboard.
 */

module OperationEncoder (
    input clk,
    input rst,

	inout wire PS2_DATA,
	inout wire PS2_CLK,

    input [2:0] state, // Current state from the FSM (StateEncoder)
    
    output reg [2:0] operation_code, // Direction of the cart.
    output reg       boost  // Speed-up
);

    /* [Keyboard Decoder] */
    wire [511:0] key_down;
	wire [8:0] last_change;
	wire been_ready;
    KeyboardDecoder KD(
        .key_down(key_down),
        .last_change(last_change),
        .key_valid(been_ready),
        .PS2_DATA(PS2_DATA),
        .PS2_CLK(PS2_CLK),
        .rst(rst),
        .clk(clk)
    );

    /* [Key Codes] */
    // Up, left, down, right
    localparam KEY_W = 9'b0_0001_1101; // 1D
    localparam KEY_A = 9'b0_0001_1100; // 1C
    localparam KEY_S = 9'b0_0001_1011; // 1B
    localparam KEY_D = 9'b0_0010_0011; // 23
    // Honk
    localparam KEY_SPACE = 9'b0_0010_1001; // 29
    // Boost
    localparam KEY_LEFT_SHIFT  = 9'b0_0001_0010; // 12
    localparam KEY_RIGHT_SHIFT = 9'b0_0101_1001; // 59

    /* [States] */
    // Local parameters
    localparam IDLE      = 3'd0;
    localparam SETTING   = 3'd1;
    localparam SYNCING   = 3'd2;
    localparam COUNTDOWN = 3'd3;
    localparam RACING    = 3'd4;
    localparam PAUSE     = 3'd5;
    localparam FINISH    = 3'd6;

    /* [Operations] */
    localparam NIL      = 3'd0;
    localparam FORWARD  = 3'd1;
    localparam BACKWARD = 3'd2;
    localparam LEFT     = 3'd3;
    localparam RIGHT    = 3'd4;

    /* [Sequential] */
    always @(posedge clk) begin
        if (rst) begin
            operation_code <= NIL;
            boost          <= 0;

        end else begin
            operation_code <= NIL;
            boost          <= 0;

            if (state == RACING) begin
                if (been_ready) begin
                    // Forward
                    if (key_down[KEY_W]) begin
                        operation_code <= FORWARD;
                    // Backward
                    end else if (key_down[KEY_S]) begin
                        operation_code <= BACKWARD;
                    // Left
                    end else if (key_down[KEY_A]) begin
                        operation_code <= LEFT;
                    // Right
                    end else if (key_down[KEY_D]) begin
                        operation_code <= RIGHT;
                    // No operation
                    end else begin
                        operation_code <= NIL;
                    end

                    // Boost if SHIFT is pressed (either of the two works.)
                    if (key_down[KEY_LEFT_SHIFT] || key_down[KEY_RIGHT_SHIFT]) begin
                        boost <= 1;
                    end
                end      
            end
        end
    end

endmodule