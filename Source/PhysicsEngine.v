module PhysicsEngine #(
    parameter START_X = 0,
    parameter START_Y = 120,
    parameter CLK_FREQ = 100_000_000,
    
    parameter MAP_W = 10'd320,
    parameter MAP_H = 10'd240,
    parameter OFFSET_DIST = 10'd2, 
    parameter COLLISION_SIZE = 10'd9 
)(
    input clk,
    input rst,
    input [2:0] state,
    input [1:0] h_code, 
    input [1:0] v_code, 
    input boost,       
    
    input [9:0] other_f_x, input [9:0] other_f_y, 
    input [9:0] other_r_x, input [9:0] other_r_y, 

    output reg [9:0] my_f_x, output reg [9:0] my_f_y,
    output reg [9:0] my_r_x, output reg [9:0] my_r_y,
    
    output wire [9:0] pos_x, 
    output wire [9:0] pos_y,
    output reg  [3:0] angle_idx, 
    output reg  [9:0] speed_out,
    output reg [1:0] flag,
    output reg finish
);
    localparam HIT_COOLDOWN_TIME = 6'd30;
    
    // --- 0. Game Tick (120Hz) ---
    localparam TICK_LIMIT = CLK_FREQ / 120;
    reg [20:0] tick_cnt;
    wire game_tick = (tick_cnt == TICK_LIMIT); 
    
    // 定點數座標 (Q10.10)
    reg signed [19:0] pos_x_accum;
    reg signed [19:0] pos_y_accum;
    
    always @(posedge clk) begin
        if (rst) tick_cnt <= 0;
        else if (game_tick) tick_cnt <= 0;
        else tick_cnt <= tick_cnt + 1;
    end

    // --- 1. 角度控制 ---
    reg [5:0] internal_angle; 
    reg [3:0] turn_delay; 

    always @(posedge clk) begin
        if (rst) begin
            internal_angle <= 6'd0;
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

    // --- 2. 向量計算 ---
    reg signed [9:0] speed;
    wire signed [9:0] unit_x, unit_y; 
    
    direction_lut lut_inst (.angle_idx(angle_idx), .dir_x(unit_x), .dir_y(unit_y));

    // 位移向量 (Shift 7)
    wire signed [9:0] final_off_x = unit_x >>> 7;
    wire signed [9:0] final_off_y = unit_y >>> 7;

    always @(posedge clk) begin
        if (rst) begin
            my_f_x <= 0; my_f_y <= 0;
            my_r_x <= 0; my_r_y <= 0;
        end else begin
            my_f_x <= (pos_x_accum[19:10]) + final_off_x;
            my_f_y <= (pos_y_accum[19:10]) + final_off_y;
            my_r_x <= (pos_x_accum[19:10]) - final_off_x;
            my_r_y <= (pos_y_accum[19:10]) - final_off_y;
        end
    end

    // --- 3. 碰撞檢測 ---
    function check_hit_func;
        input [9:0] x1, y1, x2, y2;
        reg signed [10:0] dx, dy;
        reg [21:0] d_sq;
        begin
            dx = $signed({1'b0, x1}) - $signed({1'b0, x2});
            dy = $signed({1'b0, y1}) - $signed({1'b0, y2});
            d_sq = (dx*dx) + (dy*dy);
            check_hit_func = (d_sq < (COLLISION_SIZE<<<2));
        end
    endfunction
    
    reg hit_ff, hit_fr, hit_rf, hit_rr;
    always@(posedge game_tick) begin // 注意：這裡用 game_tick 觸發可能會有一點延遲，但這不是主要問題
        hit_ff = check_hit_func(my_f_x, my_f_y, other_f_x, other_f_y);
        hit_fr = check_hit_func(my_f_x, my_f_y, other_r_x, other_r_y);
        hit_rf = check_hit_func(my_r_x, my_r_y, other_f_x, other_f_y);
        hit_rr = check_hit_func(my_r_x, my_r_y, other_r_x, other_r_y);
    end
    wire is_car_hit = (hit_ff | hit_fr | hit_rf | hit_rr);
    
    // [優化] 拆分四個方向的撞牆判定，以便做「位置鉗制」
    wire hit_left   = (my_f_x < 6 || my_r_x < 6);
    wire hit_right  = (my_f_x > MAP_W - 6 || my_r_x > MAP_W - 6);
    wire hit_top    = (my_f_y < 6 || my_r_y < 6);
    wire hit_bottom = (my_f_y > MAP_H - 6 || my_r_y > MAP_H - 6);
    wire is_wall_hit = hit_left | hit_right | hit_top | hit_bottom;

    // --- 4. 輸出邏輯 (四捨五入) ---
    assign pos_x = pos_x_accum[19:10] + {9'd0, pos_x_accum[9]}; 
    assign pos_y = pos_y_accum[19:10] + {9'd0, pos_y_accum[9]};
    
    always @(posedge clk) speed_out <= speed;

    reg signed [9:0] target_speed;
    reg [5:0] hit_cd_cnt;
    reg [2:0] speed_delay; 

    // Target Speed Calculation
    always @(*) begin
        target_speed = speed;
        if(speed_delay == 0) begin
            if (v_code == 2'd1 /*UP*/) begin
                if (boost && speed < 15)      target_speed = speed + 1;
                else if (!boost && speed < 7) target_speed = speed + 1;
            end else if (v_code == 2'd2 /*DOWN*/) begin
                if (speed > -4) target_speed = speed - 1;
            end else begin 
                if (speed > 0) target_speed = speed - 1;
                else if (speed < 0) target_speed = speed + 1;
            end
        end
    end

    // --- 5. 狀態更新 (Sequential) ---
    always @(posedge clk) begin
        if (rst) begin
            pos_x_accum <= START_X << 10;
            pos_y_accum <= START_Y << 10;
            speed <= 0;
            speed_delay <= 0;
            hit_cd_cnt <= 0;
        end else if (game_tick && state == 3'd4) begin
            
            // A. 發生撞牆 (優先權最高，強制校正位置)
            // [關鍵修正] 使用位置鉗制 (Clamping) 防止穿牆
            if (is_wall_hit) begin
                hit_cd_cnt <= 6'd20; 
                speed_delay <= 0;
                
                // 1. 反彈速度
                if (speed >= 0) speed <= -10'd2;
                else            speed <= 10'd2;

                // 2. 強制拉回牆內 (Clamping)
                // 必須判斷是車頭還是車尾撞牆，這裡做簡單的邊界限制
                // 這裡直接操作 accum，把車子「推」離牆壁 6 個像素
                if (hit_left)        pos_x_accum <= (10'd7 << 10); 
                else if (hit_right)  pos_x_accum <= ((MAP_W - 7) << 10);
                
                if (hit_top)         pos_y_accum <= (10'd7 << 10);
                else if (hit_bottom) pos_y_accum <= ((MAP_H - 7) << 10);
            end
            
            // B. 發生撞車
            else if (is_car_hit) begin
                hit_cd_cnt <= HIT_COOLDOWN_TIME;
                if(hit_rf || hit_rr) speed <= 10'd3;       // 屁股撞: 向前彈
                else                 speed <= (speed >= 0) ? -10'd3 : 10'd3; // 頭撞: 向後彈
                speed_delay <= 0;
            end
            
            // C. 冷卻中
            else if (hit_cd_cnt > 0) begin
                hit_cd_cnt <= hit_cd_cnt - 1;
                if (speed != 0) begin
                    // [修正點] 120Hz 降速：原本 >>> 1 改成 >>> 2
                    pos_x_accum <= pos_x_accum + ((speed * unit_x) >>> 2);
                    pos_y_accum <= pos_y_accum + ((speed * unit_y) >>> 2);
                end
                speed <= target_speed; 
                speed_delay <= speed_delay + 1;
            end
            
            // D. 正常行駛
            else begin
                speed <= target_speed;
                speed_delay <= speed_delay + 1;
                if (speed != 0) begin
                    // [修正點] 120Hz 降速：原本 >>> 1 改成 >>> 2
                    pos_x_accum <= pos_x_accum + ((speed * unit_x) >>> 2);
                    pos_y_accum <= pos_y_accum + ((speed * unit_y) >>> 2);
                end
            end
        end
    end

    // --- 6. Checkpoint 判定 (Sequential Logic) ---
    always @(posedge clk) begin
        if (rst) begin
            flag <= 2'd0;
            finish <= 0;
        end 
        else if (state == 3'd4) begin
            // [修正點] 這裡原本用 = (阻塞賦值)，改為 <= (非阻塞賦值)
            // 另外建議稍微放寬一點判定區間，以免 120Hz 速度快時跳過
            
            if(flag == 2'd0) begin
                // 放寬判定範圍，例如 +/- 5 pixel
                if(my_f_y > 23 && my_f_y < 54 && my_f_x > 175 && my_f_x < 185) begin
                    flag <= 2'd1;
                end
            end
            else if(flag == 2'd1) begin
                if(my_f_y > 195 && my_f_y < 227 && my_f_x < 247 && my_f_x > 242) begin
                    flag <= 2'd2;
                end
            end
            else if(flag == 2'd2) begin
                if(my_f_y > 190 && my_f_y < 220 && my_f_x < 87 && my_f_x > 82) begin
                    flag <= 2'd3;
                end
            end
            else if(flag == 2'd3) begin
                if(my_f_x > 20 && my_f_x < 50 && my_f_y < 112) begin
                    finish <= 1;
                end
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