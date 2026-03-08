module fifo_wrapper(
    input  wire clk,
    input  wire reset,

    input  wire wr_en,
    input  wire [7:0] wr_data,

    input  wire rd_en,
    output wire [7:0] rd_data,

    output wire full,
    output wire empty,
    output wire overflow
);

fifo_sync #(
    .DATA_WIDTH(8),
    .DEPTH(16)
) u_fifo (
    .clk(clk),
    .reset(reset),
    .wr_en(wr_en),
    .wr_data(wr_data),
    .rd_en(rd_en),
    .rd_data(rd_data),
    .full(full),
    .empty(empty),
    .overflow(overflow)
);

endmodule