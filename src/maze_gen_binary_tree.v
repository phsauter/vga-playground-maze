`default_nettype none

module maze_gen_binary_tree #(
    parameter integer MAZE_W = 8,
    parameter integer MAZE_H = 8,
    parameter integer SEED_W = 16,
    parameter integer XW = $clog2(MAZE_W),
    parameter integer YW = $clog2(MAZE_H)
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              start,
    input  wire              step_en,
    input  wire              fast_mode,
    input  wire [SEED_W-1:0] seed,
    output reg               busy,
    output reg               done,
    output reg  [YW-1:0]     vis_row,
    output reg               clear_all,
    output reg               east_we,
    output reg  [XW-1:0]     east_x,
    output reg  [YW-1:0]     east_y,
    output reg               east_val,
    output reg               south_we,
    output reg  [XW-1:0]     south_x,
    output reg  [YW-1:0]     south_y,
    output reg               south_val
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

    task automatic advance_cell;
        begin
            if (col_idx == LAST_COL) begin
                col_idx <= {XW{1'b0}};
                row_idx <= row_idx + 1'b1;
            end else begin
                col_idx <= col_idx + 1'b1;
            end
        end
    endtask

    always @(posedge clk) begin
        if (~rst_n) begin
            gen_state <= G_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            vis_row <= {YW{1'b0}};
            clear_all <= 1'b0;
            east_we <= 1'b0;
            east_x <= {XW{1'b0}};
            east_y <= {YW{1'b0}};
            east_val <= 1'b1;
            south_we <= 1'b0;
            south_x <= {XW{1'b0}};
            south_y <= {YW{1'b0}};
            south_val <= 1'b1;
            col_idx <= {XW{1'b0}};
            row_idx <= {YW{1'b0}};
            lfsr <= {{(SEED_W-8){1'b0}}, 8'hA5};
        end else begin
            done <= 1'b0;
            clear_all <= 1'b0;
            east_we <= 1'b0;
            south_we <= 1'b0;

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
                        clear_all <= 1'b1;
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
                                east_we <= 1'b1;
                                east_x <= col_idx;
                                east_y <= row_idx;
                                east_val <= 1'b0;
                            end else if (col_idx == LAST_COL) begin
                                south_we <= 1'b1;
                                south_x <= col_idx;
                                south_y <= row_idx;
                                south_val <= 1'b0;
                            end else if (~lfsr[0]) begin
                                east_we <= 1'b1;
                                east_x <= col_idx;
                                east_y <= row_idx;
                                east_val <= 1'b0;
                            end else begin
                                south_we <= 1'b1;
                                south_x <= col_idx;
                                south_y <= row_idx;
                                south_val <= 1'b0;
                            end
                            advance_cell();
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
