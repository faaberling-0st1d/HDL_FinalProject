module PhysicsEngine #(
    parameter START_X = 0,
    parameter START_Y = 0
)(
    input clk,
    input rst,

    input [2:0] state, // From StateEncoder

    input [2:0] operation_code, // From OperationEncoder Module
    input       boost,          // From OperationEncoder Module

    output reg [9:0] pos_x,
    output reg [9:0] pos_y,
    output reg [8:0] angle
);
    /* [Speed, Acceleration, Angle] */
    reg signed [9:0] speed, next_speed;
    reg signed [9:0] acceleration, next_acceleration;
    reg        [8:0] next_angle;
    localparam ANGLE_NUM = 9'd360;
    // Map constraints
    localparam MAP_MAX_X = 10'd320, MAP_MAX_Y = 10'd240;

    /* [Position (Coordinates)] */
    reg       [9:0] next_pos_x;
    reg       [9:0] next_pos_y;

    /* [Operations] */
    localparam NIL      = 3'd0;
    localparam FORWARD  = 3'd1;
    localparam BACKWARD = 3'd2;
    localparam LEFT     = 3'd3;
    localparam RIGHT    = 3'd4;

    /* [States] */
    // Local parameters
    localparam IDLE      = 3'd0;
    localparam SETTING   = 3'd1;
    localparam COUNTDOWN = 3'd3;
    localparam RACING    = 3'd4;
    localparam PAUSE     = 3'd5;
    localparam FINISH    = 3'd6;

    /* [Sequential Circuit]
     * `acceleration`, `speed`
     */
    always @(posedge clk) begin
        if (rst) begin
            speed        <= 10'd0;
            acceleration <= 10'd0;
            angle        <= 9'd0;
            
            pos_x <= START_X;
            pos_y <= START_Y;
            
        end else begin
            speed        <= next_speed;
            acceleration <= next_acceleration;
            angle        <= next_angle;

            pos_x <= next_pos_x;
            pos_y <= next_pos_y;
        end
    end

    /* [I. Acceleration Combinational Logic] */
    always @(*) begin
        // DEFAULT
        next_acceleration = acceleration;

        case (state)
            RACING: begin
                if (operation_code != NIL) begin
                    next_acceleration = (boost) ? 10'd20 : 10'd5 /* 上下左右自然加上速 */;
                end else begin
                    next_acceleration = (speed == 10'd0) ? 10'd0 : -10'd5 /* 自然減速 */;
                end
            end

            PAUSE:   next_acceleration = acceleration; // Remain the same value.
            default: next_acceleration = 10'd0;
        endcase
    end
    

    /* [II. Speed Combinational Logic] */
    always @(*) begin
        // DEFAULT
        next_speed = speed;

        case (state)
            RACING: begin
                next_speed = (speed + acceleration < 0) ? 10'd0 /* Remain 0 if the sum is less than 0 */ : speed + acceleration;
            end
            PAUSE:   next_speed = speed;
            default: next_speed = 10'd0;
        endcase
    end

    /* [III. Angle Combinational Logic] */
    always @(*) begin
        // DEFAULT
        next_angle = angle;

        if (state == RACING) begin
            if      (operation_code == LEFT)  next_angle = (angle == 9'b0) ? ANGLE_NUM-1 : angle-1;
            else if (operation_code == RIGHT) next_angle = (angle == ANGLE_NUM-1) ? 9'b0 : angle+1;
        end
    end

    /* [IV. Coordinate(Position) Combinational Logic] */
    always @(*) begin
        next_pos_x = pos_x;
        next_pos_y = pos_y;

        if (state == RACING) begin
            case (operation_code)
                FORWARD:  next_pos_y = pos_y + 1; // 先用常數 1 測試
                BACKWARD: next_pos_y = pos_y - 1;
                LEFT:     next_pos_x = pos_x - 1;
                RIGHT:    next_pos_x = pos_x + 1;
                default: ; 
            endcase
        end
    end
    // always @(*) begin
    //     next_pos_x = pos_x;
    //     next_pos_y = pos_y;

    //     if (state == RACING) begin
    //         case (operation_code)
    //             FORWARD: begin
    //                 if ($signed({2'b0, pos_y}) + $signed(speed) >= MAP_MAX_Y) 
    //                     next_pos_y = MAP_MAX_Y - 1;
    //                 else if ($signed({2'b0, pos_y}) + $signed(speed) <= 0)
    //                     next_pos_y = 0;
    //                 else
    //                     next_pos_y = pos_y + speed;
    //             end
    //             BACKWARD: begin
    //                 next_pos_y = (pos_y <= speed) ? 0 : pos_y - 2;
    //             end
    //             LEFT: begin
    //                 next_pos_x = (pos_x <= speed) ? 0 : pos_x - 2;
    //             end
    //             RIGHT: begin
    //                 next_pos_x = (pos_x >= MAP_MAX_X - speed) ? pos_x : pos_x + 2;
    //             end
    //             default: begin
    //                 next_pos_x = pos_x;
    //                 next_pos_y = pos_y;
    //             end
    //         endcase
    //     end
    // end
endmodule