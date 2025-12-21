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
    // 7 Segment 輸出
    output wire [6:0] display,
    output wire [3:0] digit,
    // LED 輸出
    output wire [2:0] led,
    //debug switch
    input sw
);
    // --- 參數設定 ---
    parameter MAP_BASE_ADDR   = 17'd90001; // 地圖起始位址
    parameter MAP_WIDTH       = 10'd320;
    parameter MAP_HEIGHT      = 10'd240;
    parameter TRANSPARENT     = 12'h000;   // 車子透明色 (綠)
    parameter OUT_BOUND_COLOR = 12'h6B4;   // 地圖界外色 (綠)
    parameter SEPARATOR_COLOR = 12'hFFF;   // 分割線 (白)

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
    StateEncoder state_encoder (
        .clk(clk), .rst(rst),
        .start_btn(start_btn),     // Game Starting Button
        .setting_btn(setting_btn), // Game Setting Button
        .pause_btn(pause_btn),     // Game Pause Button (for state COUNTDOWN & RACING)
        .is_game_end(0), // Whether the racing game has ended. (遊戲結束)
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
    wire       p1_boost;
    wire       p1_honk;
    wire [1:0] p2_h_code;
    wire [1:0] p2_v_code;
    wire       p2_boost;
    wire       p2_honk;
    wire [1:0] p1_flag_order;
    wire [1:0] p2_flag_order;
    OperationEncoder op_encoder (
        .clk(clk), .rst(rst),

        .PS2_DATA(PS2_DATA),
        .PS2_CLK(PS2_CLK),

        .state(state), // Current state from the FSM (StateEncoder)
    
        .p1_h_code(p1_h_code), .p1_v_code(p1_v_code),
        .p1_boost(p1_boost),
        .p1_honk(p1_honk),

        .p2_h_code(p2_h_code), .p2_v_code(p2_v_code),
        .p2_boost(p2_boost),
        .p2_honk(p2_honk)
    );

    //遊戲物理引擎 (處理移動、碰撞)
    // p1 (左邊)
    wire [9:0] p1_speed;
    wire [9:0] P1_f_x; wire [9:0] P1_f_y; wire [9:0] P1_r_x; wire [9:0] P1_r_y;
    wire [9:0] P2_f_x;wire [9:0] P2_f_y; wire [9:0] P2_r_x;wire [9:0] P2_r_y;
    PhysicsEngine #(
        .START_X(8'd15), .START_Y(8'd125)
    ) p1_engine (
        .clk(clk), .rst(rst),

        .state(state), // From StateEncoder

        .h_code(p1_h_code), .v_code(p1_v_code), // From OperationEncoder Module

        .pos_x(p1_world_x), .pos_y(p1_world_y),
        .angle_idx(p1_degree),
        .other_f_x(P2_f_x),.other_f_y(P2_f_y),.other_r_x(P2_r_x),.other_r_y(P2_r_y),
        .my_f_x(P1_f_x),.my_f_y(P1_f_y),.my_r_x(P1_r_x),.my_r_y(P1_r_y),
        .speed_out(p1_speed)
    );

    wire [9:0] p2_speed;
    PhysicsEngine #(
        .START_X(8'd25), .START_Y(8'd125)
    ) p2_engine (
        .clk(clk), .rst(rst),

        .state(state), // From StateEncoder

        .h_code(p2_h_code), .v_code(p2_v_code), // From OperationEncoder Module
        .pos_x(p2_world_x), .pos_y(p2_world_y),
        .angle_idx(p2_degree),
        .other_f_x(P1_f_x),.other_f_y(P1_f_y),.other_r_x(P1_r_x),.other_r_y(P1_r_y),
        .my_f_x(P2_f_x),.my_f_y(P2_f_y),.my_r_x(P2_r_x),.my_r_y(P2_r_y),
        .speed_out(p2_speed)
    );

    // 七段顯示器（Debug 用）
    SevenSegment seven_seg (
        .display(display),
        .digit(digit),
        .nums({p1_speed[7:0], p2_speed[7:0]}),
        .clk(clk),
        .rst(rst)
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
    reg [16:0] addr_map;
    wire [11:0] data_map;
    
    // 地圖的世界座標
    wire [9:0] map_global_x = (screen_rel_x >> 3) + (my_world_x - 20); // 假設中心在160，地圖縮放2倍
    wire [9:0] map_global_y = (v_cnt >> 3) + (my_world_y - 22);        // 假設中心在240(120*2)
    wire is_out_of_map = (map_global_x >= MAP_WIDTH) || (map_global_y >= MAP_HEIGHT);

    always @(*) begin
        if (is_out_of_map) addr_map = 0;
        // -----------------------------------------------------------------
        // [修正] 強制使用移位運算取代乘法 (320 = 256 + 64)
        // 原本: addr_map = (map_global_y * 320) + map_global_x;
        // -----------------------------------------------------------------
        else addr_map = (map_global_y << 8) + (map_global_y << 6) + map_global_x;
    end
    
    // --- B. 小地圖位址計算 (Port B) ---
    reg [16:0] addr_minimap;
    wire [11:0] data_map_mini;
    // 1. 還原相對地圖座標 (螢幕座標 -> 地圖座標)
    // 這裡用 h_cnt - 240 (小地圖起始X) 和 v_cnt - 360 (小地圖起始Y)
    // 左移 1位 (<<1) 代表乘以 2，實現 1/2 縮放採樣
    wire [9:0] mm_read_x = (h_cnt - 240) << 1;
    wire [9:0] mm_read_y = (v_cnt - 360) << 1;
    
    // 2. 計算線性位址 (Row-Major)
    // 只有在掃描線進入小地圖區域時才計算，節省功耗 (雖非必要但好習慣)
    always @(*) begin
        if (is_minimap_area)
            // -----------------------------------------------------------------
            // [修正] 強制使用移位運算取代乘法 (320 = 256 + 64)
            // 原本: addr_minimap = (mm_read_y * 320) + mm_read_x;
            // -----------------------------------------------------------------
            addr_minimap = (mm_read_y << 8) + (mm_read_y << 6) + mm_read_x;
        else
            addr_minimap = 17'd0;
    end

    wire [3:0] map_color;
    wire [3:0] map_color_mini;
    blk_mem_gen_0 map_ram (
        .clka(clk_25MHz), .addra(addr_map), .douta(map_color),
        .clkb(clk_25MHz), .addrb(addr_minimap), .doutb(map_color_mini)
        );
    color_decoder map_color_decoder(.color_index(map_color),  // 從 BRAM 讀出來的 0~5
    .rgb_data(data_map),.is_b(0));
    color_decoder map_color_mini_decoder(.color_index(map_color_mini),  // 從 BRAM 讀出來的 0~5
    .rgb_data(data_map_mini),.is_b(0));

    // B. 車子位址計算 (Car Address) - True Dual Port
    reg [16:0] addr_car_self;
    wire [11:0] data_car_self;
    reg [16:0] addr_car_enemy;
    wire [11:0] data_car_enemy;

    // 1. [自己的車] (固定在畫面中心)
    // 螢幕中心 (160, 240), 車寬 75 -> 範圍 X[123, 197], Y[203, 277]
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
    wire signed [12:0] diff_x = (enemy_world_x - my_world_x) <<< 3;
    wire signed [12:0] diff_y = (enemy_world_y - my_world_y) <<< 3;
    wire signed [12:0] enemy_center_x = 160 + diff_x;
    wire signed [12:0] enemy_center_y = 180 + diff_y;
    
    // 敵車判定框 (Box Check)
    wire signed [12:0] screen_x_signed = $signed({1'b0, screen_rel_x}); // 轉成 13-bit signed
    wire signed [12:0] screen_y_signed = $signed({1'b0, v_cnt});        // 轉成 13-bit signed
    wire signed [12:0] car_left   = enemy_center_x - 13'd37;
    wire signed [12:0] car_right  = enemy_center_x + 13'd37;
    wire signed [12:0] car_top    = enemy_center_y - 13'd37;
    wire signed [12:0] car_bottom = enemy_center_y + 13'd37;
    // 敵車判定框 (使用 Signed 比較)
   wire is_enemy_box = (screen_x_signed >= car_left) && (screen_x_signed <= car_right) &&
                         (screen_y_signed >= car_top)  && (screen_y_signed <= car_bottom);
    // 計算 Enemy 旋轉位址
   wire signed [12:0] tex_x_calc = screen_x_signed - car_left;
    wire signed [12:0] tex_y_calc = screen_y_signed - car_top;

    // 5. 連接到 Address Generator
    wire [16:0] calc_addr_enemy;
    
    car_addr addr_logic_enemy (
        .degree(enemy_degree),
        // 只取低位元傳入，因為 car_addr 只需要 0~74 的輸入
        .pixel_x(tex_x_calc[9:0]), 
        .pixel_y(tex_y_calc[9:0]),
        .rom_addr(calc_addr_enemy)
    );

    // 分配位址給 BRAM
    always @(*) begin
        addr_car_self  = is_self_box  ? calc_addr_self  : 17'd0;
        addr_car_enemy = is_enemy_box ? calc_addr_enemy : 17'd0;
    end

    // 雙埠記憶體實例化
    wire [3:0]car_self_color;
    wire [3:0]car_enemy_color;
    blk_mem_gen_1 car_ram (
        .clka(clk_25MHz), .addra(addr_car_self), .douta(car_self_color),   // Port A: Self
        .clkb(clk_25MHz), .addrb(addr_car_enemy), .doutb(car_enemy_color)  // Port B: Enemy
    );
    color_decoder car_a_decode(.color_index(car_self_color),.rgb_data(data_car_self),.is_b(!is_left_screen));
    color_decoder car_b_decode(.color_index(car_enemy_color),.rgb_data(data_car_enemy),.is_b(is_left_screen));
    
    // --- 小地圖邏輯 (Mini-map Logic) ---

    // 2. 將螢幕座標還原回「地圖座標」(反向縮放)
    // 這樣就可以直接跟 p1_world_x (0~320) 做比較
    wire [9:0] mm_scan_x = (h_cnt - 240) << 1; 
    wire [9:0] mm_scan_y = (v_cnt - 360) << 1;

    // 3. 判斷是否為車子的點 (點的大小設為 8x8 的世界座標範圍，約等於小地圖上的 4x4 像素)
    // 這裡使用簡單的矩形判斷，abs 邏輯
    wire is_p1_dot = (mm_scan_x >= p1_world_x - 4 && mm_scan_x <= p1_world_x + 4) &&
                     (mm_scan_y >= p1_world_y - 4 && mm_scan_y <= p1_world_y + 4);

    wire is_p2_dot = (mm_scan_x >= p2_world_x - 4 && mm_scan_x <= p2_world_x + 4) &&
                     (mm_scan_y >= p2_world_y - 4 && mm_scan_y <= p2_world_y + 4);
    
    // --- COUNTDOWN 倒數 --- 
    wire is_countdown_pixel;
    NumberSprite num_display (
        .h_cnt(h_cnt), .v_cnt(v_cnt),
        .num(countdown_val),
        .is_pixel(is_countdown_pixel)
    );
    
    // --- Debug Layer: 繪製碰撞框 ---
    // 假設有一個開關 sw[0] 用來切換是否顯示 Debug 框
    // 如果你的板子沒有 sw 輸入，可以暫時寫死為 1'b1
    
    // 取得當前掃描點對應的「世界座標」 (這在你的地圖邏輯裡應該已經算好了)
    // 變數名稱可能叫 map_global_x / map_global_y
    
    // 為了節省資源，我們只計算圓框 (Hollow Circle)
    // 半徑平方判定: 18^2 = 324。我們畫 16^2 ~ 19^2 之間的像素，形成一個圈
    localparam DBG_R_MIN_SQ = 10'd4;
    localparam DBG_R_MAX_SQ = 10'd9;

    // 定義一個函數來檢查「當前像素是否在圓環上」
    function is_on_circle;
        input [9:0] px, py; // 當前像素世界座標
        input [9:0] cx, cy; // 圓心座標
        reg signed [10:0] dx, dy;
        reg [21:0] d_sq;
        begin
            dx = $signed({1'b0, px}) - $signed({1'b0, cx});
            dy = $signed({1'b0, py}) - $signed({1'b0, cy});
            d_sq = (dx*dx) + (dy*dy);
            // 如果距離在 內徑 與 外徑 之間，就是圓環邊緣
            is_on_circle = (d_sq >= DBG_R_MIN_SQ && d_sq <= DBG_R_MAX_SQ);
        end
    endfunction

    wire p1_f_draw = is_on_circle(map_global_x, map_global_y, P1_f_x, P1_f_y);
    wire p1_r_draw = is_on_circle(map_global_x, map_global_y, P1_r_x, P1_r_y);
    wire p2_f_draw = is_on_circle(map_global_x, map_global_y, P2_f_x, P2_f_y);
    wire p2_r_draw = is_on_circle(map_global_x, map_global_y, P2_r_x, P2_r_y);
     // 判定當前像素是否是 Debug 線條
    wire is_debug_pixel = (p1_f_draw || p1_r_draw || p2_f_draw || p2_r_draw);

   
    wire [13:0] flag_addr;
    wire        flag_active;
    wire [3:0]  flag_code;
    wire [11:0] flag_data;   // 從 BRAM 讀出來的 RGB
    flag_addr flag_gen (
        .h_cnt     (h_cnt),
        .v_cnt     (v_cnt),
        .p1_order  (p1_flag_order), // 接你的暫存器
        .p2_order  (p2_flag_order), // 接你的暫存器
        .mem_addr  (flag_addr),
        .is_active (flag_active)
    );

    blk_mem_gen_2 flag_ram (
        .clka  (clk_25MHz),           // 使用跟 VGA 同樣的時脈
        .addra (flag_addr),   // 接上算出來的位址
        .douta (flag_code)    // 讀出來的資料
    );
    color_decoder flag_decoder(
        .color_index(flag_code),
        .rgb_data(flag_data),
        .is_b(0)
    );

    //最終顏色輸出
    reg [11:0] final_color;
    
    always @(*) begin
        if (!valid) begin
            final_color = 12'h000; // Blanking

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
            final_color = 12'hFFF;

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
            else 
                final_color = data_map;
        end
    end

    assign vgaRed   = final_color[11:8];
    assign vgaGreen = final_color[7:4];
    assign vgaBlue  = final_color[3:0];

endmodule

module SevenSegment(
    output reg [6:0] display,
    output reg [3:0] digit,
    input wire [15:0] nums,
    input wire rst,
    input wire clk
    );
    
    reg [15:0] clk_divider;
    reg [3:0] display_num;
    
    always @ (posedge clk, posedge rst) begin
        if (rst) begin
            clk_divider <= 15'b0;
        end else begin
            clk_divider <= clk_divider + 15'b1;
        end
    end
    
    always @ (posedge clk_divider[15], posedge rst) begin
        if (rst) begin
            display_num <= 4'b0000;
            digit <= 4'b1111;
        end else begin
            case (digit)
                4'b1110 : begin
                        display_num <= nums[7:4];
                        digit <= 4'b1101;
                    end
                4'b1101 : begin
                        display_num <= nums[11:8];
                        digit <= 4'b1011;
                    end
                4'b1011 : begin
                        display_num <= nums[15:12];
                        digit <= 4'b0111;
                    end
                4'b0111 : begin
                        display_num <= nums[3:0];
                        digit <= 4'b1110;
                    end
                default : begin
                        display_num <= nums[3:0];
                        digit <= 4'b1110;
                    end             
            endcase
        end
    end
    
    always @ (*) begin
        case (display_num)
            0  : display = 7'b1000000; // 0000 (0)
            1  : display = 7'b1111001; // 0001 (1)                                       
            2  : display = 7'b0100100; // 0010 (2)                                        
            3  : display = 7'b0110000; // 0011 (3)                                 
            4  : display = 7'b0011001; // 0100 (4)                                   
            5  : display = 7'b0010010; // 0101 (5)                                   
            6  : display = 7'b0000010; // 0110 (6)
            7  : display = 7'b1111000; // 0111 (7)
            8  : display = 7'b0000000; // 1000 (8)
            9  : display = 7'b0010000; // 1001 (9)
            10 : display = 7'b0001000; // 1010 (A)
            11 : display = 7'b0000011; // 1011 (b)
            12 : display = 7'b1000110; // 1100 (C)
            13 : display = 7'b0100001; // 1101 (d)
            14 : display = 7'b0000110; // 1110 (E)
            15 : display = 7'b0001110; // 1111 (F)
            default : display = 7'b1111111;
        endcase
    end
    
endmodule