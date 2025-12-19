module Top (
    input wire clk,
    input wire rst,
    
    // 硬體按鍵輸入 {Up, Down, Left, Right}
    input wire [3:0] p1_btn,
    input wire [3:0] p2_btn,

    // VGA 輸出
    output wire [3:0] vgaRed,
    output wire [3:0] vgaGreen,
    output wire [3:0] vgaBlue,
    output wire hsync,
    output wire vsync
);

    // --- 參數設定 ---
    parameter MAP_BASE_ADDR   = 17'd90001; // 地圖起始位址
    parameter MAP_WIDTH       = 10'd320;
    parameter MAP_HEIGHT      = 10'd240;
    parameter TRANSPARENT     = 12'h0F0;   // 車子透明色 (綠)
    parameter OUT_BOUND_COLOR = 12'h0F0;   // 地圖界外色 (綠)
    parameter SEPARATOR_COLOR = 12'hFFF;   // 分割線 (白)

    // --- 內部連接線 ---
    wire clk_25MHz, valid;
    wire [9:0] h_cnt, v_cnt;

    // 從 Engine 來的資訊
    wire [9:0] p1_world_x, p1_world_y;
    wire [9:0] p2_world_x, p2_world_y;
    wire [3:0] p1_degree,  p2_degree;

    // --- 模組實例化 ---
    
    // 1. 時脈除頻
    clock_divider #(.n(2)) clk25(.clk(clk), .clk_div(clk_25MHz));

    // 2. VGA 控制器
    vga_controller vga_inst(
        .pclk(clk_25MHz), .reset(rst),
        .hsync(hsync), .vsync(vsync), .valid(valid),
        .h_cnt(h_cnt), .v_cnt(v_cnt)
    );

    // 3. 遊戲物理引擎 (處理移動、碰撞)
    PhysicsEngine engine (
        .clk(clk), .rst(rst),
        //待完成
    );

    // --- 渲染變數 (Rendering Logic) ---
    
    // 狀態判斷
    wire is_left_screen = (h_cnt < 320);
    wire is_separator   = (h_cnt == 319 || h_cnt == 320);

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
    wire [9:0] map_global_x = (screen_rel_x >> 1) + (my_world_x - 80); // 假設中心在160，地圖縮放2倍
    wire [9:0] map_global_y = (v_cnt >> 1) + (my_world_y - 60);        // 假設中心在240(120*2)
    wire is_out_of_map = (map_global_x >= MAP_WIDTH) || (map_global_y >= MAP_HEIGHT);

    always @(*) begin
        if (is_out_of_map) addr_map = 0;
        else addr_map = MAP_BASE_ADDR + (map_global_y * 320) + map_global_x;
    end

    blk_mem_gen_0 map_ram (.clka(clk_25MHz), .addra(addr_map), .douta(data_map));


    // B. 車子位址計算 (Car Address) - True Dual Port
    reg [16:0] addr_car_self;
    wire [11:0] data_car_self;
    reg [16:0] addr_car_enemy;
    wire [11:0] data_car_enemy;

    // 1. [自己的車] (固定在畫面中心)
    // 螢幕中心 (160, 240), 車寬 75 -> 範圍 X[123, 197], Y[203, 277]
    wire is_self_box = (screen_rel_x >= 123 && screen_rel_x <= 197) && 
                       (v_cnt >= 203 && v_cnt <= 277);
    
    // 計算 Self 旋轉位址
    wire [16:0] calc_addr_self;
    car_addr addr_logic_self (
        .degree(my_degree),
        .pixel_x(screen_rel_x - 10'd123),
        .pixel_y(v_cnt - 10'd203),
        .rom_addr(calc_addr_self)
    );

    // 2. [敵人的車] (相對座標)
    // 距離 = (Enemy - Me) * 2 (地圖放大倍率)
    wire signed [10:0] diff_x = (enemy_world_x - my_world_x) * 2;
    wire signed [10:0] diff_y = (enemy_world_y - my_world_y) * 2;
    wire signed [10:0] enemy_center_x = 160 + diff_x;
    wire signed [10:0] enemy_center_y = 240 + diff_y;
    
    // 敵車判定框 (Box Check)
    wire is_enemy_box = (screen_rel_x >= (enemy_center_x - 37)) && (screen_rel_x <= (enemy_center_x + 37)) &&
                        (v_cnt >= (enemy_center_y - 37)) && (v_cnt <= (enemy_center_y + 37));

    // 計算 Enemy 旋轉位址
    wire [16:0] calc_addr_enemy;
    car_addr addr_logic_enemy (
        .degree(enemy_degree),
        .pixel_x(screen_rel_x - (enemy_center_x - 10'd37)), // 使用 wire 運算後的座標
        .pixel_y(v_cnt - (enemy_center_y - 10'd37)),
        .rom_addr(calc_addr_enemy)
    );

    // 分配位址給 BRAM
    always @(*) begin
        addr_car_self  = is_self_box  ? calc_addr_self  : 17'd0;
        addr_car_enemy = is_enemy_box ? calc_addr_enemy : 17'd0;
    end

    // 雙埠記憶體實例化
    blk_mem_gen_1 car_ram (
        .clka(clk_25MHz), .addra(addr_car_self), .douta(data_car_self),   // Port A: Self
        .clkb(clk_25MHz), .addrb(addr_car_enemy), .doutb(data_car_enemy)  // Port B: Enemy
    );

    // --- 4. 最終顏色輸出 (Priority Mux) ---
    reg [11:0] final_color;
    
    always @(*) begin
        if (!valid) begin
            final_color = 12'h000; // Blanking
        end else if (is_separator) begin
            final_color = SEPARATOR_COLOR; // 分割線
        end 
        else begin
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