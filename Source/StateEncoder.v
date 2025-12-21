module StateEncoder (
    input clk,
    input rst,

    input start_btn,   // Game Starting Button
    input setting_btn, // Game Setting Button
    input pause_btn,   // Game Pause Button (for state COUNTDOWN & RACING)

    // input is_sync,     // Whether two FPGAs are connected or not. (先取消，目前改單人雙螢幕)
    input is_game_end, // Whether the racing game has ended. (遊戲結束)

    output reg [2:0] state
);
    /* [Buttons] */
    // Debounce
    wire start_db, setting_db, pause_db;
    debounce db1(.pb_debounced(start_db),   .pb(start_btn),   .clk(clk));
    debounce db2(.pb_debounced(setting_db), .pb(setting_btn), .clk(clk));
    debounce db3(.pb_debounced(pause_db),   .pb(pause_btn),   .clk(clk));
    // One-pulse
    wire start_op, setting_op, pause_op;
    onepulse op1(.signal(start_db),   .clk(clk), .op(start_op));
    onepulse op2(.signal(setting_db), .clk(clk), .op(setting_op));
    onepulse op3(.signal(pause_db),   .clk(clk), .op(pause_op));

    /* [States] */
    reg [2:0] next_state;
    reg [2:0] prev_main_state;
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
    parameter SECOND = 100000000;
    parameter COUNTDOWN_TIME_LIMIT = 3 * SECOND - 1;

    /* [Sequential Circuit]
     * `state`
     */
    // "Main" states: RACING, COUNTDOWN.
    wire is_main_state = (state == IDLE || state == RACING || state == COUNTDOWN);
    
    always @(posedge clk) begin
        if (rst) begin
            state           <= IDLE;
            prev_main_state <= IDLE;
            countdown_cnt   <= 28'd0;

        end else begin
            state           <= next_state;
            prev_main_state <= (is_main_state) ? state : prev_main_state; // Note the previous state only when the current state is the main ones.
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
                    next_countdown_cnt = 28'd0;

                // Transition to state SETTING if setting button pressed.
                end else if (setting_btn) begin
                    next_state = SETTING;
                end
            end

            SETTING: begin
                // Return to IDLE (game lobby) if the setting button is pressed again.
                if (setting_btn) begin
                    next_state = IDLE;
                end
            end

            COUNTDOWN: begin
                if (countdown_cnt >= COUNTDOWN_TIME_LIMIT) begin
                    next_countdown_cnt = 28'd0;
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
                if (pause_btn) begin
                    next_state = prev_main_state;
                end
            end

            FINISH: begin
                // Press start button to restart the game from state IDLE.
                if (start_btn) begin
                    next_state = IDLE;
                end
            end
        endcase
    end

endmodule