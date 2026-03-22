`default_nettype none

module maze_video #(
    parameter integer MAZE_W = 8,
    parameter integer MAZE_H = 8,
    parameter integer CELL_SHIFT = 5,
    parameter integer XW = $clog2(MAZE_W),
    parameter integer YW = $clog2(MAZE_H),
    parameter integer EAST_BITS = MAZE_H * (MAZE_W - 1),
    parameter integer SOUTH_BITS = (MAZE_H - 1) * MAZE_W,
    parameter integer CELL_SIZE = (1 << CELL_SHIFT),
    parameter integer WALL_THICKNESS = 2,
    parameter integer ENTITY_PAD = CELL_SIZE / 4,
    parameter integer ENTITY_END = CELL_SIZE - (CELL_SIZE / 4)
) (
    input  wire [9:0]            pix_x,
    input  wire [9:0]            pix_y,
    input  wire                  video_active,
    input  wire [EAST_BITS-1:0]  east_walls_flat,
    input  wire [SOUTH_BITS-1:0] south_walls_flat,
    input  wire [XW-1:0]         player_x,
    input  wire [YW-1:0]         player_y,
    input  wire [XW-1:0]         solver_r_x,
    input  wire [YW-1:0]         solver_r_y,
    input  wire [XW-1:0]         solver_l_x,
    input  wire [YW-1:0]         solver_l_y,
    input  wire                  player_won,
    input  wire                  solver_r_won,
    input  wire                  solver_l_won,
    input  wire [3:0]            solver_speed,
    input  wire                  single_step_mode,
    input  wire                  gen_busy,
    input  wire [YW-1:0]         gen_row,
    input  wire [XW-1:0]         gen_col,
    input  wire [2:0]            gen_phase,
    output reg  [1:0]            r_out,
    output reg  [1:0]            g_out,
    output reg  [1:0]            b_out
);

    localparam [9:0] MAZE_PIX_W = MAZE_W * CELL_SIZE;
    localparam [9:0] MAZE_PIX_H = MAZE_H * CELL_SIZE;
    localparam [XW-1:0] GOAL_X = MAZE_W[XW-1:0] - 1'b1;
    localparam [YW-1:0] GOAL_Y = MAZE_H[YW-1:0] - 1'b1;
    localparam [CELL_SHIFT-1:0] WALL_LIMIT = WALL_THICKNESS;
    localparam [CELL_SHIFT-1:0] SOUTH_START = CELL_SIZE - WALL_THICKNESS;
    localparam [CELL_SHIFT-1:0] EAST_START = CELL_SIZE - WALL_THICKNESS;
    localparam [CELL_SHIFT-1:0] ENTITY_PAD_C = ENTITY_PAD;
    localparam [CELL_SHIFT-1:0] ENTITY_END_C = ENTITY_END;
    localparam [9:0] SPEED_X0 = MAZE_PIX_W + 10;
    localparam [9:0] SPEED_X1 = MAZE_PIX_W + 41;
    localparam [9:0] SPEED_FILL_X0 = MAZE_PIX_W + 12;

    wire [9:0] cell_x_full = pix_x >> CELL_SHIFT;
    wire [9:0] cell_y_full = pix_y >> CELL_SHIFT;
    wire [4:0] speed_fill_width = ({1'b0, 4'd15} - {1'b0, solver_speed} + 1'b1) << 1;

    wire in_maze = (pix_x < MAZE_PIX_W) && (pix_y < MAZE_PIX_H);
    wire [XW-1:0] cell_x = in_maze ? cell_x_full[XW-1:0] : {XW{1'b0}};
    wire [YW-1:0] cell_y = in_maze ? cell_y_full[YW-1:0] : {YW{1'b0}};
    wire [CELL_SHIFT-1:0] in_cell_x = pix_x[CELL_SHIFT-1:0];
    wire [CELL_SHIFT-1:0] in_cell_y = pix_y[CELL_SHIFT-1:0];

    wire north_wall;
    wire south_wall;
    wire east_wall;
    wire west_wall;

    wire on_north_wall = north_wall && (in_cell_y < WALL_LIMIT);
    wire on_south_wall = south_wall && (in_cell_y >= SOUTH_START);
    wire on_east_wall = east_wall && (in_cell_x >= EAST_START);
    wire on_west_wall = west_wall && (in_cell_x < WALL_LIMIT);
    wire on_wall = in_maze && (on_north_wall || on_south_wall || on_east_wall || on_west_wall);

    wire in_entity_area = (in_cell_x >= ENTITY_PAD_C) && (in_cell_x < ENTITY_END_C) &&
                          (in_cell_y >= ENTITY_PAD_C) && (in_cell_y < ENTITY_END_C);
    wire player_here = (cell_x == player_x) && (cell_y == player_y);
    wire solver_r_here = (cell_x == solver_r_x) && (cell_y == solver_r_y);
    wire solver_l_here = (cell_x == solver_l_x) && (cell_y == solver_l_y);
    wire draw_entities = in_maze && in_entity_area && ~on_wall && ~gen_busy;
    wire draw_player = draw_entities && player_here;
    wire draw_solver_r = draw_entities && solver_r_here;
    wire draw_solver_l = draw_entities && solver_l_here;
    wire draw_goal = in_maze && in_entity_area && ~on_wall && ~gen_busy && (cell_x == GOAL_X) && (cell_y == GOAL_Y) &&
                     ~player_here && ~solver_r_here && ~solver_l_here;

    wire highlight_row = gen_busy && in_maze && (cell_y == gen_row);
    wire highlight_cell = highlight_row && (cell_x == gen_col);

    wire in_speed_bar_area = (pix_x >= SPEED_X0) && (pix_x < (SPEED_X1 + 1'b1)) && (pix_y >= 10'd8) && (pix_y < 10'd18);
    wire speed_bar_border = in_speed_bar_area && ((pix_x == SPEED_X0) || (pix_x == SPEED_X1) || (pix_y == 10'd8) || (pix_y == 10'd17));
    wire speed_bar_fill = in_speed_bar_area && ~speed_bar_border && ((pix_x - SPEED_FILL_X0) < speed_fill_width);

    reg [1:0] phase_r;
    reg [1:0] phase_g;
    reg [1:0] phase_b;

    maze_wall_query #(
        .MAZE_W(MAZE_W),
        .MAZE_H(MAZE_H)
    ) pixel_walls (
        .cell_x(cell_x),
        .cell_y(cell_y),
        .east_walls_flat(east_walls_flat),
        .south_walls_flat(south_walls_flat),
        .north_wall(north_wall),
        .south_wall(south_wall),
        .east_wall(east_wall),
        .west_wall(west_wall)
    );

    always @(*) begin
        case (gen_phase)
            3'd0: begin phase_r = 2'b01; phase_g = 2'b01; phase_b = 2'b00; end
            3'd1: begin phase_r = 2'b10; phase_g = 2'b01; phase_b = 2'b00; end
            3'd2: begin phase_r = 2'b11; phase_g = 2'b10; phase_b = 2'b00; end
            3'd3: begin phase_r = 2'b10; phase_g = 2'b00; phase_b = 2'b10; end
            3'd4: begin phase_r = 2'b00; phase_g = 2'b10; phase_b = 2'b11; end
            3'd5: begin phase_r = 2'b11; phase_g = 2'b00; phase_b = 2'b01; end
            3'd6: begin phase_r = 2'b10; phase_g = 2'b11; phase_b = 2'b00; end
            default: begin phase_r = 2'b00; phase_g = 2'b10; phase_b = 2'b00; end
        endcase
    end

    always @(*) begin
        r_out = 2'b00;
        g_out = 2'b00;
        b_out = 2'b00;

        if (~video_active) begin
            r_out = 2'b00;
            g_out = 2'b00;
            b_out = 2'b00;
        end else if (speed_bar_border) begin
            r_out = 2'b11;
            g_out = 2'b11;
            b_out = single_step_mode ? 2'b00 : 2'b11;
        end else if (in_speed_bar_area) begin
            if (speed_bar_fill) begin
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
            r_out = 2'b11;
            g_out = 2'b11;
            b_out = 2'b11;
            if (highlight_row) begin
                r_out = phase_r | 2'b01;
                g_out = phase_g | 2'b01;
                b_out = phase_b | 2'b01;
            end
            if (highlight_cell) begin
                r_out = 2'b11;
                g_out = phase_g | 2'b10;
                b_out = phase_b | 2'b10;
            end
        end else if (draw_player) begin
            r_out = 2'b00;
            g_out = 2'b11;
            b_out = 2'b00;
        end else if (draw_solver_r) begin
            r_out = 2'b11;
            g_out = 2'b00;
            b_out = 2'b00;
        end else if (draw_solver_l) begin
            r_out = 2'b00;
            g_out = 2'b11;
            b_out = 2'b11;
        end else if (draw_goal) begin
            r_out = 2'b11;
            g_out = 2'b11;
            b_out = 2'b00;
        end else begin
            r_out = 2'b00;
            g_out = 2'b00;
            b_out = 2'b01;
            if (highlight_row) begin
                r_out = phase_r >> 1;
                g_out = phase_g >> 1;
                b_out = phase_b >> 1;
            end
            if (highlight_cell) begin
                r_out = phase_r;
                g_out = phase_g;
                b_out = phase_b;
            end
        end
    end

endmodule
