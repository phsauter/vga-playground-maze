`default_nettype none

module maze_wall_query_proc_binary_tree #(
    parameter integer MAZE_W = 8,
    parameter integer MAZE_H = 8,
    parameter integer SEED_W = 16,
    parameter integer XW = $clog2(MAZE_W),
    parameter integer YW = $clog2(MAZE_H)
) (
    input  wire [SEED_W-1:0] proc_seed,
    input  wire [XW-1:0]     cell_x,
    input  wire [YW-1:0]     cell_y,
    output wire              north_wall,
    output wire              south_wall,
    output wire              east_wall,
    output wire              west_wall
);

    localparam [XW-1:0] LAST_X = MAZE_W - 1;
    localparam [YW-1:0] LAST_Y = MAZE_H - 1;

    function choose_east;
        input [SEED_W-1:0] seed_value;
        input [XW-1:0] x;
        input [YW-1:0] y;
        integer idx0;
        integer idx1;
        reg mix;
        begin
            idx0 = (x + y) & (SEED_W - 1);
            idx1 = (x + (y << 1) + y + 5) & (SEED_W - 1);
            mix = seed_value[idx0] ^ seed_value[idx1] ^ x[0] ^ y[0] ^ ((x >> 1) & (y >> 1));
            choose_east = ~mix;
        end
    endfunction

    wire [XW-1:0] west_x = cell_x - 1'b1;
    wire [YW-1:0] north_y = cell_y - 1'b1;

    assign east_wall = (cell_x == LAST_X) ? 1'b1 : ((cell_y == LAST_Y) ? 1'b0 : ~choose_east(proc_seed, cell_x, cell_y));
    assign south_wall = (cell_y == LAST_Y) ? 1'b1 : ((cell_x == LAST_X) ? 1'b0 : choose_east(proc_seed, cell_x, cell_y));
    assign west_wall = (cell_x == {XW{1'b0}}) ? 1'b1 : ((cell_y == LAST_Y) ? 1'b0 : ~choose_east(proc_seed, west_x, cell_y));
    assign north_wall = (cell_y == {YW{1'b0}}) ? 1'b1 : ((cell_x == LAST_X) ? 1'b0 : choose_east(proc_seed, cell_x, north_y));

endmodule
