/* [OPERATION ENCODER]
 * Encoding operations based on the key pressed on the keyboard.
 */

module OperationEncoder (
    input clk,
    input rst,

	inout wire PS2_DATA,
	inout wire PS2_CLK,

    input [2:0] state, // Current state from the FSM (StateEncoder)
    
    output reg [2:0] p1_operation_code, // Left Cart Direction.
    output reg       p1_boost,          // Left Cart Speed-up.
    output reg       p1_honk,           // Left Cart Honk

    output reg [2:0] p2_operation_code, // Right Cart Direction.
    output reg       p2_boost,          // Right Cart Speed-up
    output reg       p2_honk            // Right Cart Honk
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

    /* [Left Cart Key Codes] */
    // Up, left, down, right
    localparam KEY_W = 9'b0_0001_1101; // 1D
    localparam KEY_A = 9'b0_0001_1100; // 1C
    localparam KEY_S = 9'b0_0001_1011; // 1B
    localparam KEY_D = 9'b0_0010_0011; // 23
    // Honk
    localparam KEY_SPACE = 9'b0_0010_1001; // 29
    // Boost
    localparam KEY_LEFT_SHIFT  = 9'b0_0001_0010; // 12

    /* [Right Cart Key Codes] */
    // Up, left, down, right
    localparam KEY_UP    = 9'b1_0111_0101; // E0 75
    localparam KEY_LEFT  = 9'b1_0110_1011; // E0 6B
    localparam KEY_DOWN  = 9'b1_0111_0010; // E0 72
    localparam KEY_RIGHT = 9'b1_0111_0100; // E0 70
    // Honk
    localparam KEY_NUM_0 = 9'b0_0111_0000; // 70
    // Boost
    localparam KEY_RIGHT_SHIFT = 9'b0_0101_1001; // 59

    wire is_p1_moving = (key_down[KEY_W]  && key_down[KEY_A]    && key_down[KEY_S]    && key_down[KEY_D]);
    wire is_p2_moving = (key_down[KEY_UP] && key_down[KEY_LEFT] && key_down[KEY_DOWN] && key_down[KEY_RIGHT]);

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
    localparam NIL   = 3'd0;
    localparam UP    = 3'd1;
    localparam DOWN  = 3'd2;
    localparam LEFT  = 3'd3;
    localparam RIGHT = 3'd4;

    /* [Sequential] */
    always @(posedge clk) begin
        if (rst) begin
            p1_operation_code <= NIL;
            p1_boost          <= 0;
            p1_honk           <= 0;

            p2_operation_code <= NIL;
            p2_boost          <= 0;
            p2_honk           <= 0;

        end else begin
            p1_operation_code <= NIL;
            p1_boost          <= 0;
            p1_honk           <= 0;

            p2_operation_code <= NIL;
            p2_boost          <= 0;
            p2_honk           <= 0;

            if (state == RACING) begin
                if (been_ready) begin
                    /* LEFT CART */
                    if      (key_down[KEY_W]) p1_operation_code <= UP;
                    else if (key_down[KEY_S]) p1_operation_code <= DOWN;
                    else if (key_down[KEY_A]) p1_operation_code <= LEFT;
                    else if (key_down[KEY_D]) p1_operation_code <= RIGHT;
                    else                      p1_operation_code <= NIL;
                    // Boost if LEFT SHIFT is pressed && the left cart IS moving.
                    if (is_p1_moving && key_down[KEY_LEFT_SHIFT]) begin
                        p1_boost <= 1;
                    end
                    // Honk if SPACE is pressed.
                    if (key_down[KEY_SPACE]) begin
                        p1_honk <= 1;
                    end

                    /* RIGHT CART */
                    if      (key_down[KEY_UP])    p2_operation_code <= UP;
                    else if (key_down[KEY_DOWN])  p2_operation_code <= DOWN;
                    else if (key_down[KEY_LEFT])  p2_operation_code <= LEFT;
                    else if (key_down[KEY_RIGHT]) p2_operation_code <= RIGHT;
                    else                          p2_operation_code <= NIL;
                    // Boost if RIGHT SHIFT is pressed && the right cart IS moving.
                    if (is_p2_moving && key_down[KEY_RIGHT_SHIFT]) begin
                        p2_boost <= 1;
                    end
                    // Honk if NUM 0 is pressed.
                    if (key_down[KEY_NUM_0]) begin
                        p2_honk <= 1;
                    end
                end      
            end
        end
    end

endmodule