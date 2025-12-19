//顏色編碼：0=透明, 1=紅, 2=深紅, 3=黃, 4=黑, 5=灰, 6=綠, 7=土黃, 8=白
module color_decoder (
    input wire [3:0] color_index,  // 從 BRAM 讀出來的 0~15
    output reg [11:0] rgb_data     // 轉還原給 VGA 的 12-bit RGB (RRRRGGGGBBBB)
);

    // 根據你的 Python centroids 數值轉回 Hex
    // 1: (13, 4, 2) -> hex D42
    // 2: (9, 2, 1)  -> hex 921
    // 3: (15, 15, 9)-> hex FF9
    // 4: (2, 1, 0)  -> hex 210
    // 5: (7, 7, 8)  -> hex 778
    // 0: 透明 -> 這裡暫時設為純黑或特定顏色(如粉紅)來讓 VGA 模組做去背
    always @(*) begin
        case (color_index)
            4'd0: rgb_data = 12'h000; // 透明 (Transparent)，通常輸出全黑，由 VGA 邏輯決定不顯示
            4'd1: rgb_data = 12'hD42; // 紅 (Centroid: 13,4,2)
            4'd2: rgb_data = 12'h921; // 深紅 (Centroid: 9,2,1)
            4'd3: rgb_data = 12'hFF9; // 黃 (Centroid: 15,15,9)
            4'd4: rgb_data = 12'h210; // 黑/深雜訊 (Centroid: 2,1,0)
            4'd5: rgb_data = 12'h778; // 灰 (Centroid: 7,7,8)
            4'd6: rgb_data = 12'h6B4; // 綠
            4'd7: rgb_data = 12'hDD0; //土黃
            4'd8: rgb_data = 12'hFFF; // 白
            default: rgb_data = 12'hF0F; // 錯誤處理 (紫色)，若出現預期外的數值方便除錯
        endcase
    end

endmodule