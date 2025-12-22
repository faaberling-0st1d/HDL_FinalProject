`define SILENCE 32'd50000000
`define C4      32'd262   // C4 
`define D4      32'd294   // D4
`define E4      32'd330   // E4
`define F4      32'd349   // F4
`define G4      32'd392   // G4
`define A4      32'd440   // A4
`define B4      32'd494   // B4
`define C5      32'd524   // C5
`define D5      32'd588   // D5
`define E5      32'd660   // E5
`define F5      32'd698   // F5
`define G5      32'd784   // G5
`define A5      32'd880   // A5
`define B5      32'd988   // B5

module AudioEncoder (
    input wire clk,
    input wire rst,

    input wire [2:0] state, // From State Encoder

    input wire [1:0] p1_flag_order,
    input wire [1:0] p2_flag_order,

    output wire audio_mclk,
    output wire audio_lrck,
    output wire audio_sck,
    output wire audio_sdin
);

    /* [Parameters Definition] */
    localparam SECOND = 100_000_000;
    localparam DIV_C4   = 22'd190_840; // 262 Hz
    localparam DIV_D4   = 22'd170_068; // 294 Hz
    localparam DIV_E4   = 22'd151_515; // 330 Hz
    localparam DIV_F4   = 22'd143_266; // 349 Hz
    localparam DIV_G4   = 22'd127_551; // 392 Hz
    localparam DIV_A4   = 22'd113_636; // 440 Hz
    localparam DIV_A5   = 22'd56_818;  // 880 Hz
    localparam DIV_MUTE = 22'h3FFFFF;  // Muted (low frequency)

    /* [States] */
    localparam IDLE      = 3'd0;
    localparam SETTING   = 3'd1;
    // localparam SYNCING = 3'd2;
    localparam COUNTDOWN = 3'd3;
    localparam RACING    = 3'd4;
    localparam PAUSE     = 3'd5;
    localparam FINISH    = 3'd6;

    localparam BEEP_FREQ = 100000;

    /* [State Processing] */
    reg  [2:0] prev_state; // The previous state
    always @(posedge clk) begin
        if (rst) prev_state <= 3'd0;
        else     prev_state <= state;
    end
    wire start_countdown = (prev_state == IDLE      && state == COUNTDOWN);
    wire start_racing    = (prev_state == COUNTDOWN && state == RACING);

    /* [Flag Processing] */
    reg [1:0] prev_p1_flag_order, prev_p2_flag_order;
    always @(posedge clk) begin
        if (rst) begin
            prev_p1_flag_order <= 2'd0;
            prev_p2_flag_order <= 2'd0;
        end else begin
            prev_p1_flag_order <= p1_flag_order;
            prev_p2_flag_order <= p2_flag_order;
        end
    end
    wire p1_checkpoint_passed = (prev_p1_flag_order != p1_flag_order);
    wire p2_checkpoint_passed = (prev_p2_flag_order != p2_flag_order);

    /* [II. Local Counter] */
    reg [28:0] local_cnt, local_cnt_2;
    reg        go_audio_effect_playing; // 3 (low), 2 (low), 1 (low), GO! (HIGH)
    reg        p1_checkpoint_effect_playing;
    reg        p2_checkpoint_effect_playing;
    // reg [31:0] freq_cnt;//
    always @(posedge clk) begin
        if (rst) begin
            local_cnt                    <= 0;
            local_cnt_2                  <= 0;
            go_audio_effect_playing      <= 0;
            p1_checkpoint_effect_playing <= 0;
            p2_checkpoint_effect_playing <= 0;
            
        end else begin
            if (start_racing) begin // Reset the counter and the flag!
                local_cnt                    <= 0;
                local_cnt_2                  <= 0;
                go_audio_effect_playing      <= 1;
                p1_checkpoint_effect_playing <= 0;
                p2_checkpoint_effect_playing <= 0;

            end else begin
                case (state)
                    IDLE: begin
                        local_cnt                    <= 0;
                        local_cnt_2                  <= 0;
                        go_audio_effect_playing      <= 0;
                        p1_checkpoint_effect_playing <= 0;
                        p2_checkpoint_effect_playing <= 0;
                    end
                    COUNTDOWN: begin
                        if (local_cnt < SECOND) local_cnt <= local_cnt + 1;
                        else                    local_cnt <= 0;
                        local_cnt_2                  <= 0;
                        go_audio_effect_playing      <= 0;
                        p1_checkpoint_effect_playing <= 0;
                        p2_checkpoint_effect_playing <= 0;
                    end
                    RACING: begin
                        if (go_audio_effect_playing) begin
                            if (local_cnt < SECOND) begin
                                local_cnt               <= local_cnt + 1;
                                go_audio_effect_playing <= 1;
                            end else begin
                                go_audio_effect_playing <= 0;
                                local_cnt               <= 0;
                            end
                        end else begin
                            // P1 Checkpoint sound effect
                            if (p1_checkpoint_passed) begin
                                local_cnt                    <= 0;
                                p1_checkpoint_effect_playing <= 1;
                            end else if (p1_checkpoint_effect_playing && local_cnt < 29'd300_000_000) begin
                                local_cnt                    <= local_cnt + 1; // 我相信他不會那麼快經過兩個 checkpoint 啦 :D
                                p1_checkpoint_effect_playing <= 1;
                            end else begin
                                local_cnt                    <= 0;
                                p1_checkpoint_effect_playing <= 0;
                            end

                            // P2 Checkpoint sound effect
                            if (p2_checkpoint_passed) begin
                                local_cnt_2                  <= 0;
                                p2_checkpoint_effect_playing <= 1;
                            end else if (p2_checkpoint_effect_playing && local_cnt_2 < 29'd300_000_000) begin
                                local_cnt_2                  <= local_cnt_2 + 1;
                                p2_checkpoint_effect_playing <= 1;
                            end else begin
                                local_cnt_2                  <= 0;
                                p2_checkpoint_effect_playing <= 0;
                            end
                        end
                    end
                    default: begin
                        local_cnt                    <= 0;
                        local_cnt_2                  <= 0;
                        go_audio_effect_playing      <= 0;
                        p1_checkpoint_effect_playing <= 0;
                        p2_checkpoint_effect_playing <= 0;
                    end
                endcase
            end
        end
    end

    /* [III. Sound Generation] */
    reg [21:0] target_div;
    reg  [2:0] volume_ctrl;

    always @(*) begin
        target_div = DIV_MUTE;
        volume_ctrl = 3'b000; // Default: Mute

        if (state == COUNTDOWN) begin
            // Beep in the beginning 0.15 second
            if (local_cnt < 28'd15_000_000) begin
                target_div = DIV_A4;
                volume_ctrl = 3'b100;
            end

        end else if (state == RACING) begin
            target_div  = DIV_MUTE;
            volume_ctrl = 3'b000;

            if (go_audio_effect_playing /* "go" effect yet to be played once */ && local_cnt < SECOND) begin
                target_div = DIV_A5;
                volume_ctrl = 3'b100;
            end

            if (p1_checkpoint_effect_playing && local_cnt < 29'd100_000_000) begin
                target_div  = DIV_D4;
                volume_ctrl = 3'b100;
            end else if (p1_checkpoint_effect_playing && local_cnt < 29'd200_000_000) begin
                target_div  = DIV_F4;
                volume_ctrl = 3'b100;
            end else if (p1_checkpoint_effect_playing && local_cnt < 29'd300_000_000) begin
                target_div  = DIV_A4;
                volume_ctrl = 3'b100;
            end

            if (p2_checkpoint_effect_playing && local_cnt_2 < 29'd100_000_000) begin
                target_div  = DIV_C4;
                volume_ctrl = 3'b100;
            end else if (p2_checkpoint_effect_playing && local_cnt_2 < 29'd200_000_000) begin
                target_div  = DIV_E4;
                volume_ctrl = 3'b100;
            end else if (p2_checkpoint_effect_playing && local_cnt_2 < 29'd300_000_000) begin
                target_div  = DIV_G4;
                volume_ctrl = 3'b100;
            end
        end
    end

    /* [Audio Modules] */
    wire [15:0] audio_l, audio_r;

    note_gen note (
        .clk(clk), .rst(rst),
        .volume(volume_ctrl),
        .note_div_left(target_div),
        .note_div_right(target_div),
        .audio_left(audio_l),
        .audio_right(audio_r)
    );
    
    speaker_control speaker (
        .clk(clk), .rst(rst),
        .audio_in_left(audio_l),
        .audio_in_right(audio_r),
        .audio_mclk(audio_mclk),
        .audio_lrck(audio_lrck),
        .audio_sck(audio_sck),
        .audio_sdin(audio_sdin)
    ); 

endmodule

module note_gen(
    input clk, // clock from crystal
    input rst, // active high reset

    input [2:0] volume, 

    input [21:0] note_div_left, // div for note generation
    input [21:0] note_div_right,
    
    output [15:0] audio_left,
    output [15:0] audio_right
    );

    // Declare internal signals
    reg [21:0] clk_cnt_next, clk_cnt;
    reg [21:0] clk_cnt_next_2, clk_cnt_2;
    reg b_clk, b_clk_next;
    reg c_clk, c_clk_next;

    // Note frequency generation
    // clk_cnt, clk_cnt_2, b_clk, c_clk
    always @(posedge clk or posedge rst)
        if (rst == 1'b1)
            begin
                clk_cnt <= 22'd0;
                clk_cnt_2 <= 22'd0;
                b_clk <= 1'b0;
                c_clk <= 1'b0;
            end
        else
            begin
                clk_cnt <= clk_cnt_next;
                clk_cnt_2 <= clk_cnt_next_2;
                b_clk <= b_clk_next;
                c_clk <= c_clk_next;
            end
    
    // clk_cnt_next, b_clk_next
    always @*
        if (clk_cnt == note_div_left)
            begin
                clk_cnt_next = 22'd0;
                b_clk_next = ~b_clk;
            end
        else
            begin
                clk_cnt_next = clk_cnt + 1'b1;
                b_clk_next = b_clk;
            end

    // clk_cnt_next_2, c_clk_next
    always @*
        if (clk_cnt_2 == note_div_right)
            begin
                clk_cnt_next_2 = 22'd0;
                c_clk_next = ~c_clk;
            end
        else
            begin
                clk_cnt_next_2 = clk_cnt_2 + 1'b1;
                c_clk_next = c_clk;
            end

    // Assign the amplitude of the note
    // Volume is controlled here
    assign audio_left = (note_div_left == 22'd1) ? 16'h0000 : 
                                (b_clk == 1'b0) ? 16'hE000 >> (16'd8 - volume) : 16'h2000 >> (16'd8 - volume);
    assign audio_right = (note_div_right == 22'd1) ? 16'h0000 : 
                                (c_clk == 1'b0) ? 16'hE000 >> (16'd8 - volume) : 16'h2000 >> (16'd8 - volume);
endmodule

module speaker_control(
    input clk,  // clock from the crystal
    input rst,  // active high reset
    input [15:0] audio_in_left, // left channel audio data input
    input [15:0] audio_in_right, // right channel audio data input
    output audio_mclk, // master clock
    output audio_lrck, // left-right clock, Word Select clock, or sample rate clock
    output audio_sck, // serial clock
    output reg audio_sdin // serial audio data input
    ); 

    // Declare internal signal nodes 
    wire [8:0] clk_cnt_next;
    reg [8:0] clk_cnt;
    reg [15:0] audio_left, audio_right;

    // Counter for the clock divider
    assign clk_cnt_next = clk_cnt + 1'b1;

    always @(posedge clk or posedge rst)
        if (rst == 1'b1)
            clk_cnt <= 9'd0;
        else
            clk_cnt <= clk_cnt_next;

    // Assign divided clock output
    assign audio_mclk = clk_cnt[1];
    assign audio_lrck = clk_cnt[8];
    assign audio_sck = 1'b1; // use internal serial clock mode

    // audio input data buffer
    always @(posedge clk_cnt[8] or posedge rst)
        if (rst == 1'b1)
            begin
                audio_left <= 16'd0;
                audio_right <= 16'd0;
            end
        else
            begin
                audio_left <= audio_in_left;
                audio_right <= audio_in_right;
            end

    always @*
        case (clk_cnt[8:4])
            5'b00000: audio_sdin = audio_right[0];
            5'b00001: audio_sdin = audio_left[15];
            5'b00010: audio_sdin = audio_left[14];
            5'b00011: audio_sdin = audio_left[13];
            5'b00100: audio_sdin = audio_left[12];
            5'b00101: audio_sdin = audio_left[11];
            5'b00110: audio_sdin = audio_left[10];
            5'b00111: audio_sdin = audio_left[9];
            5'b01000: audio_sdin = audio_left[8];
            5'b01001: audio_sdin = audio_left[7];
            5'b01010: audio_sdin = audio_left[6];
            5'b01011: audio_sdin = audio_left[5];
            5'b01100: audio_sdin = audio_left[4];
            5'b01101: audio_sdin = audio_left[3];
            5'b01110: audio_sdin = audio_left[2];
            5'b01111: audio_sdin = audio_left[1];
            5'b10000: audio_sdin = audio_left[0];
            5'b10001: audio_sdin = audio_right[15];
            5'b10010: audio_sdin = audio_right[14];
            5'b10011: audio_sdin = audio_right[13];
            5'b10100: audio_sdin = audio_right[12];
            5'b10101: audio_sdin = audio_right[11];
            5'b10110: audio_sdin = audio_right[10];
            5'b10111: audio_sdin = audio_right[9];
            5'b11000: audio_sdin = audio_right[8];
            5'b11001: audio_sdin = audio_right[7];
            5'b11010: audio_sdin = audio_right[6];
            5'b11011: audio_sdin = audio_right[5];
            5'b11100: audio_sdin = audio_right[4];
            5'b11101: audio_sdin = audio_right[3];
            5'b11110: audio_sdin = audio_right[2];
            5'b11111: audio_sdin = audio_right[1];
            default: audio_sdin = 1'b0;
        endcase

endmodule