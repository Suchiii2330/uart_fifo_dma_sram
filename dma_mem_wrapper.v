module dma_mem_wrapper (
    input wire clk,
    input wire reset,

    // CPU(external world) interface
    input wire [3:0] addr,
    input wire wr_en,
    input wire rd_en,
    input wire [31:0] wdata,
    output wire [31:0] rdata,

    // FIFO(ecxternal worls) interface
    input wire [7:0] fifo_data_out,
    input wire fifo_empty,
    output wire fifo_rd_en,

    // CPU RAM access
    input wire cpu_we,
    input wire cpu_re,
    input wire [9:0] cpu_addr,
    input wire [7:0] cpu_wdata,
    output wire [7:0] cpu_rdata,

    output wire dma_irq
);

wire [31:0] mem_addr;
wire [7:0]  mem_wdata;
wire mem_wr_en;

uart_rx_dma_v2 u_dma(
    .clk(clk),
    .reset(reset),
    .addr(addr),
    .wr_en(wr_en),
    .rd_en(rd_en),
    .wdata(wdata),
    .rdata(rdata),
    .fifo_data_out(fifo_data_out),
    .fifo_empty(fifo_empty),
    .fifo_rd_en(fifo_rd_en),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wr_en(mem_wr_en),
    .dma_irq(dma_irq)
);

sram_tdp_wf #(
    .ADDR_WIDTH(10),
    .DATA_WIDTH(8)
) u_ram(
    .clk(clk),

    .we_a(cpu_we),
    .re_a(cpu_re),
    .addr_a(cpu_addr),
    .wdata_a(cpu_wdata),
    .rdata_a(cpu_rdata),

    .we_b(mem_wr_en),
    .re_b(1'b0),
    .addr_b(mem_addr[9:0]),
    .wdata_b(mem_wdata),
    .rdata_b()
);

endmodule