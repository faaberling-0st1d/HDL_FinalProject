/* [Number Sprite Module]
 * In order to display number onto the screen when 
 */

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
                2'd1: begin
                    is_pixel = (rel_x >= 20 && rel_x <= 40);
                end
                2'd2: begin
                    if (rel_y <= 20 || (rel_y >= 40 && rel_y <= 60) || rel_y >= 80) is_pixel = 1; // 三橫
                    if ((rel_x >= 40 && rel_y < 50) || (rel_x <= 20 && rel_y > 50)) is_pixel = 1; // 兩豎
                end
                2'd3: begin
                    if (rel_y <= 20 || (rel_y >= 40 && rel_y <= 60) || rel_y >= 80) is_pixel = 1; // 三橫
                    if (rel_x >= 40) is_pixel = 1; // 一整條右邊豎線
                end
            endcase
        end
    end
endmodule

module PauseResumeSprite (
    input       clk,
    input       rst,
    input [9:0] h_cnt,
    input [9:0] v_cnt,
    input [2:0] state,

    output reg  is_pixel // Return true if that pixel should be colored.
);
    /* [States] */
    localparam IDLE      = 3'd0;
    localparam SETTING   = 3'd1;
    // localparam SYNCING = 3'd2;
    localparam COUNTDOWN = 3'd3;
    localparam RACING    = 3'd4;
    localparam PAUSE     = 3'd5;
    localparam FINISH    = 3'd6;

    wire [9:0] rel_x = h_cnt - 10'd290;
    wire [9:0] rel_y = v_cnt - 10'd190;
    wire in_box = (h_cnt >= 290 && h_cnt < 350 && v_cnt >= 190 && v_cnt <= 290);

    reg [2:0] state_ff1, state_ff2;
    always @(posedge clk) begin
        state_ff1 <= state;
        state_ff2 <= state_ff1;
    end
    wire has_resumed = (state_ff2 == PAUSE && state_ff1 == RACING);
    
    reg [28:0] resume_cnt;
    always @(posedge clk) begin
        if (rst) begin
            resume_cnt  <= 29'd0;
        end else begin
            if (state == PAUSE) begin
                resume_cnt <= 29'd0;

            end else if (state == RACING) begin
                if (has_resumed) 
                    resume_cnt <= 29'd1;
                else if (0 < resume_cnt && resume_cnt < 29'd100_000_000)
                    resume_cnt <= resume_cnt + 29'd1;
                else
                    resume_cnt <= 29'd0;
            end
        end
    end

    wire is_pause  = (state_ff1 == PAUSE);
    wire is_resume = (state_ff1 == RACING && 0 < resume_cnt && resume_cnt < 29'd100_000_000);
                
    always @(*) begin
        is_pixel = 0;
        if (in_box) begin
            if (is_pause && !is_resume) begin
                is_pixel = (rel_x <= 20) || (40 <= rel_x);
            end else if (!is_pause && is_resume) begin
                is_pixel = (rel_y <= 50 && 5 <= rel_x && rel_x <= 55 && rel_x-5 <= rel_y) 
                            || (50 < rel_y && 5 <= rel_x && rel_x <= 55 && rel_x + rel_y <= 110);
            end else begin
                is_pixel = 0;
            end
        end
    end
endmodule

module WinningSprite (
    input [9:0] h_cnt,
    input [9:0] v_cnt,
    input [1:0] winning_player,

    output reg  is_pixel
);
    // The width and height of the winning banner.
    localparam WIDTH  = 10'd280;
    localparam HEIGHT = 10'd20;

    // Coordinates settings.
    wire [9:0] START_X = (winning_player == 2'b10 /* p2 */) ? 10'd340 
                        : (winning_player == 2'b01 /* p1 */) ? 10'd20 : 10'd0;
    localparam START_Y = 10'd170;

    // ROM
    reg [279:0] winning_text_rom [0:19]; // 20 rows, 280 columns for each row.

    // Initialization: reading .mem
    initial begin
        $readmemb("YOU_WON.mem", winning_text_rom);
    end

    wire [9:0] rel_x = h_cnt - START_X;
    wire [9:0] rel_y = v_cnt - START_Y;
    wire in_box = (START_X <= h_cnt && h_cnt <= START_X + WIDTH)
                    && (START_Y <= v_cnt && v_cnt <= START_Y + HEIGHT);
    
    always @(*) begin
        if (in_box) begin
            if (winning_player != 2'b00)
                is_pixel <= winning_text_rom[rel_y][279 - rel_x];
            else
                is_pixel <= 0;
        end
    end
endmodule