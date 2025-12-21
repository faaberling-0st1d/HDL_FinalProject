(* use_dsp = "no" *)
module car_addr (
    input wire [3:0] degree,     // 0~359
    input wire [9:0] pixel_x,    // 0~74
    input wire [9:0] pixel_y,    // 0~74
    output reg [16:0] rom_addr   // 0~89999
);
    // --------------------------------------------------------
    // Step 1: 角度轉 Index (0~15)
    // --------------------------------------------------------
    // --------------------------------------------------------
    // Step 2: 計算位址
    // --------------------------------------------------------
    wire is_bottom_row;
    wire [2:0] col_pos;
    
    assign is_bottom_row = degree[3]; 
    assign col_pos       = degree[2:0];

    wire [16:0] bank_offset;
    assign bank_offset = (is_bottom_row) ? 17'd45000 : 17'd0;

    // --------------------------------------------------------
    // [修正] 移除乘法器，改用移位加法 (Shift-Add)
    // --------------------------------------------------------
    
    // Original: pixel_y * 600
    // 600 = 512 + 64 + 16 + 8 = (1<<9) + (1<<6) + (1<<4) + (1<<3)
    wire [19:0] row_offset; 
    assign row_offset = (pixel_y << 9) + (pixel_y << 6) + (pixel_y << 4) + (pixel_y << 3);

    // Original: col_pos * 75
    // 75 = 64 + 8 + 2 + 1 = (1<<6) + (1<<3) + (1<<1) + 1
    // col_pos is small (3 bits), result fits in 10 bits easily
    wire [9:0] img_x_offset;
    // 這裡 col_pos 是 3 bits，直接轉型避免寬度警告
    wire [9:0] col_pos_ext = {7'b0, col_pos};
    assign img_x_offset = (col_pos_ext << 6) + (col_pos_ext << 3) + (col_pos_ext << 1) + col_pos_ext;

    // Final Sum
    reg [19:0] final_sum; 
    always @(*) begin
        final_sum = bank_offset + row_offset + img_x_offset + pixel_x;
        rom_addr = final_sum[16:0];
    end
endmodule