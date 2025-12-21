module OperationEncoder (
    input clk,
    input rst,

    inout wire PS2_DATA,
    inout wire PS2_CLK,

    input [2:0] state, 
    
    output reg [1:0] p1_h_code, // Left Cart Steering (Left/Right)
    output reg [1:0] p1_v_code, // Left Cart Throttle (Gas/Brake)
    output reg       p1_boost,  // Left Cart Turbo
    output reg       p1_honk,   // Left Cart Honk

    output reg [1:0] p2_h_code, 
    output reg [1:0] p2_v_code, 
    output reg       p2_boost, 
    output reg       p2_honk 
);

    /* [Keyboard Decoder] */
    wire [511:0] key_pressed;
    wire [8:0] last_change;
    wire been_ready; // 我們可以忽略這個訊號，直接讀 key_pressed
    
    KeyboardDecoder KD(
        .key_down(key_pressed),
        .last_change(last_change),
        .key_valid(been_ready),
        .PS2_DATA(PS2_DATA),
        .PS2_CLK(PS2_CLK),
        .rst(rst),
        .clk(clk)
    );

    /* [Key Codes Definition] */
    // P1 Keys
    localparam KEY_W = 9'h1D;
    localparam KEY_A = 9'h1C;
    localparam KEY_S = 9'h1B;
    localparam KEY_D = 9'h23;
    localparam KEY_SPACE = 9'h29;
    localparam KEY_L_SHIFT = 9'h12;

    // P2 Keys
    localparam KEY_I = 9'h43;
    localparam KEY_J = 9'h3B;
    localparam KEY_K = 9'h42;
    localparam KEY_L = 9'h4B;
    localparam KEY_NUM_0 = 9'h70;
    localparam KEY_R_SHIFT = 9'h59;

    /* [States & Constants] */
    localparam RACING = 3'd4;
    
    localparam H_NIL   = 2'd0;
    localparam H_LEFT  = 2'd1;
    localparam H_RIGHT = 2'd2;
    
    localparam V_NIL   = 2'd0;
    localparam V_UP    = 2'd1; // Gas
    localparam V_DOWN  = 2'd2; // Brake/Reverse

    /* [Sequential Logic] */
    always @(posedge clk) begin
        if (rst) begin
            // Reset logic...
            p1_h_code <= H_NIL; p1_v_code <= V_NIL; p1_boost <= 0; p1_honk <= 0;
            p2_h_code <= H_NIL; p2_v_code <= V_NIL; p2_boost <= 0; p2_honk <= 0;
        end else begin
            // 預設值：如果在 RACING 以外的狀態，車子應該停止
            p1_h_code <= H_NIL; p1_v_code <= V_NIL; p1_boost <= 0; p1_honk <= 0;
            p2_h_code <= H_NIL; p2_v_code <= V_NIL; p2_boost <= 0; p2_honk <= 0;

            if (state == RACING) begin
                // --- PLAYER 1 ---
                
                // 1. 轉向 (Steering) - 互斥邏輯
                if (key_pressed[KEY_A] && !key_pressed[KEY_D])      p1_h_code <= H_LEFT;
                else if (key_pressed[KEY_D] && !key_pressed[KEY_A]) p1_h_code <= H_RIGHT;
                else                                                p1_h_code <= H_NIL;

                // 2. 油門 (Throttle) - 互斥邏輯
                if (key_pressed[KEY_W] && !key_pressed[KEY_S])      p1_v_code <= V_UP;
                else if (key_pressed[KEY_S] && !key_pressed[KEY_W]) p1_v_code <= V_DOWN;
                else                                                p1_v_code <= V_NIL;

                // 3. 功能鍵
                p1_boost <= key_pressed[KEY_L_SHIFT];
                p1_honk  <= key_pressed[KEY_SPACE];

                // --- PLAYER 2 ---
                
                // 1. 轉向
                if (key_pressed[KEY_J] && !key_pressed[KEY_L])      p2_h_code <= H_LEFT;
                else if (key_pressed[KEY_L] && !key_pressed[KEY_J]) p2_h_code <= H_RIGHT;
                else                                                p2_h_code <= H_NIL;

                // 2. 油門
                if (key_pressed[KEY_I] && !key_pressed[KEY_K])      p2_v_code <= V_UP;
                else if (key_pressed[KEY_K] && !key_pressed[KEY_I]) p2_v_code <= V_DOWN;
                else                                                p2_v_code <= V_NIL;

                // 3. 功能鍵
                p2_boost <= key_pressed[KEY_R_SHIFT];
                p2_honk  <= key_pressed[KEY_NUM_0];
            end 
        end
    end

endmodule