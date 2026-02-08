/*
 * Copyright (c) 2025 Uri Shaked
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_phsauter_vga_maze (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // Unused outputs
    assign uio_out = 0;
    assign uio_oe  = 0;
    
    // Suppress warnings
    wire _unused = &{ena, ui_in[7], ui_in[3:0], uio_in};

    // =========== VGA SIGNALS ===========
    wire hsync, vsync;
    wire [1:0] R, G, B;
    wire video_active;
    wire [9:0] pix_x, pix_y;

    assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

    hvsync_generator hvsync_gen (
        .clk(clk),
        .reset(~rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(video_active),
        .hpos(pix_x),
        .vpos(pix_y)
    );

    // =========== GAMEPAD ===========
    wire inp_up, inp_down, inp_left, inp_right;
    wire inp_a, inp_b, inp_select, inp_start;
    wire inp_x, inp_y, inp_l, inp_r, inp_present;

    gamepad_pmod_single gamepad (
        .rst_n(rst_n),
        .clk(clk),
        .pmod_data(ui_in[6]),
        .pmod_clk(ui_in[5]),
        .pmod_latch(ui_in[4]),
        .up(inp_up),
        .down(inp_down),
        .left(inp_left),
        .right(inp_right),
        .a(inp_a),
        .b(inp_b),
        .select(inp_select),
        .start(inp_start),
        .x(inp_x),
        .y(inp_y),
        .l(inp_l),
        .r(inp_r),
        .is_present(inp_present)
    );

    // =========== MAZE PARAMETERS ===========
    localparam MAZE_W = 8;
    localparam MAZE_H = 8;
    localparam CELL_SIZE = 40;  // 40x40 pixels per cell (320x320 area)
    localparam WALL_THICKNESS = 3;
    localparam GROUP_SIZE = 2;  // Fixed group size for sidewinder

    // =========== SEED ===========
    reg [7:0] lfsr;
    reg [7:0] maze_seed;

    // =========== HASH FUNCTION ===========
    // 8-bit hash for deterministic wall computation
    function [7:0] hash8;
        input [2:0] x;
        input [2:0] y;
        input [7:0] seed;
        input [7:0] salt;
        reg [7:0] pos;
        reg [7:0] h;
        reg [15:0] mult;
        begin
            pos = {y, 1'b0, x} ^ salt;
            h = seed ^ pos ^ {4'b0, pos[7:4]};
            mult = h * 8'd157;
            h = mult[7:0];
            h = h ^ {4'b0, h[7:4]};
            hash8 = h;
        end
    endfunction

    // =========== WALL COMPUTATION (Fixed-Group Sidewinder) ===========
    // East wall at (x, y):
    //   - x == 7: always (right border)
    //   - y == 0: never (top row is one corridor)
    //   - x % 2 == 1: always (group boundary)
    //   - else: never (cells within group connected)
    function has_east_wall;
        input [2:0] x;
        input [2:0] y;
        begin
            if (x >= MAZE_W - 1)
                has_east_wall = 1;      // Right border
            else if (y == 0)
                has_east_wall = 0;      // Top row corridor
            else
                has_east_wall = x[0];   // Group boundary at odd x
        end
    endfunction

    // South wall at (x, y):
    //   - y == 7: always (bottom border)
    //   - Row y+1 picks one cell per group to carve north
    //   - hash(group_idx, y+1, seed) % 2 determines which cell (0 or 1)
    function has_south_wall;
        input [2:0] x;
        input [2:0] y;
        reg [2:0] group_idx;
        reg [7:0] h;
        reg chosen_offset;
        reg [2:0] chosen_x;
        begin
            if (y >= MAZE_H - 1)
                has_south_wall = 1;     // Bottom border
            else begin
                group_idx = x[2:1];     // x / 2
                h = hash8(group_idx, y + 1, maze_seed, 8'd1);
                chosen_offset = h[0];   // 0 or 1
                chosen_x = {group_idx, chosen_offset};  // group_idx * 2 + offset
                has_south_wall = (x != chosen_x);
            end
        end
    endfunction

    // North wall = south wall of cell above
    function has_north_wall;
        input [2:0] x;
        input [2:0] y;
        begin
            if (y == 0)
                has_north_wall = 1;     // Top border
            else
                has_north_wall = has_south_wall(x, y - 1);
        end
    endfunction

    // West wall = east wall of cell to left
    function has_west_wall;
        input [2:0] x;
        input [2:0] y;
        begin
            if (x == 0)
                has_west_wall = 1;      // Left border
            else
                has_west_wall = has_east_wall(x - 1, y);
        end
    endfunction

    // =========== PIXEL WALL COMPUTATION ===========
    wire [2:0] cell_x = pix_x[9:0] / CELL_SIZE;
    wire [2:0] cell_y = pix_y[9:0] / CELL_SIZE;
    wire [5:0] in_cell_x = pix_x % CELL_SIZE;
    wire [5:0] in_cell_y = pix_y % CELL_SIZE;

    wire cur_east_wall = has_east_wall(cell_x, cell_y);
    wire cur_south_wall = has_south_wall(cell_x, cell_y);
    wire cur_north_wall = has_north_wall(cell_x, cell_y);
    wire cur_west_wall = has_west_wall(cell_x, cell_y);

    wire on_north_wall = (in_cell_y < WALL_THICKNESS) & cur_north_wall;
    wire on_south_wall = (in_cell_y >= CELL_SIZE - WALL_THICKNESS) & cur_south_wall;
    wire on_east_wall = (in_cell_x >= CELL_SIZE - WALL_THICKNESS) & cur_east_wall;
    wire on_west_wall = (in_cell_x < WALL_THICKNESS) & cur_west_wall;
    wire on_wall = on_north_wall | on_south_wall | on_east_wall | on_west_wall;

    // =========== GAME STATE ===========
    reg [2:0] player_x, player_y;
    reg [2:0] solver_r_x, solver_r_y;
    reg [1:0] solver_r_dir;
    reg [2:0] solver_l_x, solver_l_y;
    reg [1:0] solver_l_dir;
    reg solvers_active;
    reg player_won, solver_r_won, solver_l_won;

    // Generation animation state
    reg generating;
    reg [2:0] gen_row;
    reg [3:0] gen_frame_count;

    // Solver speed control
    reg [3:0] solver_speed;
    reg [3:0] solver_frame_count;
    reg single_step_mode;
    reg step_requested;

    // =========== ENTITY WALL LOOKUPS ===========
    wire player_north_wall = has_north_wall(player_x, player_y);
    wire player_south_wall = has_south_wall(player_x, player_y);
    wire player_east_wall = has_east_wall(player_x, player_y);
    wire player_west_wall = has_west_wall(player_x, player_y);

    wire solver_r_north_wall = has_north_wall(solver_r_x, solver_r_y);
    wire solver_r_south_wall = has_south_wall(solver_r_x, solver_r_y);
    wire solver_r_east_wall = has_east_wall(solver_r_x, solver_r_y);
    wire solver_r_west_wall = has_west_wall(solver_r_x, solver_r_y);

    wire solver_l_north_wall = has_north_wall(solver_l_x, solver_l_y);
    wire solver_l_south_wall = has_south_wall(solver_l_x, solver_l_y);
    wire solver_l_east_wall = has_east_wall(solver_l_x, solver_l_y);
    wire solver_l_west_wall = has_west_wall(solver_l_x, solver_l_y);

    // =========== EDGE DETECTION ===========
    reg inp_up_prev, inp_down_prev, inp_left_prev, inp_right_prev;
    reg inp_a_prev, inp_b_prev, inp_select_prev, inp_start_prev;
    reg inp_x_prev, inp_y_prev, inp_l_prev, inp_r_prev;

    wire inp_up_edge = inp_up & ~inp_up_prev;
    wire inp_down_edge = inp_down & ~inp_down_prev;
    wire inp_left_edge = inp_left & ~inp_left_prev;
    wire inp_right_edge = inp_right & ~inp_right_prev;
    wire inp_a_edge = inp_a & ~inp_a_prev;
    wire inp_b_edge = inp_b & ~inp_b_prev;
    wire inp_select_edge = inp_select & ~inp_select_prev;
    wire inp_start_edge = inp_start & ~inp_start_prev;
    wire inp_x_edge = inp_x & ~inp_x_prev;
    wire inp_y_edge = inp_y & ~inp_y_prev;
    wire inp_l_edge = inp_l & ~inp_l_prev;
    wire inp_r_edge = inp_r & ~inp_r_prev;

    // =========== PIXEL RENDERING ===========
    localparam GOAL_X = MAZE_W - 1;
    localparam GOAL_Y = MAZE_H - 1;

    wire in_maze = (pix_x < MAZE_W * CELL_SIZE) & (pix_y < MAZE_H * CELL_SIZE);
    wire row_revealed = ~generating | (cell_y <= gen_row);

    // Entity area: 16x16 centered in 40x40 cell
    wire in_entity_area = (in_cell_x >= 12) & (in_cell_x < 28) &
                          (in_cell_y >= 12) & (in_cell_y < 28);

    wire player_here = (cell_x == player_x) & (cell_y == player_y);
    wire solver_r_here = (cell_x == solver_r_x) & (cell_y == solver_r_y);
    wire solver_l_here = (cell_x == solver_l_x) & (cell_y == solver_l_y);
    wire is_goal_cell = (cell_x == GOAL_X) & (cell_y == GOAL_Y);

    wire [1:0] entity_count = {1'b0, player_here} + {1'b0, solver_r_here} + {1'b0, solver_l_here};

    wire [3:0] ent_x = in_cell_x[3:0] - 4'd12;
    wire [3:0] ent_y = in_cell_y[3:0] - 4'd12;
    wire [4:0] diag_pos = {1'b0, ent_x} + {1'b0, ent_y};

    reg [1:0] entity_r, entity_g, entity_b;

    always @(*) begin
        entity_r = 2'b00;
        entity_g = 2'b00;
        entity_b = 2'b00;

        if (in_entity_area & ~on_wall & ~generating & row_revealed) begin
            case (entity_count)
                2'd1: begin
                    if (player_here) begin
                        entity_g = 2'b11;
                    end else if (solver_r_here) begin
                        entity_r = 2'b11;
                    end else if (solver_l_here) begin
                        entity_g = 2'b11;
                        entity_b = 2'b11;
                    end
                end
                2'd2: begin
                    if (diag_pos < 5'd15) begin
                        if (player_here) begin
                            entity_g = 2'b11;
                        end else if (solver_r_here) begin
                            entity_r = 2'b11;
                        end else begin
                            entity_g = 2'b11;
                            entity_b = 2'b11;
                        end
                    end else begin
                        if (player_here & solver_r_here) begin
                            entity_r = 2'b11;
                        end else if (player_here & solver_l_here) begin
                            entity_g = 2'b11;
                            entity_b = 2'b11;
                        end else begin
                            entity_g = 2'b11;
                            entity_b = 2'b11;
                        end
                    end
                end
                2'd3: begin
                    if (diag_pos < 5'd10) begin
                        entity_g = 2'b11;
                    end else if (diag_pos < 5'd20) begin
                        entity_r = 2'b11;
                    end else begin
                        entity_g = 2'b11;
                        entity_b = 2'b11;
                    end
                end
                default: ;
            endcase
        end
    end

    wire any_entity_here = (entity_count > 0) & in_entity_area & ~on_wall & ~generating & row_revealed;
    wire draw_goal = is_goal_cell & in_entity_area & ~on_wall & ~any_entity_here & ~generating & row_revealed;

    wire is_gen_row = generating & (cell_y == gen_row);

    // Speed indicator
    wire in_speed_bar_area = (pix_x >= 10'd325) & (pix_x < 10'd355) & (pix_y >= 10'd5) & (pix_y < 10'd13);
    wire speed_bar_border = in_speed_bar_area & (
        (pix_x == 10'd325) | (pix_x == 10'd354) |
        (pix_y == 10'd5) | (pix_y == 10'd12)
    );
    wire speed_bar_inner = in_speed_bar_area & ~speed_bar_border;
    wire [4:0] speed_bar_local_x = pix_x[4:0] - 5'd6;
    wire [4:0] filled_width = (5'd16 - {1'b0, solver_speed}) * 2'd2;
    wire speed_bar_filled = (speed_bar_local_x < filled_width);

    // =========== COLOR OUTPUT ===========
    reg [1:0] r_out, g_out, b_out;

    always @(*) begin
        if (~video_active) begin
            r_out = 2'b00;
            g_out = 2'b00;
            b_out = 2'b00;
        end else if (speed_bar_border) begin
            r_out = 2'b11;
            g_out = 2'b11;
            b_out = single_step_mode ? 2'b00 : 2'b11;
        end else if (speed_bar_inner) begin
            if (speed_bar_filled) begin
                r_out = 2'b00;
                g_out = 2'b11;
                b_out = 2'b00;
            end else begin
                r_out = 2'b00;
                g_out = 2'b00;
                b_out = 2'b00;
            end
        end else if (~in_maze) begin
            r_out = 2'b00;
            g_out = 2'b00;
            b_out = 2'b00;
        end else if (~row_revealed) begin
            r_out = 2'b01;
            g_out = 2'b01;
            b_out = 2'b01;
        end else if (player_won) begin
            r_out = 2'b00;
            g_out = 2'b11;
            b_out = 2'b00;
        end else if (solver_r_won) begin
            r_out = 2'b11;
            g_out = 2'b00;
            b_out = 2'b00;
        end else if (solver_l_won) begin
            r_out = 2'b00;
            g_out = 2'b11;
            b_out = 2'b11;
        end else if (on_wall) begin
            if (is_gen_row) begin
                r_out = 2'b11;
                g_out = 2'b11;
                b_out = 2'b00;
            end else begin
                r_out = 2'b11;
                g_out = 2'b11;
                b_out = 2'b11;
            end
        end else if (any_entity_here) begin
            r_out = entity_r;
            g_out = entity_g;
            b_out = entity_b;
        end else if (draw_goal) begin
            r_out = 2'b11;
            g_out = 2'b11;
            b_out = 2'b00;
        end else begin
            if (is_gen_row) begin
                r_out = 2'b00;
                g_out = 2'b01;
                b_out = 2'b10;
            end else begin
                r_out = 2'b00;
                g_out = 2'b00;
                b_out = 2'b01;
            end
        end
    end

    assign R = r_out;
    assign G = g_out;
    assign B = b_out;

    // =========== GAME LOGIC ===========
    reg vsync_prev;
    wire vsync_edge = vsync & ~vsync_prev;

    wire solver_tick_normal = (solver_frame_count == 0) & vsync_edge;
    wire solver_tick = solvers_active & ~generating & ~player_won & ~solver_r_won & ~solver_l_won & (
        (~single_step_mode & solver_tick_normal) |
        (single_step_mode & step_requested)
    );

    always @(posedge clk) begin
        if (~rst_n) begin
            lfsr <= 8'hA5;
            maze_seed <= 8'hA5;
            player_x <= 0;
            player_y <= 0;
            solver_r_x <= 0;
            solver_r_y <= 0;
            solver_r_dir <= 2'd1;
            solver_l_x <= 0;
            solver_l_y <= 0;
            solver_l_dir <= 2'd1;
            solvers_active <= 0;
            player_won <= 0;
            solver_r_won <= 0;
            solver_l_won <= 0;
            generating <= 1;
            gen_row <= 0;
            gen_frame_count <= 0;
            solver_frame_count <= 0;
            solver_speed <= 4'd4;
            single_step_mode <= 0;
            step_requested <= 0;
            vsync_prev <= 0;
            inp_up_prev <= 0;
            inp_down_prev <= 0;
            inp_left_prev <= 0;
            inp_right_prev <= 0;
            inp_a_prev <= 0;
            inp_b_prev <= 0;
            inp_select_prev <= 0;
            inp_start_prev <= 0;
            inp_x_prev <= 0;
            inp_y_prev <= 0;
            inp_l_prev <= 0;
            inp_r_prev <= 0;
        end else begin
            // Edge detection
            vsync_prev <= vsync;
            inp_up_prev <= inp_up;
            inp_down_prev <= inp_down;
            inp_left_prev <= inp_left;
            inp_right_prev <= inp_right;
            inp_a_prev <= inp_a;
            inp_b_prev <= inp_b;
            inp_select_prev <= inp_select;
            inp_start_prev <= inp_start;
            inp_x_prev <= inp_x;
            inp_y_prev <= inp_y;
            inp_l_prev <= inp_l;
            inp_r_prev <= inp_r;

            if (single_step_mode & step_requested & solvers_active) begin
                step_requested <= 0;
            end

            // Frame timing
            if (vsync_edge) begin
                if (solver_frame_count == 0)
                    solver_frame_count <= solver_speed - 1;
                else
                    solver_frame_count <= solver_frame_count - 1;

                // LFSR for randomization
                lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};

                // Generation animation (just visual reveal, maze is computed on-the-fly)
                if (generating) begin
                    if (gen_frame_count < 3) begin
                        gen_frame_count <= gen_frame_count + 1;
                    end else begin
                        gen_frame_count <= 0;
                        if (gen_row < MAZE_H - 1) begin
                            gen_row <= gen_row + 1;
                        end else begin
                            generating <= 0;
                        end
                    end
                end
            end

            // SELECT: Generate new maze
            if (inp_select_edge) begin
                maze_seed <= lfsr;
                generating <= 1;
                gen_row <= 0;
                gen_frame_count <= 0;
                player_x <= 0;
                player_y <= 0;
                solver_r_x <= 0;
                solver_r_y <= 0;
                solver_r_dir <= 2'd1;
                solver_l_x <= 0;
                solver_l_y <= 0;
                solver_l_dir <= 2'd1;
                solvers_active <= 0;
                player_won <= 0;
                solver_r_won <= 0;
                solver_l_won <= 0;
                single_step_mode <= 0;
                step_requested <= 0;
            end

            // START: Skip generation animation
            if (inp_start_edge & generating) begin
                generating <= 0;
                gen_row <= MAZE_H - 1;
            end

            // A: Start/stop solvers
            if (inp_a_edge & ~player_won & ~solver_r_won & ~solver_l_won & ~generating) begin
                solvers_active <= ~solvers_active;
            end

            // B: Reset positions
            if (inp_b_edge & ~generating) begin
                player_x <= 0;
                player_y <= 0;
                solver_r_x <= 0;
                solver_r_y <= 0;
                solver_r_dir <= 2'd1;
                solver_l_x <= 0;
                solver_l_y <= 0;
                solver_l_dir <= 2'd1;
                player_won <= 0;
                solver_r_won <= 0;
                solver_l_won <= 0;
                solvers_active <= 0;
            end

            // X: Toggle single-step mode
            if (inp_x_edge) begin
                single_step_mode <= ~single_step_mode;
                step_requested <= 0;
            end

            // Y: Request step
            if (inp_y_edge & single_step_mode & solvers_active & ~player_won & ~solver_r_won & ~solver_l_won & ~generating) begin
                step_requested <= 1;
            end

            // L: Slow down
            if (inp_l_edge & solver_speed < 4'd15) begin
                solver_speed <= solver_speed + 1;
            end

            // R: Speed up
            if (inp_r_edge & solver_speed > 4'd1) begin
                solver_speed <= solver_speed - 1;
            end

            // Player movement
            if (~player_won & ~solver_r_won & ~solver_l_won & ~generating) begin
                if (inp_up_edge & ~player_north_wall & player_y > 0)
                    player_y <= player_y - 1;
                if (inp_down_edge & ~player_south_wall & player_y < MAZE_H - 1)
                    player_y <= player_y + 1;
                if (inp_left_edge & ~player_west_wall & player_x > 0)
                    player_x <= player_x - 1;
                if (inp_right_edge & ~player_east_wall & player_x < MAZE_W - 1)
                    player_x <= player_x + 1;
            end

            // Right-hand wall follower
            if (solver_tick) begin
                case (solver_r_dir)
                    2'd0: begin // North
                        if (~solver_r_east_wall) begin
                            solver_r_x <= solver_r_x + 1;
                            solver_r_dir <= 2'd1;
                        end else if (~solver_r_north_wall) begin
                            solver_r_y <= solver_r_y - 1;
                        end else if (~solver_r_west_wall) begin
                            solver_r_x <= solver_r_x - 1;
                            solver_r_dir <= 2'd3;
                        end else begin
                            solver_r_dir <= 2'd2;
                        end
                    end
                    2'd1: begin // East
                        if (~solver_r_south_wall) begin
                            solver_r_y <= solver_r_y + 1;
                            solver_r_dir <= 2'd2;
                        end else if (~solver_r_east_wall) begin
                            solver_r_x <= solver_r_x + 1;
                        end else if (~solver_r_north_wall) begin
                            solver_r_y <= solver_r_y - 1;
                            solver_r_dir <= 2'd0;
                        end else begin
                            solver_r_dir <= 2'd3;
                        end
                    end
                    2'd2: begin // South
                        if (~solver_r_west_wall) begin
                            solver_r_x <= solver_r_x - 1;
                            solver_r_dir <= 2'd3;
                        end else if (~solver_r_south_wall) begin
                            solver_r_y <= solver_r_y + 1;
                        end else if (~solver_r_east_wall) begin
                            solver_r_x <= solver_r_x + 1;
                            solver_r_dir <= 2'd1;
                        end else begin
                            solver_r_dir <= 2'd0;
                        end
                    end
                    2'd3: begin // West
                        if (~solver_r_north_wall) begin
                            solver_r_y <= solver_r_y - 1;
                            solver_r_dir <= 2'd0;
                        end else if (~solver_r_west_wall) begin
                            solver_r_x <= solver_r_x - 1;
                        end else if (~solver_r_south_wall) begin
                            solver_r_y <= solver_r_y + 1;
                            solver_r_dir <= 2'd2;
                        end else begin
                            solver_r_dir <= 2'd1;
                        end
                    end
                endcase
            end

            // Left-hand wall follower
            if (solver_tick) begin
                case (solver_l_dir)
                    2'd0: begin // North
                        if (~solver_l_west_wall) begin
                            solver_l_x <= solver_l_x - 1;
                            solver_l_dir <= 2'd3;
                        end else if (~solver_l_north_wall) begin
                            solver_l_y <= solver_l_y - 1;
                        end else if (~solver_l_east_wall) begin
                            solver_l_x <= solver_l_x + 1;
                            solver_l_dir <= 2'd1;
                        end else begin
                            solver_l_dir <= 2'd2;
                        end
                    end
                    2'd1: begin // East
                        if (~solver_l_north_wall) begin
                            solver_l_y <= solver_l_y - 1;
                            solver_l_dir <= 2'd0;
                        end else if (~solver_l_east_wall) begin
                            solver_l_x <= solver_l_x + 1;
                        end else if (~solver_l_south_wall) begin
                            solver_l_y <= solver_l_y + 1;
                            solver_l_dir <= 2'd2;
                        end else begin
                            solver_l_dir <= 2'd3;
                        end
                    end
                    2'd2: begin // South
                        if (~solver_l_east_wall) begin
                            solver_l_x <= solver_l_x + 1;
                            solver_l_dir <= 2'd1;
                        end else if (~solver_l_south_wall) begin
                            solver_l_y <= solver_l_y + 1;
                        end else if (~solver_l_west_wall) begin
                            solver_l_x <= solver_l_x - 1;
                            solver_l_dir <= 2'd3;
                        end else begin
                            solver_l_dir <= 2'd0;
                        end
                    end
                    2'd3: begin // West
                        if (~solver_l_south_wall) begin
                            solver_l_y <= solver_l_y + 1;
                            solver_l_dir <= 2'd2;
                        end else if (~solver_l_west_wall) begin
                            solver_l_x <= solver_l_x - 1;
                        end else if (~solver_l_north_wall) begin
                            solver_l_y <= solver_l_y - 1;
                            solver_l_dir <= 2'd0;
                        end else begin
                            solver_l_dir <= 2'd1;
                        end
                    end
                endcase
            end

            // Win detection
            if (~generating) begin
                if (player_x == GOAL_X && player_y == GOAL_Y && ~player_won && ~solver_r_won && ~solver_l_won)
                    player_won <= 1;
                if (solver_r_x == GOAL_X && solver_r_y == GOAL_Y && solvers_active && ~player_won && ~solver_r_won && ~solver_l_won)
                    solver_r_won <= 1;
                if (solver_l_x == GOAL_X && solver_l_y == GOAL_Y && solvers_active && ~player_won && ~solver_r_won && ~solver_l_won)
                    solver_l_won <= 1;
            end
        end
    end

endmodule



/*
 * Copyright (c) 2025 Pat Deegan, https://psychogenic.com
 * SPDX-License-Identifier: Apache-2.0
 * Version: 1.0.1
 *
 * Interfacing code for the Gamepad Pmod from Psycogenic Technologies,
 * designed for Tiny Tapeout.
 *
 * There are two high-level modules that most users will be interested in:
 * - gamepad_pmod_single: for a single controller;
 * - gamepad_pmod_dual: for two controllers.
 * 
 * There are also two lower-level modules that you can use if you want to
 * handle the interfacing yourself:
 * - gamepad_pmod_driver: interfaces with the Pmod and provides the raw data;
 * - gamepad_pmod_decoder: decodes the raw data into button states.
 *
 * The docs, schematics, PCB files, and firmware code for the Gamepad Pmod
 * are available at https://github.com/psychogenic/gamepad-pmod.
 */

/**
 * gamepad_pmod_driver -- Serial interface for the Gamepad Pmod.
 *
 * This module reads raw data from the Gamepad Pmod *serially*
 * and stores it in a shift register. When the latch signal is received, 
 * the data is transferred into `data_reg` for further processing.
 *
 * Functionality:
 *   - Synchronizes the `pmod_data`, `pmod_clk`, and `pmod_latch` signals 
 *     to the system clock domain.
 *   - Captures serial data on each falling edge of `pmod_clk`.
 *   - Transfers the shifted data into `data_reg` when `pmod_latch` goes low.
 *
 * Parameters:
 *   - `BIT_WIDTH`: Defines the width of `data_reg` (default: 24 bits).
 *
 * Inputs:
 *   - `rst_n`: Active-low reset.
 *   - `clk`: System clock.
 *   - `pmod_data`: Serial data input from the Pmod.
 *   - `pmod_clk`: Serial clock from the Pmod.
 *   - `pmod_latch`: Latch signal indicating the end of data transmission.
 *
 * Outputs:
 *   - `data_reg`: Captured parallel data after shifting is complete.
 */
module gamepad_pmod_driver #(
    parameter BIT_WIDTH = 24
) (
    input wire rst_n,
    input wire clk,
    input wire pmod_data,
    input wire pmod_clk,
    input wire pmod_latch,
    output reg [BIT_WIDTH-1:0] data_reg
);

  reg pmod_clk_prev;
  reg pmod_latch_prev;
  reg [BIT_WIDTH-1:0] shift_reg;

  // Sync Pmod signals to the clk domain:
  reg [1:0] pmod_data_sync;
  reg [1:0] pmod_clk_sync;
  reg [1:0] pmod_latch_sync;

  always @(posedge clk) begin
    if (~rst_n) begin
      pmod_data_sync  <= 2'b0;
      pmod_clk_sync   <= 2'b0;
      pmod_latch_sync <= 2'b0;
    end else begin
      pmod_data_sync  <= {pmod_data_sync[0], pmod_data};
      pmod_clk_sync   <= {pmod_clk_sync[0], pmod_clk};
      pmod_latch_sync <= {pmod_latch_sync[0], pmod_latch};
    end
  end

  always @(posedge clk) begin
    if (~rst_n) begin
      /* Initialize data and shift registers to all 1s so they're detected as "not present".
       * This accounts for cases where we have:
       *  - setup for 2 controllers;
       *  - only a single controller is connected; and
       *  - the driver in those cases only sends bits for a single controller.
       */
      data_reg <= {BIT_WIDTH{1'b1}};
      shift_reg <= {BIT_WIDTH{1'b1}};
      pmod_clk_prev <= 1'b0;
      pmod_latch_prev <= 1'b0;
    end else begin
      pmod_clk_prev   <= pmod_clk_sync[1];
      pmod_latch_prev <= pmod_latch_sync[1];

      // Capture data on rising edge of pmod_latch:
      if (pmod_latch_sync[1] & ~pmod_latch_prev) begin
        data_reg <= shift_reg;
      end

      // Sample data on rising edge of pmod_clk:
      if (pmod_clk_sync[1] & ~pmod_clk_prev) begin
        shift_reg <= {shift_reg[BIT_WIDTH-2:0], pmod_data_sync[1]};
      end
    end
  end

endmodule


/**
 * gamepad_pmod_decoder -- Decodes raw data from the Gamepad Pmod.
 *
 * This module takes a 12-bit parallel data register (`data_reg`) 
 * and decodes it into individual button states. It also determines
 * whether a controller is connected.
 *
 * Functionality:
 *   - If `data_reg` contains all `1's` (`0xFFF`), it indicates that no controller is connected.
 *   - Otherwise, it extracts individual button states from `data_reg`.
 *
 * Inputs:
 *   - `data_reg [11:0]`: Captured button state data from the gamepad.
 *
 * Outputs:
 *   - `b, y, select, start, up, down, left, right, a, x, l, r`: Individual button states (`1` = pressed, `0` = released).
 *   - `is_present`: Indicates whether a controller is connected (`1` = connected, `0` = not connected).
 */
module gamepad_pmod_decoder (
    input wire [11:0] data_reg,
    output wire b,
    output wire y,
    output wire select,
    output wire start,
    output wire up,
    output wire down,
    output wire left,
    output wire right,
    output wire a,
    output wire x,
    output wire l,
    output wire r,
    output wire is_present
);

  // When the controller is not connected, the data register will be all 1's
  wire reg_empty = (data_reg == 12'hfff);
  assign is_present = reg_empty ? 0 : 1'b1;
  assign {b, y, select, start, up, down, left, right, a, x, l, r} = reg_empty ? 0 : data_reg;

endmodule


/**
 * gamepad_pmod_single -- Main interface for a single Gamepad Pmod controller.
 * 
 * This module provides button states for a **single controller**, reducing 
 * resource usage (fewer flip-flops) compared to a dual-controller version.
 * 
 * Inputs:
 *   - `pmod_data`, `pmod_clk`, and `pmod_latch` are the signals from the PMOD interface.
 * 
 * Outputs:
 *   - Each button's state is provided as a single-bit wire (e.g., `start`, `up`, etc.).
 *   - `is_present` indicates whether the controller is connected (`1` = connected, `0` = not detected).
 */
module gamepad_pmod_single (
    input wire rst_n,
    input wire clk,
    input wire pmod_data,
    input wire pmod_clk,
    input wire pmod_latch,

    output wire b,
    output wire y,
    output wire select,
    output wire start,
    output wire up,
    output wire down,
    output wire left,
    output wire right,
    output wire a,
    output wire x,
    output wire l,
    output wire r,
    output wire is_present
);

  wire [11:0] gamepad_pmod_data;

  gamepad_pmod_driver #(
      .BIT_WIDTH(12)
  ) driver (
      .rst_n(rst_n),
      .clk(clk),
      .pmod_data(pmod_data),
      .pmod_clk(pmod_clk),
      .pmod_latch(pmod_latch),
      .data_reg(gamepad_pmod_data)
  );

  gamepad_pmod_decoder decoder (
      .data_reg(gamepad_pmod_data),
      .b(b),
      .y(y),
      .select(select),
      .start(start),
      .up(up),
      .down(down),
      .left(left),
      .right(right),
      .a(a),
      .x(x),
      .l(l),
      .r(r),
      .is_present(is_present)
  );

endmodule


/**
 * gamepad_pmod_dual -- Main interface for the Pmod gamepad.
 * This module provides button states for two controllers using
 * 2-bit vectors for each button (e.g., start[1:0], up[1:0], etc.).
 * 
 * Each button state is represented as a 2-bit vector:
 *   - Index 0 corresponds to the first controller (e.g., up[0], y[0], etc.).
 *   - Index 1 corresponds to the second controller (e.g., up[1], y[1], etc.).
 *
 * The `is_present` signal indicates whether a controller is connected:
 *   - `is_present[0] == 1` when the first controller is connected.
 *   - `is_present[1] == 1` when the second controller is connected.
 *
 * Inputs:
 *   - `pmod_data`, `pmod_clk`, and `pmod_latch` are the 3 wires coming from the Pmod interface.
 *
 * Outputs:
 *   - Button state vectors for each controller.
 *   - Presence detection via `is_present`.
 */
module gamepad_pmod_dual (
    input wire rst_n,
    input wire clk,
    input wire pmod_data,
    input wire pmod_clk,
    input wire pmod_latch,

    output wire [1:0] b,
    output wire [1:0] y,
    output wire [1:0] select,
    output wire [1:0] start,
    output wire [1:0] up,
    output wire [1:0] down,
    output wire [1:0] left,
    output wire [1:0] right,
    output wire [1:0] a,
    output wire [1:0] x,
    output wire [1:0] l,
    output wire [1:0] r,
    output wire [1:0] is_present
);

  wire [23:0] gamepad_pmod_data;

  gamepad_pmod_driver driver (
      .rst_n(rst_n),
      .clk(clk),
      .pmod_data(pmod_data),
      .pmod_clk(pmod_clk),
      .pmod_latch(pmod_latch),
      .data_reg(gamepad_pmod_data)
  );

  gamepad_pmod_decoder decoder1 (
      .data_reg(gamepad_pmod_data[11:0]),
      .b(b[0]),
      .y(y[0]),
      .select(select[0]),
      .start(start[0]),
      .up(up[0]),
      .down(down[0]),
      .left(left[0]),
      .right(right[0]),
      .a(a[0]),
      .x(x[0]),
      .l(l[0]),
      .r(r[0]),
      .is_present(is_present[0])
  );

  gamepad_pmod_decoder decoder2 (
      .data_reg(gamepad_pmod_data[23:12]),
      .b(b[1]),
      .y(y[1]),
      .select(select[1]),
      .start(start[1]),
      .up(up[1]),
      .down(down[1]),
      .left(left[1]),
      .right(right[1]),
      .a(a[1]),
      .x(x[1]),
      .l(l[1]),
      .r(r[1]),
      .is_present(is_present[1])
  );

endmodule
