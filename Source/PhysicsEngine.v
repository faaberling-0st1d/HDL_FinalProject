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
    reg signed [7:0] speed, next_speed;
    reg signed [7:0] acceleration, next_acceleration;
    reg        [3:0] next_angle;
    parameter ANGLE_NUM = 360;
    // Map constraints
    parameter MAP_MAX_X = 320, MAP_MAX_Y = 240;

    /* [Position (Coordinates)] */
    reg       [15:0] next_pos_x;
    reg       [15:0] next_pos_y;

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
            speed        <= 8'd0;
            acceleration <= 8'd0;
            angle        <= 8'd0;
            
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
                    next_acceleration = (boost) ? 8'd20 : 8'd5 /* 上下左右自然加上速 */;
                end else begin
                    next_acceleration = (speed == 8'd0) ? 8'd0 : -8'd5 /* 自然減速 */;
                end
            end

            PAUSE:   next_acceleration = acceleration; // Remain the same value.
            default: next_acceleration = 8'd0;
        endcase
    end
    

    /* [II. Speed Combinational Logic] */
    always @(*) begin
        // DEFAULT
        next_speed = speed;

        case (state)
            RACING: begin
                next_speed = (speed + acceleration < 0) ? 8'd0 /* Remain 0 if the sum is less than 0 */ : speed + acceleration;
            end
            PAUSE:   next_speed = speed;
            default: next_speed = 8'd0;
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

        case (operation_code)
            FORWARD: begin
                next_pos_y = (pos_y == MAP_MAX_Y - 1) ? pos_y : pos_y + 1;
            end
            BACKWARD: begin
                next_pos_y = (pos_y == 0) ? pos_y : pos_y - 1;
            end
            LEFT: begin
                next_pos_x = (pos_x == 0) ? pos_x : pos_x + 1;
            end
            RIGHT: begin
                next_pos_x = (pos_x == MAP_MAX_X - 1) ? pos_x : pos_x + 1;
            end
        endcase
    end
endmodule