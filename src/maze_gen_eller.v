`default_nettype none

module maze_gen_eller #(
    parameter integer MAZE_W = 8,
    parameter integer MAZE_H = 8,
    parameter integer SEED_W = 16,
    parameter integer XW = $clog2(MAZE_W),
    parameter integer YW = $clog2(MAZE_H),
    parameter integer SET_ID_W = $clog2(MAZE_W + 1)
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
    output reg              clear_all,
    output reg              east_we,
    output reg  [XW-1:0]    east_x,
    output reg  [YW-1:0]    east_y,
    output reg              east_val,
    output reg              south_we,
    output reg  [XW-1:0]    south_x,
    output reg  [YW-1:0]    south_y,
    output reg              south_val
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

    wire advance = busy & (fast_mode | step_en);

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
            clear_all <= 1'b0;
            east_we <= 1'b0;
            south_we <= 1'b0;

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
                        clear_all <= 1'b1;
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
                            east_we <= 1'b1;
                            east_x <= col_idx;
                            east_y <= row_idx;
                            east_val <= 1'b0;
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
                            south_we <= 1'b1;
                            south_x <= col_idx;
                            south_y <= row_idx;
                            south_val <= 1'b0;
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
                            south_we <= 1'b1;
                            south_x <= col_idx;
                            south_y <= row_idx;
                            south_val <= 1'b0;
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
                            east_we <= 1'b1;
                            east_x <= col_idx;
                            east_y <= row_idx;
                            east_val <= 1'b0;
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
