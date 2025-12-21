module PhysicsEngine #(
    parameter START_X = 0,
    parameter START_Y = 120,
    parameter CLK_FREQ = 100_000_000,
    
    // --- [新增] 碰撞參數 ---
    parameter MAP_W = 10'd320,   // 地圖寬
    parameter MAP_H = 10'd240,   // 地圖高
    parameter OFFSET_DIST = 10'd5, // 圓心距離車中心的偏移量 (車長/4)
    parameter COLLISION_RSQ = 10'd100
)(
    input clk,
    input rst,
    input [2:0] state,
    input [1:0] h_code, 
    input [1:0] v_code, 
    input boost,        
    
    // 對手碰撞圓 (從 Top 傳入)
    input [9:0] other_f_x, input [9:0] other_f_y, 
    input [9:0] other_r_x, input [9:0] other_r_y, 

    // 輸出自己的碰撞圓 (給 Top 傳給對手)
    output wire [9:0] my_f_x, output wire [9:0] my_f_y,
    output wire [9:0] my_r_x, output wire [9:0] my_r_y,
    
    output wire [9:0] pos_x, 
    output wire [9:0] pos_y,
    output reg  [3:0] angle_idx, 
    output reg  [9:0] speed_out
);

    // --- 0. 產生 60Hz 的遊戲節拍 (Game Tick) ---
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
            internal_angle <= 6'd0; // 預設朝上或朝右需看您 LUT 定義，假設 0 是上
            angle_idx <= 0; 
            turn_delay <= 0;
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

    // --- 2. 向量與圓心計算 (整合碰撞前置作業) ---
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
    // pos_x 是 wire (來自 accum 的高 10 位)，直接相加即可
    assign my_f_x = pos_x + final_off_x;
    assign my_f_y = pos_y + final_off_y;
    assign my_r_x = pos_x - final_off_x;
    assign my_r_y = pos_y - final_off_y;

    // --- 3. 碰撞檢測邏輯 (Combinational) ---
    
    // A. 撞牆檢測 (Wall Collision) - 檢查前圓或後圓是否出界
    // 邊界留一點緩衝 (例如 10 pixel)
    wire wall_hit_f = (my_f_x < 0 || my_f_x > MAP_W || my_f_y < 0 || my_f_y > MAP_H);
    wire wall_hit_r = (my_r_x < 0 || my_r_x > MAP_W || my_r_y < 0 || my_r_y > MAP_H);
    wire is_wall_hit = wall_hit_f | wall_hit_r;

    // B. 撞車檢測 (Car Collision) - 雙圓形交叉比對
    // 距離平方計算函數
    function check_hit_func;
        input [9:0] x1, y1, x2, y2;
        reg signed [10:0] dx, dy;
        reg [21:0] d_sq;
        begin
            dx = $signed({1'b0, x1}) - $signed({1'b0, x2});
            dy = $signed({1'b0, y1}) - $signed({1'b0, y2});
            d_sq = (dx*dx) + (dy*dy);
            check_hit_func = (d_sq < COLLISION_RSQ);
        end
    endfunction

    wire hit_ff = check_hit_func(my_f_x, my_f_y, other_f_x, other_f_y);
    wire hit_fr = check_hit_func(my_f_x, my_f_y, other_r_x, other_r_y);
    wire hit_rf = check_hit_func(my_r_x, my_r_y, other_f_x, other_f_y);
    wire hit_rr = check_hit_func(my_r_x, my_r_y, other_r_x, other_r_y);
    
    wire is_car_hit = (hit_ff | hit_fr | hit_rf | hit_rr);

    // --- 4. 座標與速度更新邏輯 ---
    reg signed [19:0] pos_x_accum, next_pos_x_accum;
    reg signed [19:0] pos_y_accum, next_pos_y_accum;
    reg [2:0] speed_delay; 

    assign pos_x = pos_x_accum[19:10]; 
    assign pos_y = pos_y_accum[19:10];
    
    always @(posedge clk) speed_out <= speed;

    always @(*) begin
        // 預設保持原值
        next_speed = speed;
        next_pos_x_accum = pos_x_accum;
        next_pos_y_accum = pos_y_accum;
        
        // 1. 優先處理 [撞車] (反彈)
        if (is_car_hit) begin
            // 速度反轉 (Knockback)
            if (speed > 0) next_speed = -10'd8; 
            else           next_speed = 10'd8;
            
            // 位置強制推回 (Anti-sticking)
            // 往當前向量的反方向推，推開距離約為速度的 4 倍
            next_pos_x_accum = pos_x_accum - unit_x; 
            next_pos_y_accum = pos_y_accum - unit_y;
        end 
        // 2. 處理 [撞牆] (停止/微反彈)
        else if (is_wall_hit) begin
            // 碰到牆壁，速度歸零 (或者您可以設一個小的反彈值如 -2)
            next_speed = 10'd0;
            // 位置保持不變 (卡在牆邊，不允許繼續前進)
            next_pos_x_accum = pos_x_accum;
            next_pos_y_accum = pos_y_accum;
            
            // 如果想允許「倒車離開牆壁」，需要判斷按鍵方向
            // 如果按下 Down 且撞牆，允許後退速度 (這部分邏輯較複雜，暫時先設為停止)
            if (v_code == 2'd2) next_speed = -10'd2; 
        end 
        // 3. 正常移動邏輯
        else begin
            // A. 速度計算
            // 注意：如果剛從碰撞恢復，需要立即更新速度，這裡使用 speed_delay 控制加速度
            if(speed_delay == 0) begin
                if (v_code == 2'd1 /*UP*/) begin
                    if (boost && speed < 15)      next_speed = speed + 1;
                    else if (!boost && speed < 8) next_speed = speed + 1;
                end else if (v_code == 2'd2 /*DOWN*/) begin
                    if (speed > -4) next_speed = speed - 1;
                end else begin
                    // 摩擦力
                    if (speed > 0) next_speed = speed - 1;
                    else if (speed < 0) next_speed = speed + 1;
                end
            end

            // B. 位置更新
            if (speed != 0) begin
                // [修正] 對齊問題:
                // unit 是 Q8, pos_accum 是 Q10, 相差 2 bits
                // (speed * unit) 是 Q8, 左移 2 位變成 Q10
                next_pos_x_accum = pos_x_accum + speed * unit_x;
                next_pos_y_accum = pos_y_accum + speed * unit_y;
            end
        end
    end

    // --- Sequential Logic ---
    always @(posedge clk) begin
        if (rst) begin
            pos_x_accum <= START_X << 10;
            pos_y_accum <= START_Y << 10;
            speed <= 0;
            speed_delay <= 0;
        end else if (game_tick && state == 3'd4) begin
            
            pos_x_accum <= next_pos_x_accum;
            pos_y_accum <= next_pos_y_accum;
            speed <= next_speed;
            
            // 如果發生碰撞，重置加速計時器，讓反彈瞬間生效
            if (is_car_hit || is_wall_hit)
                speed_delay <= 0; 
            else
                speed_delay <= speed_delay + 1; 
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