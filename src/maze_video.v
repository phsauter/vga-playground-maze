`default_nettype none

module maze_video #(
    parameter integer MAZE_W = 6,
    parameter integer MAZE_H = 6,
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
    input  wire [XW-1:0]         solver_x,
    input  wire [YW-1:0]         solver_y,
    input  wire                  player_won,
    input  wire                  solver_won,
    input  wire                  gen_busy,
    input  wire [YW-1:0]         gen_row,
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
    wire [9:0] cell_x_full = pix_x >> CELL_SHIFT;
    wire [9:0] cell_y_full = pix_y >> CELL_SHIFT;

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
    wire solver_here = (cell_x == solver_x) && (cell_y == solver_y);
    wire draw_entities = in_maze && in_entity_area && ~on_wall && ~gen_busy;
    wire draw_player = draw_entities && player_here;
    wire draw_solver = draw_entities && solver_here;
    wire draw_goal = in_maze && in_entity_area && ~on_wall && ~gen_busy && (cell_x == GOAL_X) && (cell_y == GOAL_Y) &&
                     ~player_here && ~solver_here;

    wire highlight_row = gen_busy && in_maze && (cell_y == gen_row);
    wire row_visible = ~gen_busy || (cell_y <= gen_row);

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
        r_out = 2'b00;
        g_out = 2'b00;
        b_out = 2'b00;

        if (~video_active) begin
            r_out = 2'b00;
            g_out = 2'b00;
            b_out = 2'b00;
        end else if (~in_maze) begin
            r_out = 2'b00;
            g_out = 2'b00;
            b_out = 2'b00;
        end else if (~row_visible) begin
            r_out = 2'b00;
            g_out = 2'b00;
            b_out = 2'b00;
        end else if (player_won) begin
            r_out = 2'b00;
            g_out = 2'b11;
            b_out = 2'b00;
        end else if (solver_won) begin
            r_out = 2'b11;
            g_out = 2'b00;
            b_out = 2'b00;
        end else if (on_wall) begin
            r_out = 2'b11;
            g_out = 2'b11;
            b_out = 2'b11;
            if (highlight_row)
                b_out = 2'b10;
        end else if (draw_player) begin
            r_out = 2'b00;
            g_out = 2'b11;
            b_out = 2'b00;
        end else if (draw_solver) begin
            r_out = 2'b11;
            g_out = 2'b00;
            b_out = 2'b00;
        end else if (draw_goal) begin
            r_out = 2'b11;
            g_out = 2'b11;
            b_out = 2'b00;
        end else begin
            r_out = 2'b00;
            g_out = 2'b00;
            b_out = 2'b01;
            if (highlight_row)
                g_out = 2'b01;
        end
    end

endmodule
