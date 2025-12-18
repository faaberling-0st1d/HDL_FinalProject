module StateEncoder (
    input clk,
    input rst,

    input start_btn,   // Game Starting Button
    input setting_btn, // Game Setting Button
    input pause_btn,   // Game Pause Button (for state COUNTDOWN & RACING)

    input is_sync,     // Whether two FPGAs are connected or not. (先保留，不過目前改單人)
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
    // Local parameters
    localparam IDLE      = 3'd0;
    localparam SETTING   = 3'd1;
    localparam SYNC      = 3'd2;
    localparam COUNTDOWN = 3'd3;
    localparam RACE      = 3'd4;
    localparam PAUSE     = 3'd5;
    localparam FINISH    = 3'd6;

    /* [COUNTER] */
    reg [27:0] countdown_cnt, next_countdown_cnt;
    parameter SECOND = 100000000;
    parameter COUNTDOWN_TIME_LIMIT = 3 * SECOND - 1;

    /* [Sequential Circuit]
     * `state`
     */
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            countdown_cnt <= 28'd0;

        end else begin
            state <= next_state;
            countdown_cnt <= next_countdown_cnt;
        end
    end

    /* [Combinational Circuit]
     * `next_state`
     */
    always @(*) begin
        next_state = state;

        case (state)
            IDLE: begin
                if (start_op) begin
                    if (is_sync) next_state = COUNTDOWN;
                    else         next_state = SYNC;

                end else if (setting_btn) begin
                    next_state = SETTING;
                end
            end
            SETTING: begin
                if (setting_btn) begin
                    next_state = IDLE;
                end
            end
            SYNC: begin
                if (is_sync) begin
                    next_state = COUNTDOWN;
                end
            end
            COUNTDOWN: begin
                if (countdown_cnt >= COUNTDOWN_TIME_LIMIT) begin
                    next_countdown_cnt = 28'd0;
                    next_state = RACE;
                end else begin
                    next_countdown_cnt = countdown_cnt + 1;
                end

                if (is_sync) begin
                    next_countdown_cnt = 28'd0;
                    next_state = COUNTDOWN;
                end
            end
            RACE: begin
                if (is_game_end) begin
                    next_state = FINISH;
                end
                if (pause_op /* pause button pressed */) begin
                    next_state = PAUSE;
                end
            end
            PAUSE: begin
            end
            FINISH: begin
                if (start_btn) begin
                    next_state = IDLE;
                end
            end
        endcase
    end

endmodule