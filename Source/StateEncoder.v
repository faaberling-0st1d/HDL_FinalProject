module StateEncoder (
    input clk,
    input rst,

    input start_btn,   // Game Starting Button
    input setting_btn, // Game Setting Button
    input pause_btn,   // Game Pause Button (for state COUNTDOWN & RACING)

    // input is_sync,     // Whether two FPGAs are connected or not. (先取消，目前改單人雙螢幕)
    input is_game_end, // Whether the racing game has ended. (遊戲結束)

    output reg [2:0] state,
    output reg [1:0] countdown_val
);
    /* [Buttons] */
    wire btn_clk = clk;
    // clock_divider #(.n(18)) clk_div (.clk(clk), .clk_div(btn_clk));
    // Debounce
    wire start_db, setting_db, pause_db;
    debounce db1(.pb_debounced(start_db),   .pb(start_btn),   .clk(btn_clk));
    debounce db2(.pb_debounced(setting_db), .pb(setting_btn), .clk(btn_clk));
    debounce db3(.pb_debounced(pause_db),   .pb(pause_btn),   .clk(btn_clk));
    // One-pulse
    wire start_op, setting_op, pause_op;
    onepulse op1(.signal(start_db),   .clk(btn_clk), .op(start_op));
    onepulse op2(.signal(setting_db), .clk(btn_clk), .op(setting_op));
    onepulse op3(.signal(pause_db),   .clk(btn_clk), .op(pause_op));

    /* [States] */
    reg [2:0] next_state;
    // Local parameters
    localparam IDLE      = 3'd0;
    localparam SETTING   = 3'd1;
    // localparam SYNCING = 3'd2;
    localparam COUNTDOWN = 3'd3;
    localparam RACING    = 3'd4;
    localparam PAUSE     = 3'd5;
    localparam FINISH    = 3'd6;

    /* [COUNTER] */
    reg [28:0] countdown_cnt, next_countdown_cnt;
    parameter SECOND = 29'd100_000_000;
    parameter COUNTDOWN_TIME_LIMIT = 3 * SECOND;

    always @(posedge clk) begin
        if (rst) begin
            state           <= IDLE;
            countdown_cnt   <= 29'd0;

        end else begin
            state           <= next_state;
            countdown_cnt   <= next_countdown_cnt;
        end
    end

    /* [Combinational Circuit]
     * `next_state`
     */
    always @(*) begin
        next_state = state;
        next_countdown_cnt = (state == COUNTDOWN) ? countdown_cnt : 28'd0; // Use the original counter value ONLY IF the current state is COUNTDOWN.

        case (state)
            IDLE: begin
                // If the user pressed the start button:
                if (start_op) begin
                    next_state = COUNTDOWN;
                    next_countdown_cnt = 29'd0;

                // Transition to state SETTING if setting button pressed.
                end else if (setting_op) begin
                    next_state = SETTING;
                end
            end

            SETTING: begin
                // Return to IDLE (game lobby) if the setting button is pressed again.
                if (setting_op) begin
                    next_state = IDLE;
                end
            end

            COUNTDOWN: begin
                if (countdown_cnt >= COUNTDOWN_TIME_LIMIT) begin
                    next_countdown_cnt = 29'd0;
                    next_state = RACING;
                end else begin
                    next_countdown_cnt = countdown_cnt + 1;
                end
            end

            RACING: begin
                // Transition to FINISH if the game ends.
                if (is_game_end) begin
                    next_state = FINISH;
                end
                
                // Transition to PAUSE if the user presses the pause button.
                if (pause_op /* pause button pressed */) begin
                    next_state = PAUSE;
                end
            end

            PAUSE: begin
                // Return to the previous "normal" state if the user press the pause button again.
                if (pause_op) begin
                    next_state = RACING;
                end
            end

            FINISH: begin
                // Press start button to restart the game from state IDLE.
                if (start_op) begin
                    next_state = IDLE;
                end
            end
        endcase
    end

    // Output the current countdown value.
    always @(posedge clk) begin
        if (rst) begin
            countdown_val <= 2'd3;
        end else begin
            if (state == COUNTDOWN) begin
                if      (countdown_cnt == 29'd100_000_000) countdown_val <= 2'd2;
                else if (countdown_cnt == 29'd200_000_000) countdown_val <= 2'd1;
                else if (countdown_cnt == 29'd300_000_000) countdown_val <= 2'd0;
                else                                       countdown_val <= countdown_val;
            end else begin
                countdown_val <= 2'd3;
            end
        end
    end

endmodule