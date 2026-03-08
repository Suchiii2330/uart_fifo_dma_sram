module uart_system_top (
    input wire clk,
    input wire reset,
    input wire rx_in,

    // CPU config bus
    input wire [3:0] cpu_addr,
    input wire cpu_wr_en,
    input wire cpu_rd_en,
    input wire [31:0] cpu_wdata,
    output wire [31:0] cpu_rdata,

    // CPU RAM access
    input wire cpu_ram_we,
    input wire cpu_ram_re,
    input wire [9:0] cpu_ram_addr,
    input wire [7:0] cpu_ram_wdata,
    output wire [7:0] cpu_ram_rdata,

    output wire dma_irq
);

wire [7:0] uart_data;
wire uart_valid;

wire [7:0] fifo_data;
wire fifo_empty;
wire fifo_full;
wire fifo_overflow;
wire fifo_rd_en;

uart_wrapper u_uart(
    .clk(clk),
    .reset(reset),
    .rx_in(rx_in),
    .data_out(uart_data),
    .data_valid(uart_valid),
    .frame_error(),
    .busy()
);

fifo_wrapper u_fifo(
    .clk(clk),
    .reset(reset),
    .wr_en(uart_valid),
    .wr_data(uart_data),
    .rd_en(fifo_rd_en),
    .rd_data(fifo_data),
    .full(fifo_full),
    .empty(fifo_empty),
    .overflow(fifo_overflow)
);

dma_mem_wrapper u_dma_mem(
    .clk(clk),
    .reset(reset),

    .addr(cpu_addr),
    .wr_en(cpu_wr_en),
    .rd_en(cpu_rd_en),
    .wdata(cpu_wdata),
    .rdata(cpu_rdata),

    .fifo_data_out(fifo_data),
    .fifo_empty(fifo_empty),
    .fifo_rd_en(fifo_rd_en),

    .cpu_we(cpu_ram_we),
    .cpu_re(cpu_ram_re),
    .cpu_addr(cpu_ram_addr),
    .cpu_wdata(cpu_ram_wdata),
    .cpu_rdata(cpu_ram_rdata),

    .dma_irq(dma_irq)
);

endmodule