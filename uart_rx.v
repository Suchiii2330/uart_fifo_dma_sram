`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/20/2026 05:36:35 PM
// Design Name: 
// Module Name: uart_rx
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module synchronizer(
    input clk,reset,rx_in,
    output rx_sync
    );
 
reg ff1, ff2;

always @(posedge clk) begin
    if (reset) begin
        ff1 <= 1'b1;   // line idle = high
        ff2 <= 1'b1;
    end else begin
        ff1 <= rx_in;
        ff2 <= ff1;
    end
end

assign rx_sync = ff2;
endmodule 

module baud_gen_16x (
    input  wire        clk,           // System clock (e.g., 1 MHz)
    input  wire        reset,         // Active-high synchronous reset
    input  wire [15:0] baud_div_16x,  // Divider value for 16× baud
    output reg         tick_16x       // 1-cycle pulse output
);

    reg [15:0] count;  // Counts clock cycles

    always @(posedge clk) begin
        if (reset) begin
            count    <= 16'd0;
            tick_16x <= 1'b0;
        end
        else begin
            // Check if required number of cycles completed
            if (count == baud_div_16x - 1) begin
                count    <= 16'd0;   // Restart counting
                tick_16x <= 1'b1;    // Generate pulse/bell for ONE clock, indicating that one slave cycle of 325 cycles is over
            end
            else begin
                count    <= count + 1'b1; // Keep counting upto 325
                tick_16x <= 1'b0;         // No pulse
            end
        end
    end

endmodule

module oversample_counter (
    input  wire clk,
    input  wire reset,
    input  wire tick_16x,     // from baud generator
    output reg  [3:0] os_cnt  // 0-15
);

always @(posedge clk) begin
    if (reset) begin
        os_cnt <= 4'd0;
    end
    else if (tick_16x) begin
        if (os_cnt == 4'd15)
            os_cnt <= 4'd0;
        else
            os_cnt <= os_cnt + 1'b1;
    end
end
endmodule

module bit_counter (
    input  wire clk,
    input  wire reset,
    input  wire tick_16x,
    input  wire [3:0] os_cnt,
    input  wire enable,      // count only in DATA state

    output reg  [2:0] bit_cnt, // 0-7
    output wire done          // HIGH after 8 bits
);

always @(posedge clk) begin
    if (reset)
        bit_cnt <= 3'd0;

else if (!enable)
        bit_cnt <= 3'd0;
        
    else if (enable &&
             tick_16x &&
             os_cnt == 4'd8) begin   
        bit_cnt <= bit_cnt + 1'b1;
    end
end

assign done = (bit_cnt == 3'd7);

endmodule


module uart_rx_fsm (
    input  wire clk,
    input  wire reset,
    input  wire rx_sync,
    input  wire tick_16x,
    input  wire [3:0] os_cnt,
    input  wire done,        // 8 data bits received

    output reg  enable_data,
    output reg  data_valid,
    output reg  frame_error,
    output reg  busy,
    output reg  clear_shift
);

//-----------------------------------------
// State Encoding
//-----------------------------------------

localparam IDLE  = 3'd0;
localparam START = 3'd1;
localparam DATA  = 3'd2;
localparam STOP  = 3'd3;
localparam DONE  = 3'd4;
localparam ERROR = 3'd5;

reg [2:0] state, next_state;


//-----------------------------------------
// STATE REGISTER
//-----------------------------------------

always @(posedge clk) begin
    if (reset)
        state <= IDLE;
    else
        state <= next_state;
end


//-----------------------------------------
// NEXT STATE LOGIC
//-----------------------------------------

always @(*) begin
    next_state = state;

    case (state)

        //---------------------------------
        IDLE: begin
            if (rx_sync == 1'b0)     // start bit detected
                next_state = START;
        end

        //---------------------------------
        START: begin
            // Sample center of start bit
            if (tick_16x && os_cnt == 4'd8) begin
                if (rx_sync == 1'b0)
                    next_state = DATA;   // valid start
                else
                    next_state = IDLE;   // noise
            end
        end

        //---------------------------------
        DATA: begin
            if (done)
                next_state = STOP;
        end

        //---------------------------------
        STOP: begin
            if (tick_16x && os_cnt == 4'd8) begin
                if (rx_sync == 1'b1)
                    next_state = DONE;   // valid frame
                else
                    next_state = ERROR;  // stop bit wrong
            end
        end

        //---------------------------------
        DONE: begin
            next_state = IDLE;
        end

        //---------------------------------
        ERROR: begin
            next_state = IDLE;
        end

    endcase
end


//-----------------------------------------
// OUTPUT LOGIC
//-----------------------------------------

always @(posedge clk) begin
    if (reset) begin
        enable_data <= 1'b0;
        data_valid  <= 1'b0;
        frame_error <= 1'b0;
        busy        <= 1'b0;
        clear_shift <= 1'b0;
    end
    else begin

        // reciever is busy 
        busy <= (state != IDLE);

        // Enable data capture only in DATA state
        enable_data <= (state == DATA);

        // clear shift register when DATA state begins
        clear_shift <= (state == START && next_state == DATA);

        // DONE state → valid byte
        if (state == DONE)
            data_valid <= 1'b1;
        else
            data_valid <= 1'b0;

        // ERROR state → frame error
        if (state == ERROR)
            frame_error <= 1'b1;
        else
            frame_error <= 1'b0;

    end
end
endmodule

module shift_register (
    input  wire clk,
    input  wire reset,
    input  wire tick_16x,
    input  wire [3:0] os_cnt,
    input  wire enable,
    input  wire rx_sync,
    input wire clear,

    output reg [7:0] data_out
);

always @(posedge clk) begin
    if (reset || clear)
        data_out <= 8'd0;

    else if (enable &&
             tick_16x &&
             os_cnt == 4'd7) begin

        // Shift right, new bit enters MSB
        data_out <= {data_out[6:0], rx_sync};
    end
end
endmodule

module fifo_sync #(
    parameter DATA_WIDTH = 8,   // Each element size (UART byte)
    parameter DEPTH = 16        // Number of elements FIFO can store
)(
    input  wire                  clk,
    input  wire                  reset,

    // WRITE SIDE (from UART RX core)
    input  wire                  wr_en,     // Write request
    input  wire [DATA_WIDTH-1:0] wr_data,   // Data to store

    // READ SIDE (to register interface / CPU)
    input  wire                  rd_en,     // Read request
    output reg  [DATA_WIDTH-1:0] rd_data,   // Data output

    // STATUS FLAGS
    output wire                  full,
    output wire                  empty,
    output reg                   overflow    // Set if write attempted when full
);


// ============================================================
// MEMORY ARRAY
// ============================================================
// mem[i] is one DATA_WIDTH-bit storage location
// NOT wires to all elements - real storage cells

reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];


// ============================================================
// POINTERS
// ============================================================
// wr_ptr → index where NEXT write will go
// rd_ptr → index of CURRENT element to read

reg [$clog2(DEPTH)-1:0] wr_ptr;
reg [$clog2(DEPTH)-1:0] rd_ptr;


// ============================================================
// COUNT - number of valid elements currently stored
// Range: 0 → DEPTH
// Needs extra bit to represent DEPTH itself
// ============================================================

reg [$clog2(DEPTH):0] count;


// ============================================================
// STATUS FLAGS
// ============================================================

assign full  = (count == DEPTH);  // FIFO cannot accept more data
assign empty = (count == 0);      // No data available


// ============================================================
// WRITE LOGIC (UART RX pushes data here)
// ============================================================

always @(posedge clk) begin
    if (reset) begin
        wr_ptr   <= 0;
        overflow <= 1'b0;
    end

    else begin

        // ----------------------------------------
        // NORMAL WRITE (if not full)
        // ----------------------------------------
        if (wr_en && !full) begin
            mem[wr_ptr] <= wr_data;   // Store data at current write index
            wr_ptr <= wr_ptr + 1;     // Move to next location
            overflow <= 1'b0;         // No overflow
        end

        // ----------------------------------------
        // OVERFLOW CONDITION
        // ----------------------------------------
        else if (wr_en && full) begin
            overflow <= 1'b1;         // Write attempted but FIFO full
            // Data is DROPPED (not stored)
        end

        else begin
            overflow <= 1'b0;         // No write → no overflow pulse
        end
    end
end


// ============================================================
// READ LOGIC (CPU / register block consumes data)
// ============================================================

always @(posedge clk) begin
    if (reset) begin
        rd_ptr  <= 0;
        rd_data <= 0;
    end

    else if (rd_en && !empty) begin
        rd_data <= mem[rd_ptr];   // Output current front element
        rd_ptr  <= rd_ptr + 1;    // Move to next element (POP)
    end
end


// ============================================================
// COUNT UPDATE (tracks FIFO occupancy)
// ============================================================

always @(posedge clk) begin
    if (reset)
        count <= 0;

    else begin
        case ({wr_en && !full, rd_en && !empty})

            2'b10: count <= count + 1;   // Write only
            2'b01: count <= count - 1;   // Read only
            2'b11: count <= count;       // Simultaneous write & read
            default: count <= count;     // No operation

        endcase
    end
end
endmodule


module uart_rx_regs (
    input  wire        clk,
    input  wire        reset,

    // ===============================
    // SIMPLE BUS INTERFACE (CPU SIDE)
    // ===============================

    input  wire [3:0]  addr,    // Address selecting which register
    input  wire        wr_en,   // Write enable (CPU writing)
    input  wire        rd_en,   // Read enable  (CPU reading)
    input  wire [31:0] wdata,   // Data from CPU to peripheral
    output reg  [31:0] rdata,   // Data from peripheral to CPU


    // ===============================
    // FIFO INTERFACE (HARDWARE SIDE)
    // ===============================

    input  wire [7:0]  fifo_data_out,  // Byte at front of RX FIFO
    input  wire        fifo_empty,     // FIFO empty flag
    input  wire        fifo_full,      // FIFO full flag
    input  wire        fifo_overflow,  // FIFO overflow flag
    output reg         fifo_rd_en,     // Pop FIFO when reading DATA reg


    // ===============================
    // CONTROL OUTPUTS (to UART RX core)
    // ===============================

    output reg         rx_enable       // Enables/disables receiver
);


// ============================================================
// INTERNAL REGISTER STORAGE
// ============================================================

// CONTROL register storage (32-bit for bus compatibility)
// Only bit0 is used currently (RX enable)
reg [31:0] control_reg;


// ============================================================
// WRITE LOGIC - CPU writes to registers
// ============================================================

always @(posedge clk) begin
    if (reset) begin
        control_reg <= 32'd0;  // Clear configuration
        rx_enable   <= 1'b0;   // Receiver disabled after reset
    end

    // If CPU performs WRITE operation
    else if (wr_en) begin
        case (addr)

            // ----------------------------------------
            // ADDRESS 0x08 → CONTROL REGISTER
            // ----------------------------------------
            // CPU writes configuration here
            // bit0 = RX enable
            // other bits reserved for future
            4'h8: begin
                control_reg <= wdata;      // Store full value
                rx_enable   <= wdata[0];   // Use bit0 to control RX
            end

            // Other addresses ignored on write
            default: ;
        endcase
    end
end


// ============================================================
// READ LOGIC - CPU reads registers
// ============================================================

always @(*) begin
    rdata = 32'd0;  // Default output

    case (addr)

        // ----------------------------------------
        // ADDRESS 0x00 → DATA REGISTER
        // ----------------------------------------
        // Returns next received byte from FIFO
        // Upper 24 bits padded with zeros
        4'h0: rdata = {24'd0, fifo_data_out};


        // ----------------------------------------
        // ADDRESS 0x04 → STATUS REGISTER
        // ----------------------------------------
        // Provides FIFO state flags
        // bit0 = FIFO empty
        // bit1 = Data available (~empty)
        // bit2 = FIFO full
        // bit3 = Overflow occurred
        4'h4: rdata = {
            28'd0,
            fifo_overflow,   // bit3
            fifo_full,       // bit2
            ~fifo_empty,     // bit1 (data available)
            fifo_empty       // bit0
        };


        // ----------------------------------------
        // ADDRESS 0x08 → CONTROL REGISTER
        // ----------------------------------------
        // CPU can read back configuration
        4'h8: rdata = control_reg;


        // ----------------------------------------
        // Invalid address → return zero
        // ----------------------------------------
        default: rdata = 32'd0;

    endcase
end


// ============================================================
// FIFO READ CONTROL
// ============================================================
// Reading DATA register should pop FIFO (consume byte)

always @(posedge clk) begin
    if (reset)
        fifo_rd_en <= 1'b0;

    // If CPU reads DATA register AND FIFO not empty
    else if (rd_en && addr == 4'h0 && !fifo_empty)
        fifo_rd_en <= 1'b1;   // Pop FIFO for next byte

    else
        fifo_rd_en <= 1'b0;   // Pulse for one clock
end

endmodule

module uart_rx_dma_v2 (
    input  wire        clk,
    input  wire        reset,

    // =============================
    // SIMPLE BUS INTERFACE (CPU) : CPU configures DMA like memory-mapped registers
    //bus width is 32 bits. CPU writes registers in 32 bit chunks
    // =============================
    input  wire [3:0]  addr,    // which register
    input  wire        wr_en,  //CPU writing
    input  wire        rd_en, //CPU reading
    input  wire [31:0] wdata, //data from CPU
    output reg  [31:0] rdata,  // data back to CPU

    // =============================
    // FIFO SOURCE (UART RX)  : DMA reads byte from FIFO , hence FIFO is the source
    // =============================
    input  wire [7:0]  fifo_data_out,  //byte ready
    input  wire        fifo_empty,
    output reg         fifo_rd_en,    //DMA requests a POP 

    // =============================
    // MEMORY INTERFACE : DMA writes to RAM
    // =============================
    output reg  [31:0] mem_addr, //RAM address
    output reg  [7:0]  mem_wdata, // signals out of dma to memory system {RAM} : data to write
    output reg         mem_wr_en, // write enable

    // =============================
    // INTERRUPT OUTPUT : DMA signals CPU that transfer to RAM has been done
    // =============================
    output reg         dma_irq
);
// Control & status registers of DMA
// CONTROL REGISTER:
// bit0 = start/enable  DMA 
// bit1 = circular mode
// bit2 = interrupt enable

reg [31:0] ctrl_reg;

// Destination address register: stores destination address(RAM)
reg [31:0] addr_reg;

// Transfer length register
reg [15:0] len_reg; //how many bytes to be transferred FIFO → RAM

// STATUS flags
reg busy;
reg done;
// CPU WRITE-> REGISTERS LOGIC
always @(posedge clk) begin
    if (reset) begin
        ctrl_reg <= 0;
        addr_reg <= 0;
        len_reg  <= 0;
    end
    else if (wr_en) begin
        case (addr)
       //non blocking as writes in all the 3 registers together
       //WRITE block → sequential → use <=
            4'h0: ctrl_reg <= wdata;        // DMA_CTRL
            4'h4: addr_reg <= wdata;        // DMA_ADDR
            4'h8: len_reg  <= wdata[15:0];  // DMA_LEN

        endcase
    end
end
// CPU READ FROM REGISTER LOGIC
always @(*) begin
    case (addr)
     //blocking as finshes reading one, then reads another
     //READ block → combinational → use =
        4'h0: rdata = ctrl_reg;
        4'h4: rdata = addr_reg;
        4'h8: rdata = {16'd0, len_reg};
        4'hC: rdata = {30'd0, done, busy}; //last 2 bits show status, upper bits 0

        default: rdata = 32'd0;

    endcase
end
// DMA DATA PATH
reg [15:0] count; // how many bytes have been already transferred
reg [31:0] cur_addr; //which current address of RAM is being written. Starts at addr_reg then increments

// pipeline register because FIFO data becomes valid
// one clock AFTER fifo_rd_en
reg fifo_valid;

always @(posedge clk) begin
    if (reset) begin
        busy <= 0;
        done <= 0;
        
        fifo_rd_en <= 0;
        fifo_valid <= 0;

        mem_wr_en  <= 0;
        dma_irq    <= 0;
        mem_wr_en  <= 0;
        
        count <= 0;
        cur_addr <= 0;
    end

    // START CONDITION
    else if (ctrl_reg[0] && !busy && len_reg != 0 && !done) begin
        busy     <= 1;
        done     <= 0;
        
        count    <= 0;
        dma_irq  <=0;
        cur_addr <= addr_reg;
          fifo_valid <= 0;
    end

    //--------------------------------------------------
    // ACTIVE DMA TRANSFER
    //--------------------------------------------------

    else if (busy) begin

        // request data from FIFO
        if (!fifo_empty && count < len_reg)
            fifo_rd_en <= 1;
        else
            fifo_rd_en <= 0;

        // pipeline stage
        // FIFO output becomes valid next cycle
        fifo_valid <= fifo_rd_en;


        // when data becomes valid -> write RAM
        if (fifo_valid) begin

            mem_wdata <= fifo_data_out;
            mem_addr  <= cur_addr;
            mem_wr_en <= 1;

            cur_addr <= cur_addr + 1;
            count    <= count + 1;

        end
        else begin
            mem_wr_en <= 0;
        end


        //--------------------------------------------------
        // TRANSFER COMPLETE
        //--------------------------------------------------

        if (count == len_reg-1  && fifo_valid) begin
//last valid transfer happens when count = len_reg-1.
            if (ctrl_reg[1]) begin

                // circular mode ON
                count    <= 0;
                cur_addr <= addr_reg;

            end
            else begin

                busy <= 0;
                done <= 1;

                if (ctrl_reg[2])
                    dma_irq <= 1;

            end
        end

    end
end

endmodule

module sram_tdp_wf #( 

    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 8
)(
    input  wire                    clk,

    // ============================
    // PORT A (CPU)
    // ============================
    input  wire                    we_a,
    input  wire                    re_a,
    input  wire [ADDR_WIDTH-1:0]   addr_a,
    input  wire [DATA_WIDTH-1:0]   wdata_a,
    output reg  [DATA_WIDTH-1:0]   rdata_a,

    // ============================
    // PORT B (DMA)
    // ============================
    input  wire                    we_b,
    input  wire                    re_b,
    input  wire [ADDR_WIDTH-1:0]   addr_b,
    input  wire [DATA_WIDTH-1:0]   wdata_b,
    output reg  [DATA_WIDTH-1:0]   rdata_b
);

    // ======================================================
    // MEMORY ARRAY
    // ======================================================

    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];


    // ======================================================
    // WRITE OPERATIONS (both ports)
    // ======================================================

    always @(posedge clk) begin
        if (we_a)
            mem[addr_a] <= wdata_a;

        if (we_b)
            mem[addr_b] <= wdata_b;
    end


    // ======================================================
    // READ OPERATIONS - WRITE-FIRST POLICY
    // ======================================================

    always @(posedge clk) begin

    // PORT A READ
    if (re_a) begin
        if (we_a)
            rdata_a <= wdata_a;                  // own write
//CPU writes AND reads same address simultaneously:wont be used in this project
//only DMA will write and CPU will read from RAM
            
        else if (we_b && (addr_a == addr_b))
        //if cpu is reading the same address dma is writing
        
            rdata_a <= wdata_b;                  // other port write
        else
            rdata_a <= mem[addr_a];              // normal read
    end


    // PORT B READ
    if (re_b) begin
    //dma only writes, not used
        if (we_b)
            rdata_b <= wdata_b;
        else if (we_a && (addr_b == addr_a))
        // if dma is writing at same address cpu is reading
            rdata_b <= wdata_a;
        else
            rdata_b <= mem[addr_b]; //normal read
    end

end
endmodule
