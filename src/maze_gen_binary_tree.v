`default_nettype none

module maze_gen_binary_tree #(
    parameter integer MAZE_W = 8,
    parameter integer MAZE_H = 8,
    parameter integer SEED_W = 16,
    parameter integer XW = $clog2(MAZE_W),
    parameter integer YW = $clog2(MAZE_H),
    parameter integer EAST_BITS = MAZE_H * (MAZE_W - 1),
    parameter integer SOUTH_BITS = (MAZE_H - 1) * MAZE_W
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  start,
    input  wire                  step_en,
    input  wire                  fast_mode,
    input  wire [SEED_W-1:0]     seed,
    output reg                   busy,
    output reg                   done,
    output reg  [YW-1:0]         vis_row,
    output reg  [EAST_BITS-1:0]  east_walls_flat,
    output reg  [SOUTH_BITS-1:0] south_walls_flat
);

    localparam [1:0] G_IDLE  = 2'd0;
    localparam [1:0] G_CLEAR = 2'd1;
    localparam [1:0] G_CELL  = 2'd2;
    localparam [1:0] G_DONE  = 2'd3;
    localparam [XW-1:0] LAST_COL = MAZE_W - 1;
    localparam [YW-1:0] LAST_ROW = MAZE_H - 1;

    reg [1:0] gen_state;
    reg [XW-1:0] col_idx;
    reg [YW-1:0] row_idx;
    reg [SEED_W-1:0] lfsr;

    wire advance = busy & (fast_mode | step_en);

    function [SEED_W-1:0] lfsr_step;
        input [SEED_W-1:0] value;
        begin
            lfsr_step = {value[SEED_W-2:0], value[SEED_W-1] ^ value[SEED_W-3] ^ value[SEED_W-4] ^ value[SEED_W-6]};
        end
    endfunction

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
            gen_state <= G_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            vis_row <= {YW{1'b0}};
            east_walls_flat <= {EAST_BITS{1'b1}};
            south_walls_flat <= {SOUTH_BITS{1'b1}};
            col_idx <= {XW{1'b0}};
            row_idx <= {YW{1'b0}};
            lfsr <= {{(SEED_W-8){1'b0}}, 8'hA5};
        end else begin
            done <= 1'b0;

            if (start) begin
                gen_state <= G_CLEAR;
                busy <= 1'b1;
                vis_row <= {YW{1'b0}};
                col_idx <= {XW{1'b0}};
                row_idx <= {YW{1'b0}};
                lfsr <= (seed == {SEED_W{1'b0}}) ? {{(SEED_W-8){1'b0}}, 8'hA5} : seed;
            end else if (advance) begin
                lfsr <= lfsr_step(lfsr);
                case (gen_state)
                    G_CLEAR: begin
                        east_walls_flat <= {EAST_BITS{1'b1}};
                        south_walls_flat <= {SOUTH_BITS{1'b1}};
                        vis_row <= {YW{1'b0}};
                        col_idx <= {XW{1'b0}};
                        row_idx <= {YW{1'b0}};
                        gen_state <= G_CELL;
                    end

                    G_CELL: begin
                        vis_row <= row_idx;
                        if ((row_idx == LAST_ROW) && (col_idx == LAST_COL)) begin
                            gen_state <= G_DONE;
                        end else begin
                            if (row_idx == LAST_ROW) begin
                                east_walls_flat[east_idx(col_idx, row_idx)] <= 1'b0;
                            end else if (col_idx == LAST_COL) begin
                                south_walls_flat[south_idx(col_idx, row_idx)] <= 1'b0;
                            end else if (~lfsr[0]) begin
                                east_walls_flat[east_idx(col_idx, row_idx)] <= 1'b0;
                            end else begin
                                south_walls_flat[south_idx(col_idx, row_idx)] <= 1'b0;
                            end

                            if (col_idx == LAST_COL) begin
                                col_idx <= {XW{1'b0}};
                                row_idx <= row_idx + 1'b1;
                            end else begin
                                col_idx <= col_idx + 1'b1;
                            end
                        end
                    end

                    G_DONE: begin
                        vis_row <= LAST_ROW;
                        busy <= 1'b0;
                        done <= 1'b1;
                        gen_state <= G_IDLE;
                    end

                    default: begin
                        busy <= 1'b0;
                        gen_state <= G_IDLE;
                    end
                endcase
            end
        end
    end

endmodule
