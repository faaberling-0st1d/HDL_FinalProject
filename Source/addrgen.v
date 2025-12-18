module grid_address_calc (
    input wire [8:0] degree,     // 0~359
    input wire [6:0] pixel_x,    // 0~74
    input wire [6:0] pixel_y,    // 0~74
    output reg [16:0] rom_addr   // 0~89999
);

    // --------------------------------------------------------
    // Step 1: 角度轉 Index (0~15)
    // --------------------------------------------------------
    reg [3:0] img_index;
    
    always @(*) begin
        // 這裡維持之前的邏輯
        if (degree < 23)       img_index = 4'd0;
        else if (degree < 45)  img_index = 4'd1;
        else if (degree < 68)  img_index = 4'd2;
        else if (degree < 90)  img_index = 4'd3;
        else if (degree < 113) img_index = 4'd4;
        else if (degree < 135) img_index = 4'd5;
        else if (degree < 158) img_index = 4'd6;
        else if (degree < 180) img_index = 4'd7;
        else if (degree < 203) img_index = 4'd8;
        else if (degree < 225) img_index = 4'd9;
        else if (degree < 248) img_index = 4'd10;
        else if (degree < 270) img_index = 4'd11;
        else if (degree < 293) img_index = 4'd12;
        else if (degree < 315) img_index = 4'd13;
        else if (degree < 338) img_index = 4'd14;
        else                   img_index = 4'd15;
    end

    // --------------------------------------------------------
    // Step 2: 計算位址 (針對 8x2 排列優化)
    // --------------------------------------------------------
    
    // 解析 Index
    wire is_bottom_row;  // 是否為下半部 (Index 8-15)
    wire [2:0] col_pos;  // 橫向是第幾張 (0-7)

    // 利用位元切片，完全不需要運算資源
    assign is_bottom_row = img_index[3]; // 取第 4 個 bit (數值 8)
    assign col_pos       = img_index[2:0]; // 取後 3 個 bits (數值 0-7)

    
    // 計算各部分的 Offset
    // 1. Bank Offset: 如果是下半部，起始點直接 +45000 (上半部總像素)
    wire [16:0] bank_offset;
    assign bank_offset = (is_bottom_row) ? 17'd45000 : 17'd0;

    // 2. Row Offset: pixel_y * 600 (大圖寬度)
    wire [16:0] row_offset;
    assign row_offset = pixel_y * 10'd600;

    // 3. Col Offset: 這一排的第幾張圖 * 75
    wire [9:0] img_x_offset;
    assign img_x_offset = col_pos * 7'd75;

    // 4. Final Sum
    always @(*) begin
        // Address = Bank(45000 or 0) + Y_Scan(y*600) + Image_X(idx*75) + Local_X
        rom_addr = bank_offset + row_offset + img_x_offset + pixel_x;
    end
endmodule