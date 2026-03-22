`default_nettype none

module maze_map #(
    parameter integer MAZE_W = 8,
    parameter integer MAZE_H = 8,
    parameter integer XW = $clog2(MAZE_W),
    parameter integer YW = $clog2(MAZE_H),
    parameter integer EAST_BITS = MAZE_H * (MAZE_W - 1),
    parameter integer SOUTH_BITS = (MAZE_H - 1) * MAZE_W
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 clear_all,
    input  wire                 east_we,
    input  wire [XW-1:0]        east_x,
    input  wire [YW-1:0]        east_y,
    input  wire                 east_val,
    input  wire                 south_we,
    input  wire [XW-1:0]        south_x,
    input  wire [YW-1:0]        south_y,
    input  wire                 south_val,
    output reg  [EAST_BITS-1:0] east_walls_flat,
    output reg  [SOUTH_BITS-1:0] south_walls_flat
);

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

    always @(posedge clk) begin
        if (~rst_n) begin
            east_walls_flat <= {EAST_BITS{1'b1}};
            south_walls_flat <= {SOUTH_BITS{1'b1}};
        end else if (clear_all) begin
            east_walls_flat <= {EAST_BITS{1'b1}};
            south_walls_flat <= {SOUTH_BITS{1'b1}};
        end else begin
            if (east_we)
                east_walls_flat[east_idx(east_x, east_y)] <= east_val;
            if (south_we)
                south_walls_flat[south_idx(south_x, south_y)] <= south_val;
        end
    end

endmodule
