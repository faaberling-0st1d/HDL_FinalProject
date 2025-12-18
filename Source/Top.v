module Top (
    input wire clk,           
    input wire rst,     
    output wire [3:0] vgaRed,
    output wire [3:0] vgaGreen,
    output wire [3:0] vgaBlue,
    output wire hsync,
    output wire vsync
);

    wire clk_25MHz;
    wire valid;
    wire [9:0] h_cnt; // Range: 0-639 (visible)
    wire [9:0] v_cnt; // Range: 0-479 (visible)
    
    // 記憶體相關
    reg [16:0] pixel_addr;
    wire [11:0] pixel_data; // 假設你的 RGB 是 12-bit (4-4-4)
    
    // 中央區域判斷信號
    wire is_center_box;
    
    // 捲動偏移量 (如果要讓地圖捲動，可以改變這個值)
    reg [9:0] scroll_y = 0; 


    // Clock Divider (產生 25MHz VGA Pixel Clock)
    clock_divider #(.n(2)) clk25Mhz_inst (
        .clk(clk),
        .clk_div(clk_25MHz)
    );

    // VGA Controller
    vga_controller vga_inst (
        .pclk(clk_25MHz),
        .reset(rst),
        .hsync(hsync),
        .vsync(vsync),
        .valid(valid),
        .h_cnt(h_cnt),
        .v_cnt(v_cnt)
    );

    // Block Memory (假設你的 IP Name 是 blk_mem_gen_0)
    // 注意：這裡需要根據你實際生成的 IP core 介面進行調整
    blk_mem_gen_0 blk_mem_inst (
        .clka(clk_25MHz),
        .addra(pixel_addr), // 輸入計算好的位址
        .douta(pixel_data)  // 輸出的顏色資料
    );


    // --- 中央 75x75 挖空邏輯 ---
    // 螢幕中心: (320, 240)
    // 寬度一半: 75 / 2 = 37.5 -> 取 37
    // X 範圍: 320 - 37 到 320 + 37 -> [283, 357]
    // Y 範圍: 240 - 37 到 240 + 37 -> [203, 277]
    assign is_center_box = (h_cnt >= 283 && h_cnt <= 357) && 
                           (v_cnt >= 203 && v_cnt <= 277);

    // --- 位址計算邏輯 ---
    always @(*) begin
        if (valid) begin
            if (is_center_box) begin
                // 如果在中央格子內，指向"其他東西"的位址
                // 這裡暫時設為 0 或者你可以設一個特殊的保留位址
                // 實際上這部分的顏色輸出會由下方的 assign 控制
                pixel_addr = 0; 
            end else begin
                // --- 地圖位址計算 ---
                // 1. 基礎位址: 90001
                // 2. 座標轉換: 螢幕 640x480 -> 地圖 320x240 (除以2，即右移 1 位)
                // 3. 捲動邏輯: (v_cnt >> 1) + scroll_y (這裡做簡單的垂直捲動示範)
                // 4. 公式: Base + (Y * Width) + X
                
                pixel_addr = 17'd90001 + ((v_cnt[9:1]) * 320) + (h_cnt[9:1]);
                
                // 如果你想做"循環捲動"，Y 軸需要對地圖高度取餘數 (假設地圖高 240)
                // pixel_addr = 17'd90001 + (((v_cnt[9:1] + scroll_y) % 240) * 320) + (h_cnt[9:1]);
            end
        end else begin
            pixel_addr = 0; //不在顯示範圍時歸零
        end
    end

    // --- 4. 顏色輸出邏輯 ---
    // 如果是中央格子，輸出黑色 (或其他顏色/你的車子邏輯)
    // 否則輸出記憶體讀到的地圖顏色
    assign vgaRed   = (valid && !is_center_box) ? pixel_data[11:8] : 
                      (valid && is_center_box)  ? 4'h0 : 4'h0; // 中央格子目前顯示黑色
                      
    assign vgaGreen = (valid && !is_center_box) ? pixel_data[7:4]  : 
                      (valid && is_center_box)  ? 4'h0 : 4'h0;
                      
    assign vgaBlue  = (valid && !is_center_box) ? pixel_data[3:0]  : 
                      (valid && is_center_box)  ? 4'hF : 4'h0; // 中央格子顯示藍色以供識別

endmodule