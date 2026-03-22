`default_nettype none

module maze_wall_query #(
    parameter integer MAZE_W = 8,
    parameter integer MAZE_H = 8,
    parameter integer XW = $clog2(MAZE_W),
    parameter integer YW = $clog2(MAZE_H),
    parameter integer EAST_BITS = MAZE_H * (MAZE_W - 1),
    parameter integer SOUTH_BITS = (MAZE_H - 1) * MAZE_W
) (
    input  wire [XW-1:0]         cell_x,
    input  wire [YW-1:0]         cell_y,
    input  wire [EAST_BITS-1:0]  east_walls_flat,
    input  wire [SOUTH_BITS-1:0] south_walls_flat,
    output wire                  north_wall,
    output wire                  south_wall,
    output wire                  east_wall,
    output wire                  west_wall
);

    localparam [XW-1:0] LAST_X = MAZE_W - 1;
    localparam [YW-1:0] LAST_Y = MAZE_H - 1;

    function integer east_idx;
        input [XW-1:0] x;
        input [YW-1:0] y;
        begin
            east_idx = y * (MAZE_W - 1) + x;
        end
    endfunction

    function integer south_idx;
        input [XW-1:0] x;
        input [YW-1:0] y;
        begin
            south_idx = y * MAZE_W + x;
        end
    endfunction

    wire [YW-1:0] north_y = cell_y - 1'b1;
    wire [XW-1:0] west_x = cell_x - 1'b1;

    assign north_wall = (cell_y == {YW{1'b0}}) ? 1'b1 : south_walls_flat[south_idx(cell_x, north_y)];
    assign south_wall = (cell_y == LAST_Y) ? 1'b1 : south_walls_flat[south_idx(cell_x, cell_y)];
    assign west_wall = (cell_x == {XW{1'b0}}) ? 1'b1 : east_walls_flat[east_idx(west_x, cell_y)];
    assign east_wall = (cell_x == LAST_X) ? 1'b1 : east_walls_flat[east_idx(cell_x, cell_y)];

endmodule
