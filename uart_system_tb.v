`timescale 1ns/1ps

module uart_system_tb;

//////////////////////////////////////////////////////
// CLOCK (50 MHz)
//////////////////////////////////////////////////////

reg clk = 0;
always #10 clk = ~clk;   // 20ns period

//////////////////////////////////////////////////////
// RESET
//////////////////////////////////////////////////////

reg reset;

//////////////////////////////////////////////////////
// UART RX LINE
//////////////////////////////////////////////////////

reg rx_in;

//////////////////////////////////////////////////////
// CPU CONFIG BUS: memory-mapped control bus used by the CPU to configure DMA.
//////////////////////////////////////////////////////

reg  [3:0]  cpu_addr;
reg         cpu_wr_en;
reg         cpu_rd_en;
reg  [31:0] cpu_wdata;
wire [31:0] cpu_rdata;

//////////////////////////////////////////////////////
// CPU RAM ACCESS: CPU reads data from its main memory buffer ie RAM
//////////////////////////////////////////////////////

reg         cpu_ram_we;
reg         cpu_ram_re;
reg  [9:0]  cpu_ram_addr;
reg  [7:0]  cpu_ram_wdata;
wire [7:0]  cpu_ram_rdata;

//////////////////////////////////////////////////////
// INTERRUPT
//////////////////////////////////////////////////////

wire dma_irq;

//////////////////////////////////////////////////////
// DUT
//////////////////////////////////////////////////////

uart_system_top dut(
    .clk(clk),
    .reset(reset),
    .rx_in(rx_in),

    .cpu_addr(cpu_addr),
    .cpu_wr_en(cpu_wr_en),
    .cpu_rd_en(cpu_rd_en),
    .cpu_wdata(cpu_wdata),
    .cpu_rdata(cpu_rdata),

    .cpu_ram_we(cpu_ram_we),
    .cpu_ram_re(cpu_ram_re),
    .cpu_ram_addr(cpu_ram_addr),
    .cpu_ram_wdata(cpu_ram_wdata),
    .cpu_ram_rdata(cpu_ram_rdata),

    .dma_irq(dma_irq)
);

//////////////////////////////////////////////////////
// EXPECTED DATA
//////////////////////////////////////////////////////

reg [7:0] expected_data [0:2];
integer i=0;

//////////////////////////////////////////////////////
// UART TRANSMIT TASK
//////////////////////////////////////////////////////

//simulate external device sending data to uart receiver
task send_uart_byte(input [7:0] data); //send one byte
integer j;
begin

    // START BIT
    rx_in = 0;
    #(104170);

    // DATA BITS
    for(j=0; j<8; j=j+1) begin
        rx_in = data[j];
        #(104170);
    end

    // STOP BIT
    rx_in = 1;
    #(104170);

end
endtask

//////////////////////////////////////////////////////
// MAIN TEST
//////////////////////////////////////////////////////

initial begin

    //////////////////////////////////
    // INITIAL STATE
    //////////////////////////////////

    reset = 1;
    rx_in = 1;

    cpu_wr_en = 0;
    cpu_rd_en = 0;
    cpu_addr  = 0;
    cpu_wdata = 0;

    cpu_ram_we = 0;
    cpu_ram_re = 0;
    cpu_ram_addr  = 0;
cpu_ram_wdata = 0;

    //////////////////////////////////
    // EXPECTED DATA: we expect CPU to read this data from RAM 
    //////////////////////////////////

    expected_data[0] = 8'h55;
    expected_data[1] = 8'hA3;
    expected_data[2] = 8'h0F;

    //////////////////////////////////
    // RELEASE RESET
    //////////////////////////////////

    #200;
    reset = 0;

    //////////////////////////////////
    // CONFIGURE DMA, choose which register to configure using address
    //////////////////////////////////

    // RAM address = 0
    cpu_addr  = 4'h4;//0x04 : DMA_ADDR
    cpu_wdata = 32'd0; 
    cpu_wr_en = 1;
    #20 cpu_wr_en = 0;

    // transfer length = 3 bytes
    cpu_addr  = 4'h8; //0x08: DMA_LEN
    cpu_wdata = 32'd3;
    cpu_wr_en = 1;
    #20 cpu_wr_en = 0;


    // start DMA + IRQ enable:(CONTROL REG)
    
// bit0 = start / enable DMA
//bit1 = circular mode: DMA would not stop after finishing the transfer length. Instead it would restart from the same address again.
//bit2 = interrupt enable
    cpu_addr  = 4'h0; //0X00: DMA_CTRL
    cpu_wdata = 32'b101; //cpu_wdata = 00000005
    cpu_wr_en = 1;
    #20 cpu_wr_en = 0;

    //////////////////////////////////
    // SEND UART DATA
    //////////////////////////////////

    #1000;

    send_uart_byte(8'h55);//call this task-> to simulate external device sending serial data to uart
    send_uart_byte(8'hA3);
    send_uart_byte(8'h0F);

    //////////////////////////////////
    // WAIT FOR DMA to finish writing to RAM
    //////////////////////////////////

    wait(dma_irq == 1);

    $display("DMA interrupt received");

    //////////////////////////////////
    // READ RAM + CHECK
    //////////////////////////////////

    #100;

    for(i=0;i<3;i=i+1) begin

        cpu_ram_addr = i;
        cpu_ram_re = 1;
        #20;
        cpu_ram_re = 0;

        if(cpu_ram_rdata !== expected_data[i]) begin
            $display("ERROR: RAM[%0d] = %h expected %h",
                     i, cpu_ram_rdata, expected_data[i]);
            $fatal("TEST FAILED");
        end
        else begin
            $display("PASS: RAM[%0d] = %h",
                     i, cpu_ram_rdata);
        end

    end

    //////////////////////////////////
    // SUCCESS
    //////////////////////////////////

    $display("===========================");
    $display("UART DMA TEST PASSED");
    $display("===========================");

    #100;
    $finish;

end

endmodule