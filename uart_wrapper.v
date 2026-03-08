module uart_wrapper (
    input  wire clk,
    input  wire reset,
    input  wire rx_in,

    output wire [7:0] data_out,
    output wire       data_valid,
    output wire       frame_error,
    output wire       busy
);

wire rx_sync;
wire tick_16x;
wire [3:0] os_cnt;
wire enable_data;
wire done;
wire clear_shift;

localparam BAUD_DIV = 16'd325;

synchronizer u_sync(
    .clk(clk),
    .reset(reset),
    .rx_in(rx_in),
    .rx_sync(rx_sync)
);

baud_gen_16x u_baud(
    .clk(clk),
    .reset(reset),
    .baud_div_16x(BAUD_DIV),
    .tick_16x(tick_16x)
);

oversample_counter u_os(
    .clk(clk),
    .reset(reset),
    .tick_16x(tick_16x),
    .os_cnt(os_cnt)
);

bit_counter u_bitcnt(
    .clk(clk),
    .reset(reset),
    .tick_16x(tick_16x),
    .os_cnt(os_cnt),
    .enable(enable_data),
    .bit_cnt(bit_cnt),
    .done(done)
);

shift_register u_shift(
    .clk(clk),
    .reset(reset),
    .tick_16x(tick_16x),
    .os_cnt(os_cnt),
    .enable(enable_data),
    .rx_sync(rx_sync),
    .clear(clear_shift),
    .data_out(data_out)
);

uart_rx_fsm u_fsm(
    .clk(clk),
    .reset(reset),
    .rx_sync(rx_sync),
    .tick_16x(tick_16x),
    .os_cnt(os_cnt),
    .done(done),
    .enable_data(enable_data),
    .data_valid(data_valid),
    .frame_error(frame_error),
    .busy(busy),
    .clear_shift(clear_shift)
);

endmodule