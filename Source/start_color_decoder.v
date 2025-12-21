// Color Decoder for Start state
module start_color_decoder (
    input  wire  [3:0] start_color_index,
    output reg  [11:0] rgb_data
);
    // 根據 Python centroids 數值轉回 Hex
    0: (11, 14, 11),#green
    1: (13,13,0),#yellow
    2: (15, 15, 15),  
    3: (12, 5, 4),#red
    4: (7, 11, 10),#greenblue
    5: (6,12,11),#darkgreen
    6: (4,3,5),#darkpurple
    7: (10,12,5)#lime
    always @(*) begin
        case (start_color_index)
            4'd0:    rgb_data = 12'hBEB;
            4'd1:    rgb_data = 12'hDD0;
            4'd2:    rgb_data = 12'hFFF;
            4'd3:    rgb_data = 12'hC54; 
            4'd4:    rgb_data = 12'h7BA; 
            4'd5:    rgb_data = 12'h6CB; 
            4'd6:    rgb_data = 12'h435; 
            4'd7:    rgb_data = 12'hAC5;
            default: rgb_data = 12'hF0F; // 錯誤處理 (紫色)，若出現預期外的數值方便除錯
        endcase
    end
endmodule