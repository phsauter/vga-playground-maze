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
