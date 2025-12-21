(* use_dsp = "no" *)
module PhysicsEngine #(
    parameter START_X = 0,
    parameter START_Y = 0
)(
    input clk,
    input rst,

    input [2:0] state, // From StateEncoder

    input [1:0] h_code, // From OperationEncoder Module
    input [1:0] v_code, // From OperationEncoder Module
    input       boost,          // From OperationEncoder Module

    output wire [9:0] pos_x,
    output wire [9:0] pos_y,
    output reg [8:0] angle,

    output reg [9:0] speed_out
);
    /* [Speed, Acceleration, Angle] */
    reg signed [9:0] speed;
    reg signed [9:0] acceleration, next_acceleration;
    reg        [8:0] next_angle;
    // Target angle
    reg        [8:0] target_angle;
    localparam ANGLE_NUM = 9'd360;
    // Map constraints
    localparam MAP_MAX_X = 10'd320, MAP_MAX_Y = 10'd240;

    /* [Position (Coordinates)] */
    // reg       [9:0] next_pos_x;
    // reg       [9:0] next_pos_y;

    /* [Operations (Horizontal)] */
    localparam H_NIL   = 2'd0;
    localparam H_LEFT  = 2'd1;
    localparam H_RIGHT = 2'd2;
    /* [Operations (Vertical)] */
    localparam V_NIL   = 2'd0;
    localparam V_UP    = 2'd1;
    localparam V_DOWN  = 2'd2;
    // Operation Code
    wire [3:0] movement_code = {h_code, v_code};

    /* [States] */
    // Local parameters
    localparam IDLE      = 3'd0;
    localparam SETTING   = 3'd1;
    localparam COUNTDOWN = 3'd3;
    localparam RACING    = 3'd4;
    localparam PAUSE     = 3'd5;
    localparam FINISH    = 3'd6;

    /* [Sequential Circuit]
     * `acceleration`, `angle`
     */
    always @(posedge clk) begin
        if (rst) begin
            speed_out    <= 10'd0; // Debug
            acceleration <= 10'd0;
            angle        <= 9'd0;
            
        end else begin
            speed_out    <= speed; // Debug
            acceleration <= next_acceleration;
            angle        <= next_angle;
        end
    end

    /* [I. Acceleration Combinational Logic] */
    always @(*) begin
        // DEFAULT
        next_acceleration = acceleration;

        case (state)
            RACING: begin
                if (movement_code != {H_NIL, V_NIL}) begin
                    next_acceleration = (boost) ? 10'd5 : 10'd1 /* 上下左右自然加上速 */;
                end else begin
                    next_acceleration = (speed == 10'd0) ? 10'd0 : -10'd1 /* 自然減速 */;
                end
            end

            PAUSE:   next_acceleration = acceleration; // Remain the same value.
            default: next_acceleration = 10'd0;
        endcase
    end

    /* [II. Target Angle] */
    always @(posedge clk) begin
        if (rst) begin
            target_angle <= 9'd0;
        end else begin
            case (movement_code)
                {H_NIL,   V_UP  }: target_angle <= 9'd0;
                {H_RIGHT, V_UP  }: target_angle <= 9'd45;
                {H_RIGHT, V_NIL }: target_angle <= 9'd90;
                {H_RIGHT, V_DOWN}: target_angle <= 9'd135;
                {H_NIL,   V_DOWN}: target_angle <= 9'd180;
                {H_LEFT,  V_DOWN}: target_angle <= 9'd225;
                {H_LEFT,  V_NIL }: target_angle <= 9'd270;
                {H_LEFT,  V_UP  }: target_angle <= 9'd315;
                default:           target_angle <= target_angle; // 維持原狀
            endcase
        end
    end

    /* [III. Angle Combinational Logic] */
    always @(*) begin
        // DEFAULT
        next_angle = target_angle;
    end

    /* [IV. Angle Look-Up Table] */
    
    reg signed [17:0] fx_pos_x, fx_pos_y; // 10 位整數，8 位小數。
    reg signed [15:0] dx, dy; // 移動量

    // 使用 8-bit 精度: 1.0 = 256, 0.707 = 181
    always @(*) begin
        case (angle)
            // Original 8 directions:
            9'd0:    begin dx =  16'd0;   dy = -16'd256; end // Up
            9'd45:   begin dx =  16'd181; dy = -16'd181; end // Up-Right
            9'd90:   begin dx =  16'd256; dy =  16'd0;   end // Right
            9'd135:  begin dx =  16'd181; dy =  16'd181; end // Down-Right
            9'd180:  begin dx =  16'd0;   dy =  16'd256; end // Down
            9'd225:  begin dx = -16'd181; dy =  16'd181; end // Down-Left
            9'd270:  begin dx = -16'd256; dy =  16'd0;   end // Left
            9'd315:  begin dx = -16'd181; dy = -16'd181; end // Up-Left
            // Extra 8 directions:
            9'd23:   begin dx =  16'd100; dy = -16'd236; end
            9'd68:   begin dx =  16'd237; dy = -16'd96;  end
            9'd113:  begin dx =  16'd236; dy =  16'd100; end
            9'd158:  begin dx =  16'd96;  dy =  16'd237; end
            9'd203:  begin dx = -16'd100; dy =  16'd236; end
            9'd248:  begin dx = -16'd237; dy =  16'd96;  end
            9'd293:  begin dx = -16'd236; dy = -16'd100; end
            9'd338:  begin dx = -16'd96;  dy = -16'd237; end
            default: begin dx =  16'd0;   dy =  16'd0;   end
        endcase
    end

    /* [VI. Coordinate Update] */
    // Physics Tick Generator
    // 每 10ms (100Hz) 更新一次物理邏輯
    reg [20:0] physics_tick_cnt;
    localparam [20:0] PHYSICS_TICK_TIME = 21'd1_000_000; // 100MHz / 1_000_000 = 100Hz
    wire physics_tick = (physics_tick_cnt >= PHYSICS_TICK_TIME - 1);
    
    always @(posedge clk) begin
        if (rst) physics_tick_cnt <= 0;
        else begin
            if (physics_tick)
                physics_tick_cnt <= 0;
            else
                physics_tick_cnt <= physics_tick_cnt + 1;
        end
    end

    /* [VII. Integrated Physics Logic] */
    always @(posedge clk) begin
        if (rst) begin
            speed <= 10'd0;
            fx_pos_x <= START_X << 8;
            fx_pos_y <= START_Y << 8;

        end else if (state == RACING) begin
            if (physics_tick) begin
                if (movement_code != {H_NIL, V_NIL}) begin
                    // Speed Up (加速)
                    if (speed + (boost ? 10'd5 : 10'd1) <= 10'd30)
                        speed <= speed + (boost ? 10'd5 : 10'd1);
                    else
                        speed <= 10'd30;
                end else begin
                    // Inertia (延切線減速)
                    if (speed > 10'd0) speed <= speed - 10'd1;
                    else               speed <= 10'd0;
                end

                fx_pos_x <= fx_pos_x + ($signed(speed) * $signed(dx));
                fx_pos_y <= fx_pos_y + ($signed(speed) * $signed(dy));
            end                
        end else begin
            speed <= 10'd0;
            fx_pos_x <= START_X << 8;
            fx_pos_y <= START_Y << 8;
        end
    end

    assign pos_x = fx_pos_x[17:8]; // Take the integer part.
    assign pos_y = fx_pos_y[17:8]; // Take the integer part.

endmodule