(* use_dsp = "no" *)
module PhysicsEngine #(
    parameter START_X = 0,
    parameter START_Y = 0
)(
    input clk,
    input rst,

    input [2:0] state, // From StateEncoder

    input [1:0] h_code, // From OperationEncoder Module. Horizontal Movement Code.
    input [1:0] v_code, // From OperationEncoder Module. Vertical Movement Code.
    input       boost,          // From OperationEncoder Module

    output reg [9:0] pos_x,
    output reg [9:0] pos_y,
    output reg [8:0] angle,

    output reg [9:0] speed_out
);
    /* [Speed, Acceleration, Angle] */
    reg signed [9:0] speed, next_speed;
    reg signed [9:0] acceleration, next_acceleration;
    reg        [8:0] next_angle;
    // Target angle
    reg        [8:0] target_angle;
    localparam ANGLE_NUM = 9'd360;
    // Map constraints
    localparam MAP_MAX_X = 10'd320, MAP_MAX_Y = 10'd240;

    /* [Position (Coordinates)] */
    reg       [9:0] next_pos_x;
    reg       [9:0] next_pos_y;

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
     * `acceleration`, `speed`
     */
    always @(posedge clk) begin
        if (rst) begin
            speed_out    <= 10'd0; // Debug
            speed        <= 10'd0;
            acceleration <= 10'd0;
            angle        <= 9'd0;
            
            pos_x <= START_X;
            pos_y <= START_Y;
            
        end else begin
            speed_out    <= speed; // Debug
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
                if ({h_code, v_code} != {H_NIL, V_NIL}) begin
                    next_acceleration = (boost) ? 10'd5 : 10'd1 /* 上下左右自然加上速 */;
                end else begin
                    next_acceleration = (speed == 10'd0) ? 10'd0 : -10'd1 /* 自然減速 */;
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
                if (speed + acceleration > 10'd30) next_speed = 10'd30;
                else if (speed + acceleration < 0) next_speed = 10'd0; /* Remain 0 if the sum is less than 0 */
                else                               next_speed = speed + acceleration;
            end
            PAUSE:   next_speed = speed;
            default: next_speed = 10'd0;
        endcase
    end

    /* [Target Angle] */
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
                default: target_angle <= 9'd0;
            endcase
        end
    end

    /* [III. Angle Combinational Logic] */
    always @(*) begin
        // DEFAULT
        next_angle = angle;

        if (state == RACING && movement_code != {H_NIL, V_NIL}) begin
            if (angle > target_angle)      next_angle = angle - 1;
            else if (angle < target_angle) next_angle = angle + 1;
            else                           next_angle = angle;
        end
    end

    /* [IV. Coordinate(Position) Combinational Logic] */
    always @(*) begin
        next_pos_x = pos_x;
        next_pos_y = pos_y;

        if (state == RACING) begin
            case (h_code)
                H_LEFT: begin
                    next_pos_x = pos_x - 1;
                end
                H_RIGHT: begin
                    next_pos_x = pos_x + 1;
                end
                default: ;
            endcase
            
            case (v_code)
                V_UP: begin
                    next_pos_y = pos_y - 1;
                end
                V_DOWN: begin
                    next_pos_y = pos_y + 1;
                end
                default: ;
            endcase
        end
    end
endmodule