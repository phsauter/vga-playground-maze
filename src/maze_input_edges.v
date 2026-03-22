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
