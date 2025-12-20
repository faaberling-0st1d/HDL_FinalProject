/* [OPERATION ENCODER]
 * Encoding operations based on the key pressed on the keyboard.
 */

module OperationEncoder (
    input clk,
    input rst,

	inout wire PS2_DATA,
	inout wire PS2_CLK,

    input [2:0] state, // Current state from the FSM (StateEncoder)
    
    output reg [1:0] p1_h_code, // Left Cart Horizontal Direction.
    output reg [1:0] p1_v_code, // Left Cart Vertical Direction.
    output reg       p1_boost,  // Left Cart Speed-up.
    output reg       p1_honk,   // Left Cart Honk

    output reg [1:0] p2_h_code, // Right Cart Horizontal Direction.
    output reg [1:0] p2_v_code, // Right Cart Vertical Direction.
    output reg       p2_boost,  // Right Cart Speed-up
    output reg       p2_honk    // Right Cart Honk
);

    /* [Keyboard Decoder] */
    wire [511:0] key_pressed; // 改了名字，要不然可能跟 KEY_DOWN 衝突。
	wire [8:0] last_change;
	wire been_ready;
    KeyboardDecoder KD(
        .key_down(key_pressed),
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
    localparam KEY_I = 9'b0_0100_0011; // 43
    localparam KEY_J = 9'b0_0011_1011; // 3B
    localparam KEY_K = 9'b0_0100_0010; // 42
    localparam KEY_L = 9'b0_0100_1011; // 4B
    // Honk
    localparam KEY_NUM_0 = 9'b0_0111_0000; // 70
    // Boost
    localparam KEY_RIGHT_SHIFT = 9'b0_0101_1001; // 59

    wire is_p1_moving = (key_pressed[KEY_W] && key_pressed[KEY_A] && key_pressed[KEY_S] && key_pressed[KEY_D]);
    wire is_p2_moving = (key_pressed[KEY_I] && key_pressed[KEY_J] && key_pressed[KEY_K] && key_pressed[KEY_L]);

    /* [States] */
    // Local parameters
    localparam IDLE      = 3'd0;
    localparam SETTING   = 3'd1;
    localparam SYNCING   = 3'd2;
    localparam COUNTDOWN = 3'd3;
    localparam RACING    = 3'd4;
    localparam PAUSE     = 3'd5;
    localparam FINISH    = 3'd6;

    /* [Operations (Horizontal)] */
    localparam H_NIL   = 2'd0;
    localparam H_LEFT  = 2'd1;
    localparam H_RIGHT = 2'd2;
    /* [Operations (Vertical)] */
    localparam V_NIL   = 2'd0;
    localparam V_UP    = 2'd1;
    localparam V_DOWN  = 2'd2;

    /* [Sequential] */
    always @(posedge clk) begin
        if (rst) begin
            p1_h_code <= H_NIL;
            p1_v_code <= V_NIL;
            p1_boost  <= 0;
            p1_honk   <= 0;

            p2_h_code <= H_NIL;
            p2_v_code <= V_NIL;
            p2_boost  <= 0;
            p2_honk   <= 0;

        end else begin
            p1_h_code <= H_NIL;
            p1_v_code <= V_NIL;
            p1_boost  <= 0;
            p1_honk   <= 0;

            p2_h_code <= H_NIL;
            p2_v_code <= V_NIL;
            p2_boost  <= 0;
            p2_honk   <= 0;

            if (state == RACING) begin
                if (been_ready) begin
                    /* LEFT CART */
                    // Vertical
                    if      (key_pressed[KEY_W]) p1_v_code <= V_UP;
                    else if (key_pressed[KEY_S]) p1_v_code <= V_DOWN;
                    else                         p1_v_code <= V_NIL;
                    // Horizontal
                    if      (key_pressed[KEY_A]) p1_h_code <= H_LEFT;
                    else if (key_pressed[KEY_D]) p1_h_code <= H_RIGHT;
                    else                         p1_h_code <= H_NIL;
                    // Boost if LEFT SHIFT is pressed && the left cart IS moving.
                    if (is_p1_moving && key_pressed[KEY_LEFT_SHIFT]) p1_boost <= 1;
                    // Honk if SPACE is pressed.
                    if (key_pressed[KEY_SPACE]) p1_honk <= 1;

                    /* RIGHT CART */
                    // Vertical
                    if      (key_pressed[KEY_I]) p2_v_code <= V_UP;
                    else if (key_pressed[KEY_K]) p2_v_code <= V_DOWN;
                    else                         p2_v_code <= V_NIL;
                    // Horizontal
                    if      (key_pressed[KEY_J]) p2_h_code <= H_LEFT;
                    else if (key_pressed[KEY_L]) p2_h_code <= H_RIGHT;
                    else                         p2_h_code <= H_NIL;
                    // Boost if RIGHT SHIFT is pressed && the right cart IS moving.
                    if (is_p2_moving && key_pressed[KEY_RIGHT_SHIFT]) p2_boost <= 1;
                    // Honk if NUM 0 is pressed.
                    if (key_pressed[KEY_NUM_0]) p2_honk <= 1;
                end      
            end
        end
    end

endmodule