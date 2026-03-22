`default_nettype none

/*
 * Main control/gameplay block.
 *
 * Controls:
 * - D-pad: move the player during play.
 * - A: start/stop both solvers.
 * - B: reset player and solver positions.
 * - SELECT: generate a new maze from the current LFSR seed.
 * - START: while generating, switch to fast generation mode.
 * - X: toggle solver single-step mode.
 * - Y: advance one solver step when single-step mode is enabled.
 * - L: slow solvers down.
 * - R: speed solvers up.
 */

module maze_game_core #(
    parameter integer MAZE_W = 8,
    parameter integer MAZE_H = 8,
    parameter integer SEED_W = 16,
    parameter integer SOLVER_SPEED_W = 4,
    parameter integer XW = $clog2(MAZE_W),
    parameter integer YW = $clog2(MAZE_H),
    parameter integer EAST_BITS = MAZE_H * (MAZE_W - 1),
    parameter integer SOUTH_BITS = (MAZE_H - 1) * MAZE_W
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  frame_tick,
    input  wire                  inp_up,
    input  wire                  inp_down,
    input  wire                  inp_left,
    input  wire                  inp_right,
    input  wire                  inp_a,
    input  wire                  inp_b,
    input  wire                  inp_select,
    input  wire                  inp_start,
    input  wire                  inp_x,
    input  wire                  inp_y,
    input  wire                  inp_l,
    input  wire                  inp_r,
    output wire [EAST_BITS-1:0]  east_walls_flat,
    output wire [SOUTH_BITS-1:0] south_walls_flat,
    output reg  [XW-1:0]         player_x,
    output reg  [YW-1:0]         player_y,
    output reg  [XW-1:0]         solver_r_x,
    output reg  [YW-1:0]         solver_r_y,
    output reg  [1:0]            solver_r_dir,
    output reg  [XW-1:0]         solver_l_x,
    output reg  [YW-1:0]         solver_l_y,
    output reg  [1:0]            solver_l_dir,
    output reg                   solvers_active,
    output reg                   player_won,
    output reg                   solver_r_won,
    output reg                   solver_l_won,
    output reg  [SOLVER_SPEED_W-1:0] solver_speed,
    output reg                   single_step_mode,
    output wire                  gen_busy,
    output wire [YW-1:0]         gen_row_vis,
    output wire [XW-1:0]         gen_col_vis,
    output wire [2:0]            gen_phase_vis
);

    localparam [2:0] C_RESET = 3'd0;
    localparam [2:0] C_GEN_START = 3'd1;
    localparam [2:0] C_GEN_RUN = 3'd2;
    localparam [2:0] C_PLAY = 3'd3;
    localparam [2:0] C_WIN = 3'd4;
    localparam [XW-1:0] GOAL_X = MAZE_W[XW-1:0] - 1'b1;
    localparam [YW-1:0] GOAL_Y = MAZE_H[YW-1:0] - 1'b1;

    reg [2:0] core_state;
    reg [SEED_W-1:0] lfsr;
    reg [SEED_W-1:0] maze_seed;
    reg [SOLVER_SPEED_W-1:0] solver_frame_count;
    reg step_requested;
    reg gen_start;
    reg gen_fast_mode;

    wire up_edge;
    wire down_edge;
    wire left_edge;
    wire right_edge;
    wire a_edge;
    wire b_edge;
    wire select_edge;
    wire start_edge;
    wire x_edge;
    wire y_edge;
    wire l_edge;
    wire r_edge;

    wire clear_all;
    wire east_we;
    wire [XW-1:0] east_x;
    wire [YW-1:0] east_y;
    wire east_val;
    wire south_we;
    wire [XW-1:0] south_x;
    wire [YW-1:0] south_y;
    wire south_val;
    wire gen_done;

    wire player_north_wall;
    wire player_south_wall;
    wire player_east_wall;
    wire player_west_wall;
    wire solver_r_north_wall;
    wire solver_r_south_wall;
    wire solver_r_east_wall;
    wire solver_r_west_wall;
    wire solver_l_north_wall;
    wire solver_l_south_wall;
    wire solver_l_east_wall;
    wire solver_l_west_wall;

    wire [XW-1:0] solver_r_next_x;
    wire [YW-1:0] solver_r_next_y;
    wire [1:0] solver_r_next_dir;
    wire [XW-1:0] solver_l_next_x;
    wire [YW-1:0] solver_l_next_y;
    wire [1:0] solver_l_next_dir;

    wire solver_tick_normal = frame_tick && (solver_frame_count == 0);
    wire solver_tick = (core_state == C_PLAY) && solvers_active && ~player_won && ~solver_r_won && ~solver_l_won &&
                       ((~single_step_mode && solver_tick_normal) || (single_step_mode && step_requested));

    function [SEED_W-1:0] lfsr_step;
        input [SEED_W-1:0] value;
        begin
            lfsr_step = {value[SEED_W-2:0], value[SEED_W-1] ^ value[SEED_W-3] ^ value[SEED_W-4] ^ value[SEED_W-6]};
        end
    endfunction

    maze_input_edges edges (
        .clk(clk),
        .rst_n(rst_n),
        .inp_up(inp_up),
        .inp_down(inp_down),
        .inp_left(inp_left),
        .inp_right(inp_right),
        .inp_a(inp_a),
        .inp_b(inp_b),
        .inp_select(inp_select),
        .inp_start(inp_start),
        .inp_x(inp_x),
        .inp_y(inp_y),
        .inp_l(inp_l),
        .inp_r(inp_r),
        .up_edge(up_edge),
        .down_edge(down_edge),
        .left_edge(left_edge),
        .right_edge(right_edge),
        .a_edge(a_edge),
        .b_edge(b_edge),
        .select_edge(select_edge),
        .start_edge(start_edge),
        .x_edge(x_edge),
        .y_edge(y_edge),
        .l_edge(l_edge),
        .r_edge(r_edge)
    );

    maze_map #(
        .MAZE_W(MAZE_W),
        .MAZE_H(MAZE_H)
    ) map (
        .clk(clk),
        .rst_n(rst_n),
        .clear_all(clear_all),
        .east_we(east_we),
        .east_x(east_x),
        .east_y(east_y),
        .east_val(east_val),
        .south_we(south_we),
        .south_x(south_x),
        .south_y(south_y),
        .south_val(south_val),
        .east_walls_flat(east_walls_flat),
        .south_walls_flat(south_walls_flat)
    );

    maze_gen_eller #(
        .MAZE_W(MAZE_W),
        .MAZE_H(MAZE_H),
        .SEED_W(SEED_W)
    ) generator (
        .clk(clk),
        .rst_n(rst_n),
        .start(gen_start),
        .step_en(frame_tick),
        .fast_mode(gen_fast_mode),
        .seed(maze_seed),
        .busy(gen_busy),
        .done(gen_done),
        .vis_row(gen_row_vis),
        .vis_col(gen_col_vis),
        .vis_phase(gen_phase_vis),
        .clear_all(clear_all),
        .east_we(east_we),
        .east_x(east_x),
        .east_y(east_y),
        .east_val(east_val),
        .south_we(south_we),
        .south_x(south_x),
        .south_y(south_y),
        .south_val(south_val)
    );

    maze_wall_query #(
        .MAZE_W(MAZE_W),
        .MAZE_H(MAZE_H)
    ) player_walls (
        .cell_x(player_x),
        .cell_y(player_y),
        .east_walls_flat(east_walls_flat),
        .south_walls_flat(south_walls_flat),
        .north_wall(player_north_wall),
        .south_wall(player_south_wall),
        .east_wall(player_east_wall),
        .west_wall(player_west_wall)
    );

    maze_wall_query #(
        .MAZE_W(MAZE_W),
        .MAZE_H(MAZE_H)
    ) solver_r_walls (
        .cell_x(solver_r_x),
        .cell_y(solver_r_y),
        .east_walls_flat(east_walls_flat),
        .south_walls_flat(south_walls_flat),
        .north_wall(solver_r_north_wall),
        .south_wall(solver_r_south_wall),
        .east_wall(solver_r_east_wall),
        .west_wall(solver_r_west_wall)
    );

    maze_wall_query #(
        .MAZE_W(MAZE_W),
        .MAZE_H(MAZE_H)
    ) solver_l_walls (
        .cell_x(solver_l_x),
        .cell_y(solver_l_y),
        .east_walls_flat(east_walls_flat),
        .south_walls_flat(south_walls_flat),
        .north_wall(solver_l_north_wall),
        .south_wall(solver_l_south_wall),
        .east_wall(solver_l_east_wall),
        .west_wall(solver_l_west_wall)
    );

    maze_solver_hand #(
        .MAZE_W(MAZE_W),
        .MAZE_H(MAZE_H),
        .RIGHT_HAND(1)
    ) solver_r (
        .cur_x(solver_r_x),
        .cur_y(solver_r_y),
        .cur_dir(solver_r_dir),
        .north_wall(solver_r_north_wall),
        .south_wall(solver_r_south_wall),
        .east_wall(solver_r_east_wall),
        .west_wall(solver_r_west_wall),
        .next_x(solver_r_next_x),
        .next_y(solver_r_next_y),
        .next_dir(solver_r_next_dir)
    );

    maze_solver_hand #(
        .MAZE_W(MAZE_W),
        .MAZE_H(MAZE_H),
        .RIGHT_HAND(0)
    ) solver_l (
        .cur_x(solver_l_x),
        .cur_y(solver_l_y),
        .cur_dir(solver_l_dir),
        .north_wall(solver_l_north_wall),
        .south_wall(solver_l_south_wall),
        .east_wall(solver_l_east_wall),
        .west_wall(solver_l_west_wall),
        .next_x(solver_l_next_x),
        .next_y(solver_l_next_y),
        .next_dir(solver_l_next_dir)
    );

    always @(posedge clk) begin
        if (~rst_n) begin
            core_state <= C_RESET;
            lfsr <= {{(SEED_W-8){1'b0}}, 8'hA5};
            maze_seed <= {{(SEED_W-8){1'b0}}, 8'hA5};
            player_x <= {XW{1'b0}};
            player_y <= {YW{1'b0}};
            solver_r_x <= {XW{1'b0}};
            solver_r_y <= {YW{1'b0}};
            solver_r_dir <= 2'd1;
            solver_l_x <= {XW{1'b0}};
            solver_l_y <= {YW{1'b0}};
            solver_l_dir <= 2'd1;
            solvers_active <= 1'b0;
            player_won <= 1'b0;
            solver_r_won <= 1'b0;
            solver_l_won <= 1'b0;
            solver_speed <= 4'd4;
            solver_frame_count <= 4'd0;
            single_step_mode <= 1'b0;
            step_requested <= 1'b0;
            gen_start <= 1'b0;
            gen_fast_mode <= 1'b0;
        end else begin
            gen_start <= 1'b0;

            if (frame_tick)
                lfsr <= lfsr_step(lfsr);

            if ((core_state == C_PLAY) && frame_tick) begin
                if (solver_frame_count == 0)
                    solver_frame_count <= solver_speed - 1'b1;
                else
                    solver_frame_count <= solver_frame_count - 1'b1;
            end

            if (solver_tick) begin
                solver_r_x <= solver_r_next_x;
                solver_r_y <= solver_r_next_y;
                solver_r_dir <= solver_r_next_dir;
                solver_l_x <= solver_l_next_x;
                solver_l_y <= solver_l_next_y;
                solver_l_dir <= solver_l_next_dir;
                if (single_step_mode)
                    step_requested <= 1'b0;
            end

            case (core_state)
                C_RESET: begin
                    player_x <= {XW{1'b0}};
                    player_y <= {YW{1'b0}};
                    solver_r_x <= {XW{1'b0}};
                    solver_r_y <= {YW{1'b0}};
                    solver_r_dir <= 2'd1;
                    solver_l_x <= {XW{1'b0}};
                    solver_l_y <= {YW{1'b0}};
                    solver_l_dir <= 2'd1;
                    solvers_active <= 1'b0;
                    player_won <= 1'b0;
                    solver_r_won <= 1'b0;
                    solver_l_won <= 1'b0;
                    single_step_mode <= 1'b0;
                    step_requested <= 1'b0;
                    gen_fast_mode <= 1'b0;
                    core_state <= C_GEN_START;
                end

                C_GEN_START: begin
                    gen_start <= 1'b1;
                    gen_fast_mode <= 1'b0;
                    player_x <= {XW{1'b0}};
                    player_y <= {YW{1'b0}};
                    solver_r_x <= {XW{1'b0}};
                    solver_r_y <= {YW{1'b0}};
                    solver_r_dir <= 2'd1;
                    solver_l_x <= {XW{1'b0}};
                    solver_l_y <= {YW{1'b0}};
                    solver_l_dir <= 2'd1;
                    solvers_active <= 1'b0;
                    player_won <= 1'b0;
                    solver_r_won <= 1'b0;
                    solver_l_won <= 1'b0;
                    step_requested <= 1'b0;
                    solver_frame_count <= solver_speed - 1'b1;
                    core_state <= C_GEN_RUN;
                end

                C_GEN_RUN: begin
                    if (select_edge) begin
                        maze_seed <= lfsr;
                        core_state <= C_GEN_START;
                    end else begin
                        if (start_edge)
                            gen_fast_mode <= 1'b1;
                        if (gen_done) begin
                            gen_fast_mode <= 1'b0;
                            core_state <= C_PLAY;
                        end
                    end
                end

                C_PLAY: begin
                    if (select_edge) begin
                        maze_seed <= lfsr;
                        core_state <= C_GEN_START;
                    end else begin
                        if (b_edge) begin
                            player_x <= {XW{1'b0}};
                            player_y <= {YW{1'b0}};
                            solver_r_x <= {XW{1'b0}};
                            solver_r_y <= {YW{1'b0}};
                            solver_r_dir <= 2'd1;
                            solver_l_x <= {XW{1'b0}};
                            solver_l_y <= {YW{1'b0}};
                            solver_l_dir <= 2'd1;
                            player_won <= 1'b0;
                            solver_r_won <= 1'b0;
                            solver_l_won <= 1'b0;
                            solvers_active <= 1'b0;
                            step_requested <= 1'b0;
                        end

                        if (a_edge && ~player_won && ~solver_r_won && ~solver_l_won)
                            solvers_active <= ~solvers_active;

                        if (x_edge) begin
                            single_step_mode <= ~single_step_mode;
                            step_requested <= 1'b0;
                        end

                        if (y_edge && single_step_mode && solvers_active && ~player_won && ~solver_r_won && ~solver_l_won)
                            step_requested <= 1'b1;

                        if (l_edge && (solver_speed < 4'd15))
                            solver_speed <= solver_speed + 1'b1;

                        if (r_edge && (solver_speed > 4'd1))
                            solver_speed <= solver_speed - 1'b1;

                        if (~player_won && ~solver_r_won && ~solver_l_won) begin
                            if (up_edge && ~player_north_wall && (player_y > 0))
                                player_y <= player_y - 1'b1;
                            if (down_edge && ~player_south_wall && (player_y < GOAL_Y))
                                player_y <= player_y + 1'b1;
                            if (left_edge && ~player_west_wall && (player_x > 0))
                                player_x <= player_x - 1'b1;
                            if (right_edge && ~player_east_wall && (player_x < GOAL_X))
                                player_x <= player_x + 1'b1;
                        end

                        if ((player_x == GOAL_X) && (player_y == GOAL_Y) && ~player_won && ~solver_r_won && ~solver_l_won) begin
                            player_won <= 1'b1;
                            solvers_active <= 1'b0;
                            core_state <= C_WIN;
                        end else if ((solver_r_x == GOAL_X) && (solver_r_y == GOAL_Y) && solvers_active && ~player_won && ~solver_r_won && ~solver_l_won) begin
                            solver_r_won <= 1'b1;
                            solvers_active <= 1'b0;
                            core_state <= C_WIN;
                        end else if ((solver_l_x == GOAL_X) && (solver_l_y == GOAL_Y) && solvers_active && ~player_won && ~solver_r_won && ~solver_l_won) begin
                            solver_l_won <= 1'b1;
                            solvers_active <= 1'b0;
                            core_state <= C_WIN;
                        end
                    end
                end

                C_WIN: begin
                    if (select_edge) begin
                        maze_seed <= lfsr;
                        core_state <= C_GEN_START;
                    end else if (b_edge) begin
                        player_x <= {XW{1'b0}};
                        player_y <= {YW{1'b0}};
                        solver_r_x <= {XW{1'b0}};
                        solver_r_y <= {YW{1'b0}};
                        solver_r_dir <= 2'd1;
                        solver_l_x <= {XW{1'b0}};
                        solver_l_y <= {YW{1'b0}};
                        solver_l_dir <= 2'd1;
                        player_won <= 1'b0;
                        solver_r_won <= 1'b0;
                        solver_l_won <= 1'b0;
                        solvers_active <= 1'b0;
                        step_requested <= 1'b0;
                        core_state <= C_PLAY;
                    end
                end

                default: begin
                    core_state <= C_RESET;
                end
            endcase
        end
    end

endmodule
