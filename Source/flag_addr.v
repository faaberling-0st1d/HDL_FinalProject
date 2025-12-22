module flag_addr (
    input  wire [9:0] h_cnt,       // 目前螢幕 X 座標
    input  wire [9:0] v_cnt,       // 目前螢幕 Y 座標
    input  wire [1:0] p1_order,    // P1 排列模式 (0:ABA, 1:BAB...)
    input  wire [1:0] p2_order,    // P2 排列模式
    output reg [13:0] mem_addr,    // 算出來給 BRAM 的位址
    output reg        is_active    // 輸出一個訊號告訴主程式：現在是否在卡片顯示範圍內？
);

    // --- 參數設定 ---
    parameter MEM_W = 120; // 記憶體總寬度
    parameter IMG_W = 60;  // 單張卡片寬度
    
    // --- 內部變數 ---
    reg [1:0] curr_slot;     // 0, 1, 2
    reg [9:0] local_x;       // 0~59
    reg [1:0] target_order;  // 當前要用的模式
    reg       use_img_right; // 0:左圖, 1:右圖
    reg [9:0] tex_x_offset;  // 0 或 60

    always @(*) begin
        // 初始化預設值
        mem_addr = 0;
        is_active = 0;
        
        curr_slot = 0;
        local_x = 0;
        target_order = 0;
        use_img_right = 0;

        // -------------------------------------------------------
        // Step 1: 判斷區域 (P1 或 P2) 與計算 Local X
        // -------------------------------------------------------
        
        // 檢查 Y 軸範圍 (HUD高度 360~480)
        if (v_cnt >= 360 && v_cnt < 480) begin
            
            if (h_cnt >= 60 && h_cnt < 240) begin
                // --- P1 區域 ---
                is_active = 1'b1;
                target_order = p1_order;
                
                if (h_cnt < 120) begin 
                    curr_slot = 0; local_x = h_cnt - 60; 
                end else if (h_cnt < 180) begin 
                    curr_slot = 1; local_x = h_cnt - 120; 
                end else begin 
                    curr_slot = 2; local_x = h_cnt - 180; 
                end

            end else if (h_cnt >= 400 && h_cnt < 580) begin
                // --- P2 區域 ---
                is_active = 1'b1;
                target_order = p2_order;

                if (h_cnt < 460) begin 
                    curr_slot = 0; local_x = h_cnt - 400; 
                end else if (h_cnt < 520) begin 
                    curr_slot = 1; local_x = h_cnt - 460; 
                end else begin 
                    curr_slot = 2; local_x = h_cnt - 520; 
                end
            end
        end

        // -------------------------------------------------------
        // Step 2: 根據模式決定要用左圖還是右圖
        // -------------------------------------------------------
        if (is_active) begin
            case (target_order)
                2'd0: use_img_right = 1'b0; // ABA
                2'd1: use_img_right = (curr_slot == 0) ? 1'b1 : 1'b0; // BAB
                2'd2: use_img_right = (curr_slot == 2) ? 1'b0 : 1'b1; // AAB
                2'd3: use_img_right = 1'b1;                           // BBB
                default: use_img_right = 1'b1;
            endcase

            // -------------------------------------------------------
            // Step 3: 計算最終位址
            // Address = (Local_Y * 120) + (Offset + Local_X)
            // -------------------------------------------------------
            tex_x_offset = (use_img_right) ? IMG_W : 0;
            
            // v_cnt - 360 是將螢幕座標轉換為圖片局部座標 (0~119)
            mem_addr = ((v_cnt - 360) * MEM_W) + (tex_x_offset + local_x);
            
        end else begin
            mem_addr = 0; // 不在範圍內，位址歸零 (避免讀取無效資料)
        end
    end

endmodule