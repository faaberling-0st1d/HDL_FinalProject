// Color Decoder for Start state
module start_color_decoder (
    input  wire  [3:0] start_color_index,
    output reg  [11:0] rgb_data
);
    // 根據 Python centroids 數值轉回 Hex
    // 1: (13, 4, 2) -> hex D42
    // 2: (9, 2, 1)  -> hex 921
    // 3: (15, 15, 9)-> hex FF9
    // 4: (2, 1, 0)  -> hex 210
    // 5: (7, 7, 8)  -> hex 778
    // 0: 透明 -> 這裡暫時設為純黑或特定顏色(如粉紅)來讓 VGA 模組做去背
    always @(*) begin
        case (start_color_index)
            4'd0:    rgb_data = 12'h000;
            4'd1:    rgb_data = 12'h
            4'd2:    rgb_data = 12'h
            4'd3:    rgb_data = 12'hFF9; 
            4'd4:    rgb_data = 12'h210; 
            4'd5:    rgb_data = 12'h778; 
            4'd6:    rgb_data = 12'h6B4; 
            4'd7:    rgb_data = 12'hDD0;
            4'd8:    rgb_data = 12'hFFF; 
            4'd9:    rgb_data = 12'h0F0;
            4'd10:   rgb_data = 12'hBBB;
            default: rgb_data = 12'hF0F; // 錯誤處理 (紫色)，若出現預期外的數值方便除錯
        endcase
    end
endmodule