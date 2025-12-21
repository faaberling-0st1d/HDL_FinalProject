module PhysicsEngine #(
    parameter START_X = 0,
    parameter START_Y = 120,
    parameter CLK_FREQ = 100_000_000,
    
    parameter MAP_W = 10'd320,   // 地圖寬
    parameter MAP_H = 10'd240,   // 地圖高
    parameter OFFSET_DIST = 10'd2, // 圓心距離車中心的偏移量
    parameter COLLISION_RSQ = 10'd9
)(
    input clk,
    input rst,
    input [2:0] state,
    input [1:0] h_code, 
    input [1:0] v_code, 
    input boost,       
    
    // 對手碰撞圓
    input [9:0] other_f_x, input [9:0] other_f_y, 
    input [9:0] other_r_x, input [9:0] other_r_y, 

    // 自己碰撞圓
    output wire [9:0] my_f_x, output wire [9:0] my_f_y,
    output wire [9:0] my_r_x, output wire [9:0] my_r_y,
    
    output wire [9:0] pos_x, 
    output wire [9:0] pos_y,
    output reg  [3:0] angle_idx, 
    output reg  [9:0] speed_out,
    output [1:0] flag 
);
    localparam HIT_COOLDOWN_TIME = 6'd30;
    // 60Hz Game Tick
    reg [20:0] tick_cnt;
    wire game_tick;
    
    always @(posedge clk) begin
        if (rst) tick_cnt <= 0;
        else if (tick_cnt >= (CLK_FREQ / 60)) tick_cnt <= 0;
        else tick_cnt <= tick_cnt + 1;
    end
    assign game_tick = (tick_cnt == 0); 

    // --- 1. 角度控制 ---
    reg [5:0] internal_angle; 
    reg [3:0] turn_delay; 

    always @(posedge clk) begin
        if (rst) begin
            internal_angle <= 6'd0;
            angle_idx <= 0; 
            turn_delay <= 0;
            flag <= 2'd0;
        end else if (game_tick && state == 3'd4) begin
            if (h_code == 2'd1) begin // Left
                if (turn_delay == 0) begin
                    internal_angle <= internal_angle - 1;
                    turn_delay <= 2; 
                end else turn_delay <= turn_delay - 1;
            end else if (h_code == 2'd2) begin // Right
                if (turn_delay == 0) begin
                    internal_angle <= internal_angle + 1;
                    turn_delay <= 2;
                end else turn_delay <= turn_delay - 1;
            end else begin
                 turn_delay <= 0;
            end
            angle_idx <= internal_angle[5:2]; 
        end
    end

    //向量與圓心計算
    reg signed [9:0] speed;
    reg signed [9:0] next_speed;
    wire signed [9:0] unit_x, unit_y; // 來自 LUT (Q8 格式, 放大256倍)
    
    direction_lut lut_inst (.angle_idx(angle_idx), .dir_x(unit_x), .dir_y(unit_y));

    // 計算前後圓偏移量 (Offset Vector)
    // 運算: (UnitVector * OffsetDist) / 256
    reg signed [19:0] raw_off_x, raw_off_y;
    wire signed [9:0] final_off_x, final_off_y;
    
    always @(*) begin
        raw_off_x = unit_x * $signed(OFFSET_DIST);
        raw_off_y = unit_y * $signed(OFFSET_DIST);
    end
    assign final_off_x = raw_off_x >>> 8;
    assign final_off_y = raw_off_y >>> 8;

    // 計算並輸出絕對座標 (目前位置 +/- 偏移量)
    assign my_f_x = pos_x + final_off_x;
    assign my_f_y = pos_y + final_off_y;
    assign my_r_x = pos_x - final_off_x;
    assign my_r_y = pos_y - final_off_y;

    //碰撞檢測邏輯
    //撞牆檢測
    wire wall_hit_f = (my_f_x < 10 || my_f_x+10 > MAP_W || my_f_y < 10 || my_f_y+10 > MAP_H);
    wire wall_hit_r = (my_r_x < 10 || my_r_x+10 > MAP_W || my_r_y < 10 || my_r_y+10 > MAP_H);
    wire is_wall_hit = wall_hit_f | wall_hit_r;

    //撞車檢測
    // 距離平方計算函數
    function check_hit_func;
        input [9:0] x1, y1, x2, y2;
        reg signed [10:0] dx, dy;
        reg [21:0] d_sq;
        begin
            dx = $signed({1'b0, x1}) - $signed({1'b0, x2});
            dy = $signed({1'b0, y1}) - $signed({1'b0, y2});
            d_sq = (dx*dx) + (dy*dy);
            check_hit_func = (d_sq < (COLLISION_RSQ<<<2));
        end
    endfunction

    wire hit_ff = check_hit_func(my_f_x, my_f_y, other_f_x, other_f_y);
    wire hit_fr = check_hit_func(my_f_x, my_f_y, other_r_x, other_r_y);
    wire hit_rf = check_hit_func(my_r_x, my_r_y, other_f_x, other_f_y);
    wire hit_rr = check_hit_func(my_r_x, my_r_y, other_r_x, other_r_y);
    
    wire is_car_hit = (hit_ff | hit_fr | hit_rf | hit_rr);

    //座標與速度更新邏輯
    reg signed [19:0] pos_x_accum, next_pos_x_accum;
    reg signed [19:0] pos_y_accum, next_pos_y_accum;
    
    reg [5:0] hit_cd_cnt;
    reg [2:0] speed_delay; 

    assign pos_x = pos_x_accum[19:10]; 
    assign pos_y = pos_y_accum[19:10];
    
    always @(posedge clk) speed_out <= speed;

   // 無碰撞數值計算
    always @(*) begin
        // 預設保持原值
        next_speed = speed;
        next_pos_x_accum = pos_x_accum;
        next_pos_y_accum = pos_y_accum;

        // 計算摩擦力與加減速
        if(speed_delay == 0) begin
            if (v_code == 2'd1 /*UP*/) begin
                if (boost && speed < 15)      next_speed = speed + 1;
                else if (!boost && speed < 8) next_speed = speed + 1;
            end else if (v_code == 2'd2 /*DOWN*/) begin
                if (speed > -4) next_speed = speed - 1;
            end else begin
                if (speed > 0) next_speed = speed - 1;
                else if (speed < 0) next_speed = speed + 1;
            end
        end
        
        // 計算位置
        if (speed != 0) begin
            next_pos_x_accum = pos_x_accum + ((speed * unit_x)>>>1);
            next_pos_y_accum = pos_y_accum + ((speed * unit_y)>>>1);
        end
    end

    //處理狀態更新與碰撞觸發
    always @(posedge clk) begin
        if (rst) begin
            pos_x_accum <= START_X << 10;
            pos_y_accum <= START_Y << 10;
            speed <= 0;
            speed_delay <= 0;
            hit_cd_cnt <= 0;
        end else if (game_tick && state == 3'd4) begin
            if (hit_cd_cnt > 0) begin
                hit_cd_cnt <= hit_cd_cnt - 1;
                pos_x_accum <= next_pos_x_accum;
                pos_y_accum <= next_pos_y_accum;
                speed <= next_speed; 
                speed_delay <= speed_delay + 1;
            end
            else if (is_car_hit) begin
                hit_cd_cnt <= HIT_COOLDOWN_TIME; 
                if(hit_rf)begin
                    if (speed >= 0) speed <= speed+10'd3;
                    else speed <= speed-10'd3;
                end
                else begin
                    if (speed >= 0) speed <= -10'd3;
                    else speed <= 10'd3;
                end
                pos_x_accum <= pos_x_accum; 
                pos_y_accum <= pos_y_accum;
                speed_delay <= 0;
            end
            else if (is_wall_hit) begin
                if (speed >= 0) speed <= -10'd2;
                else           speed <= 10'd2;
                pos_x_accum <= pos_x_accum; // 停在原地 (不更新位置)
                pos_y_accum <= pos_y_accum;
                speed_delay <= 0;
                hit_cd_cnt <= 6'd20; 
            end
            
            //正常行駛
            else begin
                pos_x_accum <= next_pos_x_accum;
                pos_y_accum <= next_pos_y_accum;
                speed <= next_speed;
                speed_delay <= speed_delay + 1;
            end
        end
    end
endmodule
module direction_lut (
    input [3:0] angle_idx, // 0=Up, 順時針增加
    output reg signed [9:0] dir_x, 
    output reg signed [9:0] dir_y  
);
    // 座標系: X向右為正, Y向下為正(螢幕座標)
    // 數值: 256 * 單位向量
    
    always @(*) begin
        case (angle_idx)
            // --- 第 1 象限 (上 -> 右) ---
            4'd0:  begin dir_x =   0; dir_y = -256; end // Up (North)
            4'd1:  begin dir_x = 100; dir_y = -236; end // NNE
            4'd2:  begin dir_x = 181; dir_y = -181; end // NE
            4'd3:  begin dir_x = 236; dir_y = -100; end // ENE
            
            // --- 第 2 象限 (右 -> 下) ---
            4'd4:  begin dir_x = 256; dir_y =    0; end // Right (East)
            4'd5:  begin dir_x = 236; dir_y =  100; end // ESE
            4'd6:  begin dir_x = 181; dir_y =  181; end // SE
            4'd7:  begin dir_x = 100; dir_y =  236; end // SSE

            // --- 第 3 象限 (下 -> 左) ---
            4'd8:  begin dir_x =   0; dir_y =  256; end // Down (South)
            4'd9:  begin dir_x = -100;dir_y =  236; end // SSW
            4'd10: begin dir_x = -181;dir_y =  181; end // SW
            4'd11: begin dir_x = -236;dir_y =  100; end // WSW

            // --- 第 4 象限 (左 -> 上) ---
            4'd12: begin dir_x = -256;dir_y =    0; end // Left (West)
            4'd13: begin dir_x = -236;dir_y = -100; end // WNW
            4'd14: begin dir_x = -181;dir_y = -181; end // NW
            4'd15: begin dir_x = -100;dir_y = -236; end // NNW
            
            default: begin dir_x = 0; dir_y = -256; end
        endcase
    end
endmodule