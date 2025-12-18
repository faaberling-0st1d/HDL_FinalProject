module Top (
    input wire clk,
    input wire rst,

    input wire [9:0] scroll_x, // 地圖 X 軸捲動位置
    input wire [9:0] scroll_y, // 地圖 Y 軸捲動位置
    
    output wire [3:0] vgaRed,
    output wire [3:0] vgaGreen,
    output wire [3:0] vgaBlue,
    output wire hsync,
    output wire vsync
);

    // --- 參數設定 ---
    // 假設你的地圖在記憶體中的起始位置是 90001 (如你先前所述)
    // 如果地圖是獨立存放在 blk_mem_gen_0 的第 0 格，請改成 0
    parameter MAP_WIDTH     = 10'd320;
    parameter MAP_HEIGHT    = 10'd240;
    parameter OUT_BOUND_COLOR = 12'h6B4; // 界外顯示綠色

    // --- 內部訊號 ---
    wire clk_25MHz;
    wire valid;
    wire [9:0] h_cnt; // Range: 0-639
    wire [9:0] v_cnt; // Range: 0-479
    wire [3:0] degree,   // 車子角度 (0-15)
    
    // 記憶體位址與資料
    reg  [16:0] pixel_addr; // 地圖位址
    wire [11:0] pixel_data; // 地圖資料 (Map)
    wire [16:0] car_pixel;  // 車子位址
    wire [11:0] car_data;   // 車子資料 (Car)

    // 邏輯判斷旗標
    wire is_center_box;
    wire is_out_of_map;
    
    // 計算後的「世界地圖」座標
    wire [9:0] map_global_x;
    wire [9:0] map_global_y;

    // --- 1. Clock & VGA Controller ---
    clock_divider #(.n(2)) clk25Mhz_inst (
        .clk(clk),
        .clk_div(clk_25MHz)
    );

    vga_controller vga_inst (
        .pclk(clk_25MHz), .reset(rst),
        .hsync(hsync), .vsync(vsync), .valid(valid),
        .h_cnt(h_cnt), .v_cnt(v_cnt)
    );
    PhysicsEngin physic(
        //待完成
        .clk(clk),
        .rst(rst),
        .state(), // From StateEncoder
        .operation_code, // From OperationEncoder Module
        .boost(),          // From OperationEncoder Module
        .pos_x(),
        .pos_y(),
        .angle_index(degree),
    );
    
    // --- 2. 記憶體模組 (BRAM) ---
    // 地圖記憶體
    blk_mem_gen_0 blk_mem_inst (
        .clka(clk_25MHz),
        .addra(pixel_addr), 
        .douta(pixel_data)
    );
    
    // 車子記憶體
    blk_mem_gen_1 blk_mem_inst1 (
        .clka(clk_25MHz),
        .addra(car_pixel), 
        .douta(car_data)
    );

    // --- 3. 邏輯運算 ---

    // [中央挖空邏輯]
    // 螢幕中心附近 75x75 的區域
    assign is_center_box = (h_cnt >= 283 && h_cnt <= 357) && 
                           (v_cnt >= 203 && v_cnt <= 277);

    // [地圖座標計算與邊界檢查]
    // 1. (h_cnt >> 1): 將 640x480 縮小對應到 320x240
    // 2. + scroll: 加上捲動偏移量
    assign map_global_x = (h_cnt >> 1) + scroll_x;
    assign map_global_y = (v_cnt >> 1) + scroll_y;

    // 判斷是否超出地圖原本的 320x240 範圍
    assign is_out_of_map = (map_global_x >= MAP_WIDTH) || (map_global_y >= MAP_HEIGHT);

    // [車子位址計算模組]
    car_addr ccc(
        .degree(degree),        // 接上輸入的角度
        .pixel_x(h_cnt - 283),  // 計算相對於中央框框左上角的 X
        .pixel_y(v_cnt - 203),  // 計算相對於中央框框左上角的 Y
        .rom_addr(car_pixel)    // 輸出計算好的記憶體位址
    );

    // [地圖記憶體位址計算]
    always @(*) begin
        if (is_out_of_map) begin
            // 如果超出地圖範圍，不需要讀取有效資料 (設為0或其他安全值)
            pixel_addr = 0;
        end else begin
            // 公式: Base + (Y * Width) + X
            pixel_addr = (map_global_y * 320) + map_global_x;
        end
    end

    // --- 4. 最終顏色輸出 (Priority Logic) ---
    // 優先順序: 
    // 1. !valid (消隱期) -> 全黑
    // 2. 中央區域 AND 車子非透明 -> 顯示車子
    // 3. 超出地圖範圍 -> 顯示綠色
    // 4. 其他 -> 顯示地圖

    reg [11:0] final_color;

    always @(*) begin
        if (!valid) begin
            final_color = 12'h000;
        end 
        // 如果在中央格子 且 車子顏色不是透明色(12'h000)
        else if (is_center_box && car_data != 12'h000) begin
            final_color = car_data;
        end 
        // (重要) 如果上面沒顯示車子，且地圖座標已經出界 -> 顯示綠色背景
        else if (is_out_of_map) begin
            final_color = OUT_BOUND_COLOR; 
        end 
        // 顯示正常地圖背景 (這會透過車子的透明部分顯示出來，或者顯示在車子框框外)
        else begin
            final_color = pixel_data;
        end
    end

    assign vgaRed   = final_color[11:8];
    assign vgaGreen = final_color[7:4];
    assign vgaBlue  = final_color[3:0];

endmodule