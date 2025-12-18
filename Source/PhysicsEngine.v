module PhysicsEngin (
    input clk,
    input rst,

    input [2:0] state, // From StateEncoder

    input [2:0] operation_code, // From OperationEncoder Module
    input       boost,          // From OperationEncoder Module

    output reg [15:0] pos_x,
    output reg [15:0] pos_y,
    output reg [3:0] angle_index // 在 verilog 裡面寫三角函數有點複雜，直接指定轉彎的 index 對應車體動畫幀數。
);
    /* [Speed, Acceleration, Angle] */
    reg signed [7:0] speed, next_speed;
    reg signed [7:0] acceleration, next_acceleration;
    reg        [3:0] next_angle_index;
    parameter ANGLE_NUM = 16;

    /* [Position (Coordinates)] */
    reg       [15:0] next_pos_x;
    reg       [15:0] next_pos_y;
    parameter [15:0] START_X = 16'd0;
    parameter [15:0] START_Y = 16'd0;

    /* [Operations] */
    localparam NIL      = 3'd0;
    localparam FORWARD  = 3'd1;
    localparam BACKWARD = 3'd2;
    localparam LEFT     = 3'd3;
    localparam RIGHT    = 3'd4;

    /* [Sequential Circuit]
     * `acceleration`, `speed`
     */
    always @(posedge clk) begin
        if (rst) begin
            speed        <= 8'd0;
            acceleration <= 8'd0;
            angle_index  <= 8'd0;
            
            pos_x <= START_X;
            pos_y <= START_Y;
            
        end else begin
            speed        <= next_speed;
            acceleration <= next_acceleration;
            angle_index  <= next_angle_index;

            pos_x <= next_pos_x;
            pos_y <= next_pos_y;
        end
    end

    /* [I. Acceleration Combinational Logic] */
    always @(*) begin
        // DEFAULT
        next_acceleration = 8'd0;

        if (operation_code != NIL) begin
            next_acceleration = (boost) ? 8'd20 : 8'd5 /* 上下左右自然加上速 */;
        end else begin
            next_acceleration = (speed == 8'd0) ? 8'd0 : -8'd5 /* 自然減速 */;
        end
    end
    

    /* [II. Speed Combinational Logic] */
    always @(*) begin
        next_speed = (speed + acceleration < 0) ? 8'd0 /* Remain 0 if the sum is less than 0 */ : speed + acceleration;
    end

    /* [III. Angle Combinational Logic] */
    always @(*) begin
        next_angle_index = angle_index;
        if (operation_code == LEFT) begin
            next_angle_index = (angle_index + ANGLE_NUM - 1) % ANGLE_NUM;

        end else if (operation_code == RIGHT) begin
            next_angle_index = (angle_index + 1) % ANGLE_NUM;
        end
    end

    /* [IV. Coordinate(Position) Combinational Logic] */
    always @(*) begin
        next_pos_x = pos_x;
        next_pos_y = pos_y;
    end
endmodule