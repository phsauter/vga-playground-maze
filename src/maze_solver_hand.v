`default_nettype none

module maze_solver_hand #(
    parameter integer MAZE_W = 8,
    parameter integer MAZE_H = 8,
    parameter integer XW = $clog2(MAZE_W),
    parameter integer YW = $clog2(MAZE_H),
    parameter integer RIGHT_HAND = 1
) (
    input  wire [XW-1:0] cur_x,
    input  wire [YW-1:0] cur_y,
    input  wire [1:0]    cur_dir,
    input  wire          north_wall,
    input  wire          south_wall,
    input  wire          east_wall,
    input  wire          west_wall,
    output reg  [XW-1:0] next_x,
    output reg  [YW-1:0] next_y,
    output reg  [1:0]    next_dir
);

    always @(*) begin
        next_x = cur_x;
        next_y = cur_y;
        next_dir = cur_dir;

        if (RIGHT_HAND != 0) begin
            case (cur_dir)
                2'd0: begin
                    if (~east_wall) begin next_x = cur_x + 1'b1; next_dir = 2'd1; end
                    else if (~north_wall) begin next_y = cur_y - 1'b1; end
                    else if (~west_wall) begin next_x = cur_x - 1'b1; next_dir = 2'd3; end
                    else begin next_dir = 2'd2; end
                end
                2'd1: begin
                    if (~south_wall) begin next_y = cur_y + 1'b1; next_dir = 2'd2; end
                    else if (~east_wall) begin next_x = cur_x + 1'b1; end
                    else if (~north_wall) begin next_y = cur_y - 1'b1; next_dir = 2'd0; end
                    else begin next_dir = 2'd3; end
                end
                2'd2: begin
                    if (~west_wall) begin next_x = cur_x - 1'b1; next_dir = 2'd3; end
                    else if (~south_wall) begin next_y = cur_y + 1'b1; end
                    else if (~east_wall) begin next_x = cur_x + 1'b1; next_dir = 2'd1; end
                    else begin next_dir = 2'd0; end
                end
                default: begin
                    if (~north_wall) begin next_y = cur_y - 1'b1; next_dir = 2'd0; end
                    else if (~west_wall) begin next_x = cur_x - 1'b1; end
                    else if (~south_wall) begin next_y = cur_y + 1'b1; next_dir = 2'd2; end
                    else begin next_dir = 2'd1; end
                end
            endcase
        end else begin
            case (cur_dir)
                2'd0: begin
                    if (~west_wall) begin next_x = cur_x - 1'b1; next_dir = 2'd3; end
                    else if (~north_wall) begin next_y = cur_y - 1'b1; end
                    else if (~east_wall) begin next_x = cur_x + 1'b1; next_dir = 2'd1; end
                    else begin next_dir = 2'd2; end
                end
                2'd1: begin
                    if (~north_wall) begin next_y = cur_y - 1'b1; next_dir = 2'd0; end
                    else if (~east_wall) begin next_x = cur_x + 1'b1; end
                    else if (~south_wall) begin next_y = cur_y + 1'b1; next_dir = 2'd2; end
                    else begin next_dir = 2'd3; end
                end
                2'd2: begin
                    if (~east_wall) begin next_x = cur_x + 1'b1; next_dir = 2'd1; end
                    else if (~south_wall) begin next_y = cur_y + 1'b1; end
                    else if (~west_wall) begin next_x = cur_x - 1'b1; next_dir = 2'd3; end
                    else begin next_dir = 2'd0; end
                end
                default: begin
                    if (~south_wall) begin next_y = cur_y + 1'b1; next_dir = 2'd2; end
                    else if (~west_wall) begin next_x = cur_x - 1'b1; end
                    else if (~north_wall) begin next_y = cur_y - 1'b1; next_dir = 2'd0; end
                    else begin next_dir = 2'd1; end
                end
            endcase
        end
    end

endmodule
