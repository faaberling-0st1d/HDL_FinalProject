// Color Decoder for Start state
module start_color_decoder (
    input  wire  [3:0] start_color_index,
    output reg  [11:0] rgb_data
);
   
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
// Color Decoder for Start state
module final_color_decoder (
    input  wire  [1:0] final_color_index,
    output reg  [11:0] rgb_data
);
   
    always @(*) begin
        case (final_color_index)
            2'd0:    rgb_data = 12'hFE0;
            2'd1:    rgb_data = 12'h799;
            2'd2:    rgb_data = 12'hFFF;
            2'd3:    rgb_data = 12'hBE9; 
            default: rgb_data = 12'hF0F; // 錯誤處理 (紫色)，若出現預期外的數值方便除錯
        endcase
    end
endmodule