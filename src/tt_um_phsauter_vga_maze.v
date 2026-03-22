/*
 * Copyright (c) 2025 Uri Shaked
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_phsauter_vga_maze (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    localparam integer TOP_MAZE_W = 20;
    localparam integer TOP_MAZE_H = 15;
    localparam integer TOP_CELL_SHIFT = 5;
    localparam integer TOP_SEED_W = 16;
    localparam integer GEN_ALGO_ELLER = 0;
    localparam integer GEN_ALGO_BINARY = 1;
    localparam integer GEN_ALGO_PROC_BINARY = 2;
    localparam integer XW = $clog2(TOP_MAZE_W);
    localparam integer YW = $clog2(TOP_MAZE_H);
    localparam integer EAST_BITS = TOP_MAZE_H * (TOP_MAZE_W - 1);
    localparam integer SOUTH_BITS = (TOP_MAZE_H - 1) * TOP_MAZE_W;

    assign uio_out = 8'b0;
    assign uio_oe = 8'b0;

    wire hsync;
    wire vsync;
    wire video_active;
    wire [9:0] pix_x;
    wire [9:0] pix_y;
    reg vsync_prev;
    wire frame_tick = vsync & ~vsync_prev;

    wire [1:0] r_out;
    wire [1:0] g_out;
    wire [1:0] b_out;

    wire inp_up;
    wire inp_down;
    wire inp_left;
    wire inp_right;
    wire inp_a;
    wire inp_b;
    wire inp_select;
    wire inp_start;
    wire inp_x;
    wire inp_y;
    wire inp_l;
    wire inp_r;
    wire inp_present;

    wire _unused = &{ena, ui_in[7], ui_in[3:0], uio_in, inp_x, inp_y, inp_l, inp_r, inp_present, GEN_ALGO_ELLER[0], GEN_ALGO_BINARY[0], GEN_ALGO_PROC_BINARY[0]};

    wire [EAST_BITS-1:0] east_walls_flat;
    wire [SOUTH_BITS-1:0] south_walls_flat;
    wire [XW-1:0] player_x;
    wire [YW-1:0] player_y;
    wire [XW-1:0] solver_x;
    wire [YW-1:0] solver_y;
    wire [1:0] solver_dir;
    wire solver_active;
    wire player_won;
    wire solver_won;
    wire gen_busy;
    wire [YW-1:0] gen_row_vis;
    wire [TOP_SEED_W-1:0] maze_seed_vis;

    assign uo_out = {hsync, b_out[0], g_out[0], r_out[0], vsync, b_out[1], g_out[1], r_out[1]};

    hvsync_generator hvsync_gen (
        .clk(clk),
        .reset(~rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(video_active),
        .hpos(pix_x),
        .vpos(pix_y)
    );

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

    maze_game_core #(
        .MAZE_W(TOP_MAZE_W),
        .MAZE_H(TOP_MAZE_H),
        .SEED_W(TOP_SEED_W),
        .GEN_ALGO(GEN_ALGO_PROC_BINARY)
    ) core (
        .clk(clk),
        .rst_n(rst_n),
        .frame_tick(frame_tick),
        .inp_up(inp_up),
        .inp_down(inp_down),
        .inp_left(inp_left),
        .inp_right(inp_right),
        .inp_a(inp_a),
        .inp_b(inp_b),
        .inp_select(inp_select),
        .inp_start(inp_start),
        .east_walls_flat(east_walls_flat),
        .south_walls_flat(south_walls_flat),
        .player_x(player_x),
        .player_y(player_y),
        .solver_x(solver_x),
        .solver_y(solver_y),
        .solver_dir(solver_dir),
        .solver_active(solver_active),
        .player_won(player_won),
        .solver_won(solver_won),
        .gen_busy(gen_busy),
        .gen_row_vis(gen_row_vis),
        .maze_seed_vis(maze_seed_vis)
    );

    maze_video #(
        .MAZE_W(TOP_MAZE_W),
        .MAZE_H(TOP_MAZE_H),
        .SEED_W(TOP_SEED_W),
        .GEN_ALGO(GEN_ALGO_PROC_BINARY),
        .CELL_SHIFT(TOP_CELL_SHIFT)
    ) video (
        .pix_x(pix_x),
        .pix_y(pix_y),
        .video_active(video_active),
        .east_walls_flat(east_walls_flat),
        .south_walls_flat(south_walls_flat),
        .player_x(player_x),
        .player_y(player_y),
        .solver_x(solver_x),
        .solver_y(solver_y),
        .player_won(player_won),
        .solver_won(solver_won),
        .gen_busy(gen_busy),
        .gen_row(gen_row_vis),
        .maze_seed(maze_seed_vis),
        .r_out(r_out),
        .g_out(g_out),
        .b_out(b_out)
    );

    always @(posedge clk) begin
        if (~rst_n)
            vsync_prev <= 1'b0;
        else
            vsync_prev <= vsync;
    end

endmodule
