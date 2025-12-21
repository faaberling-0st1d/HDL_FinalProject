module PhysicsEngine #(
    parameter START_X = 160,
    parameter START_Y = 120,
    // 假設 clk = 100MHz, 我們想要 60Hz 的更新率
    // 100,000,000 / 60 = 1,666,666
    parameter CLK_FREQ = 100_000_000 
)(
    input clk,
    input rst,
    input [2:0] state,
    input [1:0] h_code, 
    input [1:0] v_code, 
    input boost,        
    
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
    assign game_tick = (tick_cnt == 0); // 每秒觸發 60 次

    // --- 1. 角度控制 ---
    reg [5:0] internal_angle; 
    reg [3:0] turn_delay; 

    always @(posedge clk) begin
        if (rst) begin
           internal_angle <= 6'd0;
            angle_idx <= 0; 
            turn_delay <= 0;
        end else if (game_tick && state == 3'd4) begin
            // 只在 game_tick 時更新
            if (h_code == 2'd1) begin // Left
                if (turn_delay == 0) begin
                    internal_angle <= internal_angle - 1;
                    turn_delay <= 2; // 設定延遲，避免轉太快
                end else turn_delay <= turn_delay - 1;
            end else if (h_code == 2'd2) begin // Right
                if (turn_delay == 0) begin
                    internal_angle <= internal_angle + 1;
                    turn_delay <= 2;
                end else turn_delay <= turn_delay - 1;
            end else begin
                 turn_delay <= 0; // 放開按鍵時重置延遲
            end
            
            angle_idx <= internal_angle[5:2]; 
        end
    end

    // --- 2. 向量計算 ---
    reg signed [9:0] speed;
    reg signed [9:0] next_speed;
    wire signed [9:0] unit_x, unit_y;
    
    direction_lut lut_inst (.angle_idx(angle_idx), .dir_x(unit_x), .dir_y(unit_y));

    // --- 3. 座標系統 ---
    reg signed [19:0] pos_x_accum, next_pos_x_accum;
    reg signed [19:0] pos_y_accum, next_pos_y_accum;

    assign pos_x = pos_x_accum[19:10]; 
    assign pos_y = pos_y_accum[19:10];
    
    // Debug 用
    always @(posedge clk) speed_out <= speed;

    // --- 組合邏輯: 計算下一幀的速度與位置 ---
    always @(*) begin
        // A. 速度計算 (加上 Boost 邏輯)
        next_speed = speed;
        // 定義最大速度
        // 若 boost 按下，最大速設為 15，否則 8
        
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

        // B. 位置計算
        next_pos_x_accum = pos_x_accum;
        next_pos_y_accum = pos_y_accum;
        
        if (speed != 0) begin
            // 修正數學對齊問題:
            // unit_x 是 Q8 (x256), pos_accum 是 Q10 (x1024)
            // 所以 (speed * unit_x) 需要再左移 2 位 (x4) 才能對齊 Q10
            // 使用 >>> 確保有號數移位正確
            next_pos_x_accum = pos_x_accum + ((speed * unit_x));
            next_pos_y_accum = pos_y_accum + ((speed * unit_y));
        end
    end

    // --- Sequential Logic ---
    always @(posedge clk) begin
        if (rst) begin
            pos_x_accum <= START_X << 10;
            pos_y_accum <= START_Y << 10;
            speed <= 0;
        end else if (game_tick && state == 3'd4) begin
            // 關鍵：只在 Game Tick 更新物理狀態
            pos_x_accum <= next_pos_x_accum;
            pos_y_accum <= next_pos_y_accum;
            speed <= next_speed;
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