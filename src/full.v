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
`default_nettype none

module maze_gen_proc_binary_tree #(
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
    output wire [EAST_BITS-1:0]  east_walls_flat,
    output wire [SOUTH_BITS-1:0] south_walls_flat
);

    localparam [1:0] G_IDLE = 2'd0;
    localparam [1:0] G_RUN  = 2'd1;
    localparam [1:0] G_DONE = 2'd2;
    localparam [YW-1:0] LAST_ROW = MAZE_H - 1;

    reg [1:0] gen_state;
    reg [SEED_W-1:0] latched_seed;

    wire advance = busy & (fast_mode | step_en);

    function choose_east;
        input integer x;
        input integer y;
        integer idx0;
        integer idx1;
        reg mix;
        begin
            idx0 = (x + y) & (SEED_W - 1);
            idx1 = (x + 3*y + 5) & (SEED_W - 1);
            mix = latched_seed[idx0] ^ latched_seed[idx1] ^ x[0] ^ y[0] ^ ((x >> 1) & (y >> 1));
            choose_east = ~mix;
        end
    endfunction

    genvar gx;
    genvar gy;
    generate
        for (gy = 0; gy < MAZE_H; gy = gy + 1) begin : gen_rows_e
            for (gx = 0; gx < MAZE_W - 1; gx = gx + 1) begin : gen_cols_e
                localparam integer EIDX = gy * (MAZE_W - 1) + gx;
                assign east_walls_flat[EIDX] = (gy == MAZE_H - 1) ? 1'b0 : ~choose_east(gx, gy);
            end
        end
        for (gy = 0; gy < MAZE_H - 1; gy = gy + 1) begin : gen_rows_s
            for (gx = 0; gx < MAZE_W; gx = gx + 1) begin : gen_cols_s
                localparam integer SIDX = gy * MAZE_W + gx;
                assign south_walls_flat[SIDX] = (gx == MAZE_W - 1) ? 1'b0 : choose_east(gx, gy);
            end
        end
    endgenerate

    always @(posedge clk) begin
        if (~rst_n) begin
            gen_state <= G_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            vis_row <= {YW{1'b0}};
            latched_seed <= {{(SEED_W-8){1'b0}}, 8'hA5};
        end else begin
            done <= 1'b0;

            if (start) begin
                gen_state <= G_RUN;
                busy <= 1'b1;
                vis_row <= {YW{1'b0}};
                latched_seed <= (seed == {SEED_W{1'b0}}) ? {{(SEED_W-8){1'b0}}, 8'hA5} : seed;
            end else if (advance) begin
                case (gen_state)
                    G_RUN: begin
                        if (vis_row == LAST_ROW)
                            gen_state <= G_DONE;
                        else
                            vis_row <= vis_row + 1'b1;
                    end

                    G_DONE: begin
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
`default_nettype none

module maze_video #(
    parameter integer MAZE_W = 6,
    parameter integer MAZE_H = 6,
    parameter integer SEED_W = 16,
    parameter integer GEN_ALGO = 1,
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
    input  wire [SEED_W-1:0]     maze_seed,
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

    generate
        if (GEN_ALGO == 2) begin : gen_proc_pixel_walls
            maze_wall_query_proc_binary_tree #(
                .MAZE_W(MAZE_W),
                .MAZE_H(MAZE_H),
                .SEED_W(SEED_W)
            ) pixel_walls (
                .proc_seed(maze_seed),
                .cell_x(cell_x),
                .cell_y(cell_y),
                .north_wall(north_wall),
                .south_wall(south_wall),
                .east_wall(east_wall),
                .west_wall(west_wall)
            );
        end else begin : gen_stored_pixel_walls
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
        end
    endgenerate

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

`default_nettype none

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
      data_reg <= {BIT_WIDTH{1'b1}};
      shift_reg <= {BIT_WIDTH{1'b1}};
      pmod_clk_prev <= 1'b0;
      pmod_latch_prev <= 1'b0;
    end else begin
      pmod_clk_prev <= pmod_clk_sync[1];
      pmod_latch_prev <= pmod_latch_sync[1];

      if (pmod_latch_sync[1] & ~pmod_latch_prev)
        data_reg <= shift_reg;

      if (pmod_clk_sync[1] & ~pmod_clk_prev)
        shift_reg <= {shift_reg[BIT_WIDTH-2:0], pmod_data_sync[1]};
    end
  end

endmodule

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

  wire reg_empty = (data_reg == 12'hfff);
  assign is_present = reg_empty ? 1'b0 : 1'b1;
  assign {b, y, select, start, up, down, left, right, a, x, l, r} = reg_empty ? 12'b0 : data_reg;

endmodule

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
`default_nettype none

/*
 * Main control/gameplay block.
 *
 * Controls:
 * - D-pad: move the player during play.
 * - A: start/stop the solver.
 * - B: reset player and solver positions.
 * - SELECT: generate a new maze from the current LFSR seed.
 * - START: while generating, switch to fast generation mode.
 */

module maze_game_core #(
    parameter integer MAZE_W = 6,
    parameter integer MAZE_H = 6,
    parameter integer SEED_W = 16,
    parameter integer GEN_ALGO = 1,
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
    output wire [EAST_BITS-1:0]  east_walls_flat,
    output wire [SOUTH_BITS-1:0] south_walls_flat,
    output reg  [XW-1:0]         player_x,
    output reg  [YW-1:0]         player_y,
    output reg  [XW-1:0]         solver_x,
    output reg  [YW-1:0]         solver_y,
    output reg  [1:0]            solver_dir,
    output reg                   solver_active,
    output reg                   player_won,
    output reg                   solver_won,
    output wire                  gen_busy,
    output wire [YW-1:0]         gen_row_vis,
    output wire [SEED_W-1:0]     maze_seed_vis
);

    localparam [2:0] C_RESET = 3'd0;
    localparam [2:0] C_GEN_START = 3'd1;
    localparam [2:0] C_GEN_RUN = 3'd2;
    localparam [2:0] C_PLAY = 3'd3;
    localparam [2:0] C_WIN = 3'd4;
    localparam [XW-1:0] GOAL_X = MAZE_W[XW-1:0] - 1'b1;
    localparam [YW-1:0] GOAL_Y = MAZE_H[YW-1:0] - 1'b1;
    localparam [1:0] SOLVER_DIV = 2'd3;
    localparam integer GEN_ALGO_ELLER = 0;
    localparam integer GEN_ALGO_BINARY = 1;
    localparam integer GEN_ALGO_PROC_BINARY = 2;

    reg [2:0] core_state;
    reg [SEED_W-1:0] lfsr;
    reg [SEED_W-1:0] maze_seed;
    reg [1:0] solver_frame_count;
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

    wire gen_done;

    wire player_north_wall;
    wire player_south_wall;
    wire player_east_wall;
    wire player_west_wall;
    wire solver_north_wall;
    wire solver_south_wall;
    wire solver_east_wall;
    wire solver_west_wall;

    wire [XW-1:0] solver_next_x;
    wire [YW-1:0] solver_next_y;
    wire [1:0] solver_next_dir;

    assign maze_seed_vis = maze_seed;

    wire solver_tick_normal = frame_tick && (solver_frame_count == 0);
    wire solver_tick = (core_state == C_PLAY) && solver_active && ~player_won && ~solver_won && solver_tick_normal;

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
        .up_edge(up_edge),
        .down_edge(down_edge),
        .left_edge(left_edge),
        .right_edge(right_edge),
        .a_edge(a_edge),
        .b_edge(b_edge),
        .select_edge(select_edge),
        .start_edge(start_edge)
    );

    generate
        if (GEN_ALGO == GEN_ALGO_ELLER) begin : gen_eller
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
                .east_walls_flat(east_walls_flat),
                .south_walls_flat(south_walls_flat)
            );
        end else if (GEN_ALGO == GEN_ALGO_BINARY) begin : gen_binary
            maze_gen_binary_tree #(
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
                .east_walls_flat(east_walls_flat),
                .south_walls_flat(south_walls_flat)
            );
        end else begin : gen_proc_binary
            maze_gen_proc_binary_tree #(
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
                .east_walls_flat(east_walls_flat),
                .south_walls_flat(south_walls_flat)
            );
        end
    endgenerate

    generate
        if (GEN_ALGO == GEN_ALGO_PROC_BINARY) begin : gen_proc_queries
            maze_wall_query_proc_binary_tree #(
                .MAZE_W(MAZE_W),
                .MAZE_H(MAZE_H),
                .SEED_W(SEED_W)
            ) player_walls (
                .proc_seed(maze_seed),
                .cell_x(player_x),
                .cell_y(player_y),
                .north_wall(player_north_wall),
                .south_wall(player_south_wall),
                .east_wall(player_east_wall),
                .west_wall(player_west_wall)
            );

            maze_wall_query_proc_binary_tree #(
                .MAZE_W(MAZE_W),
                .MAZE_H(MAZE_H),
                .SEED_W(SEED_W)
            ) solver_walls (
                .proc_seed(maze_seed),
                .cell_x(solver_x),
                .cell_y(solver_y),
                .north_wall(solver_north_wall),
                .south_wall(solver_south_wall),
                .east_wall(solver_east_wall),
                .west_wall(solver_west_wall)
            );
        end else begin : gen_stored_queries
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
            ) solver_walls (
                .cell_x(solver_x),
                .cell_y(solver_y),
                .east_walls_flat(east_walls_flat),
                .south_walls_flat(south_walls_flat),
                .north_wall(solver_north_wall),
                .south_wall(solver_south_wall),
                .east_wall(solver_east_wall),
                .west_wall(solver_west_wall)
            );
        end
    endgenerate

    maze_solver_hand #(
        .MAZE_W(MAZE_W),
        .MAZE_H(MAZE_H),
        .RIGHT_HAND(1)
    ) solver (
        .cur_x(solver_x),
        .cur_y(solver_y),
        .cur_dir(solver_dir),
        .north_wall(solver_north_wall),
        .south_wall(solver_south_wall),
        .east_wall(solver_east_wall),
        .west_wall(solver_west_wall),
        .next_x(solver_next_x),
        .next_y(solver_next_y),
        .next_dir(solver_next_dir)
    );

    always @(posedge clk) begin
        if (~rst_n) begin
            core_state <= C_RESET;
            lfsr <= {{(SEED_W-8){1'b0}}, 8'hA5};
            maze_seed <= {{(SEED_W-8){1'b0}}, 8'hA5};
            player_x <= {XW{1'b0}};
            player_y <= {YW{1'b0}};
            solver_x <= {XW{1'b0}};
            solver_y <= {YW{1'b0}};
            solver_dir <= 2'd1;
            solver_active <= 1'b0;
            player_won <= 1'b0;
            solver_won <= 1'b0;
            solver_frame_count <= 2'd0;
            gen_start <= 1'b0;
            gen_fast_mode <= 1'b0;
        end else begin
            gen_start <= 1'b0;

            if (frame_tick)
                lfsr <= lfsr_step(lfsr);

            if ((core_state == C_PLAY) && frame_tick) begin
                if (solver_frame_count == 0)
                    solver_frame_count <= SOLVER_DIV;
                else
                    solver_frame_count <= solver_frame_count - 1'b1;
            end

            if (solver_tick) begin
                solver_x <= solver_next_x;
                solver_y <= solver_next_y;
                solver_dir <= solver_next_dir;
            end

            case (core_state)
                C_RESET: begin
                    player_x <= {XW{1'b0}};
                    player_y <= {YW{1'b0}};
                    solver_x <= {XW{1'b0}};
                    solver_y <= {YW{1'b0}};
                    solver_dir <= 2'd1;
                    solver_active <= 1'b0;
                    player_won <= 1'b0;
                    solver_won <= 1'b0;
                    gen_fast_mode <= 1'b0;
                    core_state <= C_GEN_START;
                end

                C_GEN_START: begin
                    gen_start <= 1'b1;
                    gen_fast_mode <= 1'b0;
                    player_x <= {XW{1'b0}};
                    player_y <= {YW{1'b0}};
                    solver_x <= {XW{1'b0}};
                    solver_y <= {YW{1'b0}};
                    solver_dir <= 2'd1;
                    solver_active <= 1'b0;
                    player_won <= 1'b0;
                    solver_won <= 1'b0;
                    solver_frame_count <= SOLVER_DIV;
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
                            solver_x <= {XW{1'b0}};
                            solver_y <= {YW{1'b0}};
                            solver_dir <= 2'd1;
                            player_won <= 1'b0;
                            solver_won <= 1'b0;
                            solver_active <= 1'b0;
                        end

                        if (a_edge && ~player_won && ~solver_won)
                            solver_active <= ~solver_active;

                        if (~player_won && ~solver_won) begin
                            if (up_edge && ~player_north_wall && (player_y > 0))
                                player_y <= player_y - 1'b1;
                            if (down_edge && ~player_south_wall && (player_y < GOAL_Y))
                                player_y <= player_y + 1'b1;
                            if (left_edge && ~player_west_wall && (player_x > 0))
                                player_x <= player_x - 1'b1;
                            if (right_edge && ~player_east_wall && (player_x < GOAL_X))
                                player_x <= player_x + 1'b1;
                        end

                        if ((player_x == GOAL_X) && (player_y == GOAL_Y) && ~player_won && ~solver_won) begin
                            player_won <= 1'b1;
                            solver_active <= 1'b0;
                            core_state <= C_WIN;
                        end else if ((solver_x == GOAL_X) && (solver_y == GOAL_Y) && solver_active && ~player_won && ~solver_won) begin
                            solver_won <= 1'b1;
                            solver_active <= 1'b0;
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
                        solver_x <= {XW{1'b0}};
                        solver_y <= {YW{1'b0}};
                        solver_dir <= 2'd1;
                        player_won <= 1'b0;
                        solver_won <= 1'b0;
                        solver_active <= 1'b0;
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
`default_nettype none

module maze_gen_eller #(
    parameter integer MAZE_W = 8,
    parameter integer MAZE_H = 8,
    parameter integer SEED_W = 16,
    parameter integer XW = $clog2(MAZE_W),
    parameter integer YW = $clog2(MAZE_H),
    parameter integer SET_ID_W = $clog2(MAZE_W + 1),
    parameter integer EAST_BITS = MAZE_H * (MAZE_W - 1),
    parameter integer SOUTH_BITS = (MAZE_H - 1) * MAZE_W
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             start,
    input  wire             step_en,
    input  wire             fast_mode,
    input  wire [SEED_W-1:0] seed,
    output reg              busy,
    output reg              done,
    output reg  [YW-1:0]    vis_row,
    output reg  [EAST_BITS-1:0]  east_walls_flat,
    output reg  [SOUTH_BITS-1:0] south_walls_flat
);

    localparam [3:0] G_IDLE = 4'd0;
    localparam [3:0] G_CLEAR = 4'd1;
    localparam [3:0] G_LOAD_ROW = 4'd2;
    localparam [3:0] G_ASSIGN_SETS = 4'd3;
    localparam [3:0] G_JOIN_SCAN = 4'd4;
    localparam [3:0] G_MERGE_REMAP = 4'd5;
    localparam [3:0] G_PREP_DOWN = 4'd6;
    localparam [3:0] G_DOWN_SCAN = 4'd7;
    localparam [3:0] G_REPAIR_SCAN = 4'd8;
    localparam [3:0] G_ADVANCE_ROW = 4'd9;
    localparam [3:0] G_LAST_ROW_JOIN = 4'd10;
    localparam [3:0] G_DONE = 4'd11;

    localparam [XW-1:0] LAST_COL = MAZE_W - 1;
    localparam [XW-1:0] LAST_PAIR_COL = MAZE_W - 2;
    localparam [YW-1:0] LAST_ROW = MAZE_H - 1;
    localparam [1:0] JOIN_BIAS = 2'd1;
    localparam [1:0] DROP_BIAS = 2'd2;

    reg [3:0] gen_state;
    reg [YW-1:0] row_idx;
    reg [XW-1:0] col_idx;
    reg [XW-1:0] remap_idx;
    reg merge_last_row;
    reg [SET_ID_W-1:0] merge_from;
    reg [SET_ID_W-1:0] merge_to;
    reg [SEED_W-1:0] lfsr;

    reg [SET_ID_W-1:0] row_set [0:MAZE_W-1];
    reg [SET_ID_W-1:0] next_row_set [0:MAZE_W-1];
    reg used_ids [0:MAZE_W];
    reg set_has_down [0:MAZE_W];
    reg set_seen [0:MAZE_W];
    reg [XW-1:0] set_first_x [0:MAZE_W];

    integer i;
    integer free_id;

    function [SEED_W-1:0] lfsr_step;
        input [SEED_W-1:0] value;
        begin
            lfsr_step = {value[SEED_W-2:0], value[SEED_W-1] ^ value[SEED_W-3] ^ value[SEED_W-4] ^ value[SEED_W-6]};
        end
    endfunction

    function decide_path;
        input [1:0] rnd;
        input [1:0] bias;
        begin
            case (bias)
                2'd0: decide_path = (rnd == 2'b00);
                2'd1: decide_path = rnd[0];
                2'd2: decide_path = (rnd != 2'b00);
                default: decide_path = (rnd != 2'b11);
            endcase
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

    wire advance = busy & (fast_mode | step_en);

    always @(posedge clk) begin
        if (~rst_n) begin
            gen_state <= G_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            vis_row <= {YW{1'b0}};
            east_walls_flat <= {EAST_BITS{1'b1}};
            south_walls_flat <= {SOUTH_BITS{1'b1}};
            row_idx <= {YW{1'b0}};
            col_idx <= {XW{1'b0}};
            remap_idx <= {XW{1'b0}};
            merge_last_row <= 1'b0;
            merge_from <= {SET_ID_W{1'b0}};
            merge_to <= {SET_ID_W{1'b0}};
            lfsr <= {{(SEED_W-8){1'b0}}, 8'hA5};
            for (i = 0; i < MAZE_W; i = i + 1) begin
                row_set[i] <= {SET_ID_W{1'b0}};
                next_row_set[i] <= {SET_ID_W{1'b0}};
            end
            for (i = 0; i <= MAZE_W; i = i + 1) begin
                used_ids[i] <= 1'b0;
                set_has_down[i] <= 1'b0;
                set_seen[i] <= 1'b0;
                set_first_x[i] <= {XW{1'b0}};
            end
        end else begin
            done <= 1'b0;

            if (start) begin
                gen_state <= G_CLEAR;
                busy <= 1'b1;
                vis_row <= {YW{1'b0}};
                row_idx <= {YW{1'b0}};
                col_idx <= {XW{1'b0}};
                remap_idx <= {XW{1'b0}};
                merge_last_row <= 1'b0;
                merge_from <= {SET_ID_W{1'b0}};
                merge_to <= {SET_ID_W{1'b0}};
                lfsr <= (seed == {SEED_W{1'b0}}) ? {{(SEED_W-8){1'b0}}, 8'hA5} : seed;
                for (i = 0; i < MAZE_W; i = i + 1) begin
                    row_set[i] <= {SET_ID_W{1'b0}};
                    next_row_set[i] <= {SET_ID_W{1'b0}};
                end
                for (i = 0; i <= MAZE_W; i = i + 1) begin
                    used_ids[i] <= 1'b0;
                    set_has_down[i] <= 1'b0;
                    set_seen[i] <= 1'b0;
                    set_first_x[i] <= {XW{1'b0}};
                end
            end else if (advance) begin
                lfsr <= lfsr_step(lfsr);
                case (gen_state)
                    G_CLEAR: begin
                        east_walls_flat <= {EAST_BITS{1'b1}};
                        south_walls_flat <= {SOUTH_BITS{1'b1}};
                        vis_row <= {YW{1'b0}};
                        for (i = 0; i < MAZE_W; i = i + 1) begin
                            row_set[i] <= {SET_ID_W{1'b0}};
                            next_row_set[i] <= {SET_ID_W{1'b0}};
                        end
                        for (i = 0; i <= MAZE_W; i = i + 1) begin
                            used_ids[i] <= 1'b0;
                            set_has_down[i] <= 1'b0;
                            set_seen[i] <= 1'b0;
                            set_first_x[i] <= {XW{1'b0}};
                        end
                        gen_state <= G_LOAD_ROW;
                    end

                    G_LOAD_ROW: begin
                        vis_row <= row_idx;
                        col_idx <= {XW{1'b0}};
                        for (i = 0; i <= MAZE_W; i = i + 1) begin
                            used_ids[i] <= 1'b0;
                            set_has_down[i] <= 1'b0;
                            set_seen[i] <= 1'b0;
                            set_first_x[i] <= {XW{1'b0}};
                        end
                        for (i = 0; i < MAZE_W; i = i + 1) begin
                            row_set[i] <= next_row_set[i];
                            if (next_row_set[i] != {SET_ID_W{1'b0}})
                                used_ids[next_row_set[i]] <= 1'b1;
                            next_row_set[i] <= {SET_ID_W{1'b0}};
                        end
                        gen_state <= G_ASSIGN_SETS;
                    end

                    G_ASSIGN_SETS: begin
                        vis_row <= row_idx;
                        if (row_set[col_idx] == {SET_ID_W{1'b0}}) begin
                            free_id = 0;
                            for (i = 1; i <= MAZE_W; i = i + 1)
                                if ((free_id == 0) && ~used_ids[i])
                                    free_id = i;
                            row_set[col_idx] <= free_id[SET_ID_W-1:0];
                            used_ids[free_id] <= 1'b1;
                        end

                        if (col_idx == LAST_COL) begin
                            col_idx <= {XW{1'b0}};
                            if (row_idx == LAST_ROW)
                                gen_state <= G_LAST_ROW_JOIN;
                            else
                                gen_state <= G_JOIN_SCAN;
                        end else begin
                            col_idx <= col_idx + 1'b1;
                        end
                    end

                    G_JOIN_SCAN: begin
                        vis_row <= row_idx;
                        if (row_set[col_idx] != row_set[col_idx + 1'b1] && decide_path(lfsr[1:0], JOIN_BIAS)) begin
                            east_walls_flat[east_idx(col_idx, row_idx)] <= 1'b0;
                            merge_from <= row_set[col_idx + 1'b1];
                            merge_to <= row_set[col_idx];
                            remap_idx <= {XW{1'b0}};
                            merge_last_row <= 1'b0;
                            gen_state <= G_MERGE_REMAP;
                        end else if (col_idx == LAST_PAIR_COL) begin
                            gen_state <= G_PREP_DOWN;
                            col_idx <= {XW{1'b0}};
                        end else begin
                            col_idx <= col_idx + 1'b1;
                        end
                    end

                    G_MERGE_REMAP: begin
                        vis_row <= row_idx;
                        if (row_set[remap_idx] == merge_from)
                            row_set[remap_idx] <= merge_to;

                        if (remap_idx == LAST_COL) begin
                            remap_idx <= {XW{1'b0}};
                            if (merge_last_row) begin
                                if (col_idx == LAST_PAIR_COL)
                                    gen_state <= G_DONE;
                                else begin
                                    col_idx <= col_idx + 1'b1;
                                    gen_state <= G_LAST_ROW_JOIN;
                                end
                            end else begin
                                if (col_idx == LAST_PAIR_COL) begin
                                    gen_state <= G_PREP_DOWN;
                                    col_idx <= {XW{1'b0}};
                                end else begin
                                    col_idx <= col_idx + 1'b1;
                                    gen_state <= G_JOIN_SCAN;
                                end
                            end
                        end else begin
                            remap_idx <= remap_idx + 1'b1;
                        end
                    end

                    G_PREP_DOWN: begin
                        vis_row <= row_idx;
                        col_idx <= {XW{1'b0}};
                        for (i = 0; i <= MAZE_W; i = i + 1) begin
                            set_has_down[i] <= 1'b0;
                            set_seen[i] <= 1'b0;
                        end
                        gen_state <= G_DOWN_SCAN;
                    end

                    G_DOWN_SCAN: begin
                        vis_row <= row_idx;

                        if (~set_seen[row_set[col_idx]]) begin
                            set_seen[row_set[col_idx]] <= 1'b1;
                            set_first_x[row_set[col_idx]] <= col_idx;
                        end

                        if (decide_path(lfsr[3:2], DROP_BIAS)) begin
                            south_walls_flat[south_idx(col_idx, row_idx)] <= 1'b0;
                            next_row_set[col_idx] <= row_set[col_idx];
                            set_has_down[row_set[col_idx]] <= 1'b1;
                        end else begin
                            next_row_set[col_idx] <= {SET_ID_W{1'b0}};
                        end

                        if (col_idx == LAST_COL) begin
                            col_idx <= {XW{1'b0}};
                            gen_state <= G_REPAIR_SCAN;
                        end else begin
                            col_idx <= col_idx + 1'b1;
                        end
                    end

                    G_REPAIR_SCAN: begin
                        vis_row <= row_idx;
                        if (~set_has_down[row_set[col_idx]] && (set_first_x[row_set[col_idx]] == col_idx)) begin
                            south_walls_flat[south_idx(col_idx, row_idx)] <= 1'b0;
                            next_row_set[col_idx] <= row_set[col_idx];
                            set_has_down[row_set[col_idx]] <= 1'b1;
                        end

                        if (col_idx == LAST_COL)
                            gen_state <= G_ADVANCE_ROW;
                        else
                            col_idx <= col_idx + 1'b1;
                    end

                    G_ADVANCE_ROW: begin
                        vis_row <= row_idx;
                        row_idx <= row_idx + 1'b1;
                        gen_state <= G_LOAD_ROW;
                    end

                    G_LAST_ROW_JOIN: begin
                        vis_row <= row_idx;
                        if (row_set[col_idx] != row_set[col_idx + 1'b1]) begin
                            east_walls_flat[east_idx(col_idx, row_idx)] <= 1'b0;
                            merge_from <= row_set[col_idx + 1'b1];
                            merge_to <= row_set[col_idx];
                            remap_idx <= {XW{1'b0}};
                            merge_last_row <= 1'b1;
                            gen_state <= G_MERGE_REMAP;
                        end else if (col_idx == LAST_PAIR_COL) begin
                            gen_state <= G_DONE;
                        end else begin
                            col_idx <= col_idx + 1'b1;
                        end
                    end

                    G_DONE: begin
                        vis_row <= row_idx;
                        busy <= 1'b0;
                        done <= 1'b1;
                        gen_state <= G_IDLE;
                    end

                    default: begin
                        gen_state <= G_IDLE;
                        busy <= 1'b0;
                    end
                endcase
            end
        end
    end

endmodule
`default_nettype none

module maze_input_edges (
    input  wire clk,
    input  wire rst_n,
    input  wire inp_up,
    input  wire inp_down,
    input  wire inp_left,
    input  wire inp_right,
    input  wire inp_a,
    input  wire inp_b,
    input  wire inp_select,
    input  wire inp_start,
    output wire up_edge,
    output wire down_edge,
    output wire left_edge,
    output wire right_edge,
    output wire a_edge,
    output wire b_edge,
    output wire select_edge,
    output wire start_edge
);

    reg inp_up_prev;
    reg inp_down_prev;
    reg inp_left_prev;
    reg inp_right_prev;
    reg inp_a_prev;
    reg inp_b_prev;
    reg inp_select_prev;
    reg inp_start_prev;

    assign up_edge = inp_up & ~inp_up_prev;
    assign down_edge = inp_down & ~inp_down_prev;
    assign left_edge = inp_left & ~inp_left_prev;
    assign right_edge = inp_right & ~inp_right_prev;
    assign a_edge = inp_a & ~inp_a_prev;
    assign b_edge = inp_b & ~inp_b_prev;
    assign select_edge = inp_select & ~inp_select_prev;
    assign start_edge = inp_start & ~inp_start_prev;

    always @(posedge clk) begin
        if (~rst_n) begin
            inp_up_prev <= 1'b0;
            inp_down_prev <= 1'b0;
            inp_left_prev <= 1'b0;
            inp_right_prev <= 1'b0;
            inp_a_prev <= 1'b0;
            inp_b_prev <= 1'b0;
            inp_select_prev <= 1'b0;
            inp_start_prev <= 1'b0;
        end else begin
            inp_up_prev <= inp_up;
            inp_down_prev <= inp_down;
            inp_left_prev <= inp_left;
            inp_right_prev <= inp_right;
            inp_a_prev <= inp_a;
            inp_b_prev <= inp_b;
            inp_select_prev <= inp_select;
            inp_start_prev <= inp_start;
        end
    end

endmodule
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
