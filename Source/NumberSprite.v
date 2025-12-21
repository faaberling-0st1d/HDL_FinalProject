module NumberSprite (
    input [9:0] h_cnt,
    input [9:0] v_cnt,
    input [1:0] num,
    output reg is_pixel // Return true if that pixel should be colored.
);
    wire [9:0] rel_x = h_cnt - 10'd290;
    wire [9:0] rel_y = v_cnt - 10'd190;
    
    wire in_box = (h_cnt >= 290 && h_cnt < 350 && v_cnt >= 190 && v_cnt <= 290);

    always @(*) begin
        is_pixel = 0;
        if (in_box) begin
            case (num)
                2'd1: is_pixel = (rel_x >= 25 && rel_x <= 35);
                2'd2: begin
                    if (rel_y <= 10 || (rel_y >= 45 && rel_y <= 55) || rel_y >= 90) is_pixel = 1; // 三橫
                    if ((rel_x >= 50 && rel_y < 50) || (rel_x <= 10 && rel_y > 50)) is_pixel = 1; // 兩豎
                end
                2'd3: begin
                    if (rel_y <= 10 || (rel_y >= 45 && rel_y <= 55) || rel_y >= 90) is_pixel = 1; // 三橫
                    if (rel_x >= 50) is_pixel = 1; // 一整條右邊豎線
                end
            endcase
        end
    end
endmodule