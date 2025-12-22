module Top (
    input wire clk,
    input wire rst,
    inout wire PS2_CLK,
    inout wire PS2_DATA,
    // Button
    input wire start_btn,
    input wire setting_btn,
    input wire pause_btn,
    // VGA 輸出
    output wire [3:0] vgaRed,
    output wire [3:0] vgaGreen,
    output wire [3:0] vgaBlue,
    output wire hsync,
    output wire vsync,
    // LED 輸出
    output wire [2:0] led,
    // Debug switch Input
    input wire sw,
    // PMOD Audio 模組
    output wire audio_mclk,
    output wire audio_lrck,
    output wire audio_sck,
    output wire audio_sdin
);
    // --- 參數設定 ---
   parameter MAP_BASE_ADDR   = 17'd90001; 
    parameter MAP_WIDTH       = 10'd640; 
    parameter MAP_HEIGHT      = 10'd480;
    parameter TRANSPARENT     = 12'h000;   
    parameter OUT_BOUND_COLOR = 12'h6B4;   
    parameter SEPARATOR_COLOR = 12'hFFF;

    // --- 內部連接線 ---
    wire clk_25MHz, valid;
    wire [9:0] h_cnt, v_cnt;

    // 在地圖上的絕對座標
    wire [9:0] p1_world_x, p1_world_y;
    wire [9:0] p2_world_x, p2_world_y;
    wire [3:0] p1_degree,  p2_degree;

    // --- 模組實例化 ---
    wire [2:0] state;
    wire [1:0] countdown_val;
    wire       p1_finish,  p2_finish; // 移到這邊，State Encoder 可能需要用。參考 PhysicsEngine。
    StateEncoder state_encoder (
        .clk(clk), .rst(rst),
        .start_btn(start_btn),     // Game Starting Button
        .setting_btn(setting_btn), // Game Setting Button
        .pause_btn(pause_btn),     // Game Pause Button (for state COUNTDOWN & RACING)
        .is_game_end(p1_finish & p2_finish), // 兩個人都完成再結束遊戲。
        .state(state),
        .countdown_val(countdown_val)
    );
    assign led = state;
    /* [States] */
    localparam IDLE      = 3'd0;
    localparam SETTING   = 3'd1;
    // localparam SYNCING = 3'd2;
    localparam COUNTDOWN = 3'd3;
    localparam RACING    = 3'd4;
    localparam PAUSE     = 3'd5;
    localparam FINISH    = 3'd6;
    
    // 1. 時脈除頻
    clock_divider #(.n(2)) clk25(.clk(clk), .clk_div(clk_25MHz));
    // 2. VGA 控制器
    vga_controller vga_inst(
        .pclk(clk_25MHz), .reset(rst),
        .hsync(hsync), .vsync(vsync), .valid(valid),
        .h_cnt(h_cnt), .v_cnt(v_cnt)
    );

    // 3. Operation Encoder Module
    // 從鍵盤接收訊息
    wire [1:0] p1_h_code;
    wire [1:0] p1_v_code;
    wire       p1_honk;
    wire [1:0] p2_h_code;
    wire [1:0] p2_v_code;
    wire       p2_honk;
    wire [1:0] p1_flag_order;
    wire [1:0] p2_flag_order;
    reg [1:0] p1_color;
    reg [1:0] p2_color;
    OperationEncoder op_encoder (
        .clk(clk), .rst(rst),

        .PS2_DATA(PS2_DATA),
        .PS2_CLK(PS2_CLK),

        .state(state), // Current state from the FSM (StateEncoder)
    
        .p1_h_code(p1_h_code), .p1_v_code(p1_v_code),
        .p1_honk(p1_honk),

        .p2_h_code(p2_h_code), .p2_v_code(p2_v_code),
        .p2_honk(p2_honk)
    );

    //遊戲物理引擎 (處理移動、碰撞)
    // p1 (左邊)
    wire [9:0] p1_speed;
    wire [9:0] P1_f_x; wire [9:0] P1_f_y; wire [9:0] P1_r_x; wire [9:0] P1_r_y;
    wire [9:0] P2_f_x;wire [9:0] P2_f_y; wire [9:0] P2_r_x;wire [9:0] P2_r_y;
    PhysicsEngine #(
        .START_X(8'd55), .START_Y(8'd240)
    ) p1_engine (
        .clk(clk), .rst(rst),

        .state(state), // From StateEncoder

        .h_code(p1_h_code), .v_code(p1_v_code), // From OperationEncoder Module

        .pos_x(p1_world_x), .pos_y(p1_world_y),
        .angle_idx(p1_degree),
        .other_f_x(P2_f_x),.other_f_y(P2_f_y),.other_r_x(P2_r_x),.other_r_y(P2_r_y),
        .my_f_x(P1_f_x),.my_f_y(P1_f_y),.my_r_x(P1_r_x),.my_r_y(P1_r_y),
        .speed_out(p1_speed),.flag(p1_flag_order),.finish(p1_finish),.color(p1_color)
    );

    wire [9:0] p2_speed;
    PhysicsEngine #(
        .START_X(8'd85), .START_Y(8'd240)
    ) p2_engine (
        .clk(clk), .rst(rst),

        .state(state), // From StateEncoder

        .h_code(p2_h_code), .v_code(p2_v_code), // From OperationEncoder Module
        .pos_x(p2_world_x), .pos_y(p2_world_y),
        .angle_idx(p2_degree),
        .other_f_x(P1_f_x),.other_f_y(P1_f_y),.other_r_x(P1_r_x),.other_r_y(P1_r_y),
        .my_f_x(P2_f_x),.my_f_y(P2_f_y),.my_r_x(P2_r_x),.my_r_y(P2_r_y),
        .speed_out(p2_speed),.flag(p2_flag_order),.finish(p2_finish),.color(p2_color)
    );

    // --- 渲染變數 (Rendering Logic) ---
    
    // 狀態判斷
    wire is_left_screen = (h_cnt < 320);
    wire is_separator   = (h_cnt == 319 || h_cnt == 320);
    wire is_hud_separator   = (v_cnt == 359 || v_cnt == 360);
    wire is_hud_area = (v_cnt >= 360); // 下方 120 pixel 為介面區
    wire is_minimap_area = (h_cnt >= 240 && h_cnt < 400) && (v_cnt >= 360);

    
    // 動態變數 (根據目前掃描左右邊切換)
    reg [9:0] my_world_x, my_world_y;       // 當前畫面主角
    reg [9:0] enemy_world_x, enemy_world_y; // 當前畫面敵人
    reg [3:0] my_degree, enemy_degree;
    reg [9:0] screen_rel_x;                 // 相對螢幕 X (0~319)

    // 切換視角邏輯 (Multiplexer)
    always @(*) begin
        if (is_left_screen) begin
            // [P1 View]
            screen_rel_x  = h_cnt;
            my_world_x    = p1_world_x;
            my_world_y    = p1_world_y;
            my_degree     = p1_degree;
            enemy_world_x = p2_world_x;
            enemy_world_y = p2_world_y;
            enemy_degree  = p2_degree;
        end else begin
            // [P2 View]
            screen_rel_x  = h_cnt - 320;
            my_world_x    = p2_world_x;
            my_world_y    = p2_world_y;
            my_degree     = p2_degree;
            enemy_world_x = p1_world_x;
            enemy_world_y = p1_world_y;
            enemy_degree  = p1_degree;
        end
    end

    // --- 記憶體位址計算 ---

    // A. 地圖位址計算 (Map Address)
    reg [18:0] addr_map; 
    wire [11:0] data_map;
    
    // 地圖的世界座標
    wire [9:0] map_global_x = (screen_rel_x >> 2) + (my_world_x - 40); 
    wire [9:0] map_global_y = (v_cnt >> 2) + (my_world_y - 45);
    wire is_out_of_map = (map_global_x >= MAP_WIDTH) || (map_global_y >= MAP_HEIGHT);

   always @(*) begin
        if (is_out_of_map) addr_map = 0;
        else addr_map = (map_global_y << 9) + (map_global_y << 7) + map_global_x;
    end
    
    // --- B. 小地圖位址計算 (Port B) ---
    reg [18:0] addr_minimap;
    wire [11:0] data_map_mini;
    
    wire [9:0] mm_read_x = (h_cnt - 240) << 2;
    wire [9:0] mm_read_y = (v_cnt - 360) << 2;
    
    // 2. 計算線性位址 (Row-Major)
    // 只有在掃描線進入小地圖區域時才計算，節省功耗 (雖非必要但好習慣)
    always @(*) begin
        if (is_minimap_area)
            addr_minimap = (mm_read_y << 9) + (mm_read_y << 7) + mm_read_x;
        else
            addr_minimap = 17'd0;
    end

    wire [1:0] map_color;
    wire [1:0] map_color_mini;
    blk_mem_gen_0 map_ram (
        .clka(clk_25MHz), .addra(addr_map), .douta(map_color),
        .clkb(clk_25MHz), .addrb(addr_minimap), .doutb(map_color_mini)
        );
    big_map_color_decoder map_color_decoder(.color_index(map_color),  // 從 BRAM 讀出來的 0~5
    .rgb_data(data_map));
    big_map_color_decoder map_color_mini_decoder(.color_index(map_color_mini),  // 從 BRAM 讀出來的 0~5
    .rgb_data(data_map_mini));

    // B. 車子位址計算 (Car Address) - True Dual Port
    reg [16:0] addr_car_self;
    wire [11:0] data_car_self;
    reg [16:0] addr_car_enemy;
    wire [11:0] data_car_enemy;

    //自己的車 (固定在畫面中心)
    wire is_self_box = (screen_rel_x >= 123 && screen_rel_x <= 197) && 
                       (v_cnt >= 143 && v_cnt <= 217);
    
    // 計算 Self 旋轉位址
    wire [16:0] calc_addr_self;
    car_addr addr_logic_self (
        .degree(my_degree),
        .pixel_x(screen_rel_x - 10'd123),
        .pixel_y(v_cnt - 10'd143),
        .rom_addr(calc_addr_self)
    );

    // 2. [敵人的車] (相對座標)
    // 距離 = (Enemy - Me) * 2 (地圖放大倍率)
    wire signed [12:0] diff_x = (enemy_world_x - my_world_x) <<< 2;
    wire signed [12:0] diff_y = (enemy_world_y - my_world_y) <<< 2;
    wire signed [12:0] enemy_center_x = 160 + diff_x;
    wire signed [12:0] enemy_center_y = 180 + diff_y;
    
    // 敵車判定框
    wire signed [12:0] screen_x_signed = $signed({1'b0, screen_rel_x}); // 轉成 13-bit signed
    wire signed [12:0] screen_y_signed = $signed({1'b0, v_cnt});        // 轉成 13-bit signed
    wire signed [12:0] car_left   = enemy_center_x - 13'd37;
    wire signed [12:0] car_right  = enemy_center_x + 13'd37;
    wire signed [12:0] car_top    = enemy_center_y - 13'd37;
    wire signed [12:0] car_bottom = enemy_center_y + 13'd37;
   
    wire is_enemy_box = (screen_x_signed >= car_left) && (screen_x_signed <= car_right) &&
                         (screen_y_signed >= car_top)  && (screen_y_signed <= car_bottom);
    // 計算 Enemy 旋轉位址
    wire signed [12:0] tex_x_calc = screen_x_signed - car_left;
    wire signed [12:0] tex_y_calc = screen_y_signed - car_top;

    wire [16:0] calc_addr_enemy;
    
    car_addr addr_logic_enemy (
        .degree(enemy_degree),
        .pixel_x(tex_x_calc[9:0]), 
        .pixel_y(tex_y_calc[9:0]),
        .rom_addr(calc_addr_enemy)
    );

    always @(*) begin
        addr_car_self  = is_self_box  ? calc_addr_self  : 17'd0;
        addr_car_enemy = is_enemy_box ? calc_addr_enemy : 17'd0;
    end
    wire [3:0] car_self_color;
    wire [3:0] car_enemy_color;
    blk_mem_gen_1 car_ram (
        .clka(clk_25MHz), .addra(addr_car_self), .douta(car_self_color),   // Port A: Self
        .clkb(clk_25MHz), .addrb(addr_car_enemy), .doutb(car_enemy_color)  // Port B: Enemy
    );
    color_decoder car_a_decode(.color_index(car_self_color),.rgb_data(data_car_self),.is_b(!is_left_screen));
    color_decoder car_b_decode(.color_index(car_enemy_color),.rgb_data(data_car_enemy),.is_b(is_left_screen));
    
    //小地圖邏輯
    //將螢幕座標反向縮放
    wire [9:0] mm_scan_x = (h_cnt - 240) << 2; 
    wire [9:0] mm_scan_y = (v_cnt - 360) << 2;

    //判斷是否為車子的點 (點的大小設為 8x8 的世界座標範圍，約等於小地圖上的 4x4 像素)
    wire is_p1_dot = (mm_scan_x >= p1_world_x - 6 && mm_scan_x <= p1_world_x + 6) &&
                     (mm_scan_y >= p1_world_y - 6 && mm_scan_y <= p1_world_y + 6);

    wire is_p2_dot = (mm_scan_x >= p2_world_x - 6 && mm_scan_x <= p2_world_x + 6) &&
                     (mm_scan_y >= p2_world_y - 6 && mm_scan_y <= p2_world_y + 6);
    
    // --- COUNTDOWN 倒數 --- 
    wire is_countdown_pixel;
    NumberSprite num_display (
        .h_cnt(h_cnt), .v_cnt(v_cnt),
        .num(countdown_val),
        .is_pixel(is_countdown_pixel)
    );

    // --- PAUSE and PLAY 暫停與回歸遊玩 ---
    wire is_pause_resume_pixel;
    PauseResumeSprite pause_play_display (
        .clk(clk), .rst(rst),
        .h_cnt(h_cnt), .v_cnt(v_cnt),
        .state(state),
        .is_pixel(is_pause_resume_pixel)
    );

    // --- WINNING 玩家先贏 ---
    wire [1:0] winning_player = {p2_finish, p1_finish};
    wire is_win_pixel;
    WinningSprite win_display (
        .h_cnt(h_cnt), .v_cnt(v_cnt),
        .winning_player(winning_player),
        .is_pixel(is_win_pixel)
    ); 
    
    reg is_debug_pixel;
    localparam DBG_R_MIN_SQ = 10'd25; 
    localparam DBG_R_MAX_SQ = 10'd36;

    function is_on_circle;
        input [9:0] px, py; // 當前像素世界座標
        input [9:0] cx, cy; // 圓心座標
        reg signed [10:0] dx, dy;
        reg [21:0] d_sq;
        begin
            dx = $signed({1'b0, px}) - $signed({1'b0, cx});
            dy = $signed({1'b0, py}) - $signed({1'b0, cy});
            d_sq = (dx*dx) + (dy*dy);
            is_on_circle = (d_sq >= DBG_R_MIN_SQ && d_sq <= DBG_R_MAX_SQ);
        end
    endfunction

    wire p1_f_draw = is_on_circle(map_global_x, map_global_y, P1_f_x, P1_f_y);
    wire p1_r_draw = is_on_circle(map_global_x, map_global_y, P1_r_x, P1_r_y);
    wire p2_f_draw = is_on_circle(map_global_x, map_global_y, P2_f_x, P2_f_y);
    wire p2_r_draw = is_on_circle(map_global_x, map_global_y, P2_r_x, P2_r_y);
    
    always @(*) begin
        is_debug_pixel = (p1_f_draw || p1_r_draw || p2_f_draw || p2_r_draw);
    end

   
    wire [13:0] flag_addr;
    wire        flag_active;
    wire [3:0]  flag_code;
    wire [11:0] flag_data;
    flag_addr flag_gen (
        .h_cnt     (h_cnt),
        .v_cnt     (v_cnt),
        .p1_order  (p1_flag_order), 
        .p2_order  (p2_flag_order), 
        .mem_addr  (flag_addr),
        .is_active (flag_active)
    );

    blk_mem_gen_2 flag_ram (
        .clka  (clk_25MHz),         
        .addra (flag_addr),  
        .douta (flag_code)  
    );
    color_decoder flag_decoder(
        .color_index(flag_code),
        .rgb_data(flag_data),
        .is_b(0)
    );
    wire [16:0] lobby_addr = ((v_cnt - 120) << 8) + ((v_cnt - 120) << 6) + (h_cnt-160);
    wire [3:0] lobby_code;
    wire [11:0] lobby_data;
    blk_mem_gen_3 lobby_ram(
        .clka(clk_25MHz),
        .addra(lobby_addr),
        .douta(lobby_code)
    );
    start_color_decoder lobby_decoder(
        .start_color_index(lobby_code),
        .rgb_data(lobby_data)
    );

    wire [16:0] finish_addr = (v_cnt << 6) + (v_cnt << 4) + (h_cnt>>2);
    wire [3:0] finish_code;
    wire [11:0] finish_data;
    blk_mem_gen_4 finish_ram(
        .clka(clk_25MHz),
        .addra(finish_addr),
        .douta(finish_code)
    );
    final_color_decoder finish_decoder(
        .final_color_index(finish_code),
        .rgb_data(finish_data)
    );

    //自定義白色格子邏輯
    wire is_area_A = (map_global_x >= 40 && map_global_x <= 55) &&
                     (map_global_y >= 210 && map_global_y <= 218);
    wire is_area_B = (map_global_x >= 55 && map_global_x <= 70) &&
                     (map_global_y >= 218 && map_global_y <= 227);
    wire is_area_C = (map_global_x >= 70 && map_global_x <= 85) &&
                     (map_global_y >= 210 && map_global_y <= 218);
    wire is_area_D = (map_global_x >= 85 && map_global_x <= 100) &&
                     (map_global_y >= 218 && map_global_y <= 227);                                  
    wire is_white_grid = is_area_A || is_area_B || is_area_C || is_area_D;

    //最終顏色輸出
    reg [11:0] final_color;
    
    always @(*) begin
        if (!valid) begin
            final_color = 12'h000; // Blanking
        end
        else if(state==IDLE)begin
            if((h_cnt>160 && h_cnt<480) && v_cnt>120 && v_cnt<360)begin
                final_color = lobby_data;
            end
            else begin
                final_color = 12'hBEB;
            end
        end else if(state==FINISH)begin
            final_color= finish_data;
        end else if (is_hud_separator)begin
            final_color = SEPARATOR_COLOR;

        end else if (is_hud_area)begin
            if (is_minimap_area) begin
                if (is_p1_dot) 
                    final_color = 12'hF00; // 紅點 (P1)
                else if (is_p2_dot) 
                    final_color = 12'h00F; // 藍點 (P2)
                else 
                    final_color = data_map_mini;
            end else if(flag_active)begin
                    final_color = flag_data;
            end else begin
                final_color = 12'h444; // HUD 邊框底色
            end

        end else if (is_separator) begin
            final_color = SEPARATOR_COLOR; // 分割線
        end else if (sw && is_debug_pixel) begin
            final_color = 12'hF0F; // 亮紫色
        end else if (state == COUNTDOWN && is_countdown_pixel) begin
            final_color = 12'hFFF; // 白色
        end else if (is_pause_resume_pixel) begin
            final_color = 12'hFFF; // 白色
        
        // Left player finish first!
        end else if ((state == RACING || state == PAUSE) && p1_finish && is_left_screen && !is_hud_area) begin
            final_color = (is_win_pixel) ? 12'hF0F /* 洋紅色 */ : 12'hFAA /* 粉紅色 */;
        // Right player finish first!
        end else if ((state == RACING || state == PAUSE) && p2_finish && !is_left_screen && !is_hud_area) begin
            final_color = (is_win_pixel) ? 12'h0FF /* 青色 */ : 12'hAAF /* 粉藍色 */;

        end else begin
            // 優先顯示自己的車
            if (is_self_box && data_car_self != TRANSPARENT) 
                final_color = data_car_self;
            // 其次顯示敵人的車 (Ghost)
            else if (is_enemy_box && data_car_enemy != TRANSPARENT) 
                final_color = data_car_enemy;
            // 檢查是否超出地圖
            else if (is_out_of_map) 
                final_color = OUT_BOUND_COLOR;
            // 最後顯示地圖背景
            else if (is_white_grid)final_color = 12'hFFF;
            else 
                final_color = data_map;
        end
    end
    //地圖顏色抓取
    always @(posedge clk_25MHz) begin
        if (rst) begin
            p1_color <= 2'd0;
            p2_color <= 2'd0;
        end else begin
            // 抓取 P1 (左畫面中心 X=160, 車子中心 Y=180)
            if (h_cnt == 10'd160 && v_cnt == 10'd180) begin
                p1_color <= map_color; 
            end
            
            // 抓取 P2 (右畫面中心 X=480, 車子中心 Y=180)
            else if (h_cnt == 10'd480 && v_cnt == 10'd180) begin
                p2_color <= map_color;
            end
        end
    end


    assign vgaRed   = final_color[11:8];
    assign vgaGreen = final_color[7:4];
    assign vgaBlue  = final_color[3:0];

    /* [C. PMOD Audio] */
    AudioEncoder audio (
        .clk(clk), .rst(rst),
        .state(state),
        .audio_mclk(audio_mclk),
        .audio_lrck(audio_lrck),
        .audio_sck(audio_sck),
        .audio_sdin(audio_sdin)
    );

endmodule

