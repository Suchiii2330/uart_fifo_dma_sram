# uart_fifo_dma_sram
UART RX → FIFO → DMA → SRAM System
Overview

This project implements a complete UART receive data path with hardware DMA, designed in Verilog.
Incoming UART data is captured, buffered in a FIFO, and automatically transferred to memory using a DMA engine.

The design demonstrates a typical embedded hardware data pipeline used in SoCs and microcontrollers.

UART RX → FIFO → DMA → Dual-Port SRAM

The CPU only configures registers.
Data movement happens fully in hardware without CPU intervention.

System Architecture
RX line -> UART RX(16X oversampling) -> FIFO BUFFER -> DMA ENGINE -> DUAL PORT SRAM


CPU Interface → Register Block
 Features
 
1.UART Receiver
->16× oversampling receiver
->Start/stop bit validation
->Frame error detection
->Bit counter + oversample counter
->Shift register assembly
->Synchronizer for metastability protection

2.FIFO Buffer
->Parameterized synchronous FIFO
->Configurable depth
->Overflow detection
->Separate read/write control

3.DMA Engine

Hardware-controlled transfer:
FIFO → SRAM

Features:

->Memory-mapped configuration registers
->Automatic burst transfers
->Configurable transfer length
->Interrupt generation on completion
->Optional circular mode support

Dual-Port SRAM
->True dual-port memory
->CPU access on Port A
->DMA writes on Port B
->Write-first behavior

CPU Register Interface
Address 	Register	        Description
0x00	    DMA_CTRL	        Control bits
0x04	    DMA_ADDR         	Destination memory address
0x08	    DMA_LEN	          Number of bytes to transfer
0x0C	    DMA_STATUS	      Busy / Done flags

Control bits:
bit0 → DMA start
bit1 → Circular mode
bit2 → Interrupt enable


Key Design Blocks

Synchronizer
Prevents metastability when sampling the asynchronous RX input.

Baud Generator
Produces the 16× oversampling tick used for precise UART sampling.

UART FSM
Handles:
IDLE
START
DATA
STOP
DONE
ERROR


FIFO
Buffers received bytes so DMA can read asynchronously.

DMA Controller
Handles:
FIFO read
Memory write
Address increment
Transfer completion
Interrupt generation


Simulation

The design was verified using a SystemVerilog testbench.
Simulation demonstrates:
UART frame reception
Byte assembly
FIFO buffering
DMA memory transfer
Memory updates

Example data flow observed in simulation:
UART RX byte
→ FIFO write
→ DMA read
→ SRAM write

Simulation runtime: 5 ms

Waveforms confirm correct operation of:

UART RX
FIFO write/read
DMA transfers
SRAM updates


Example Data Path
UART Frame
   ↓
Shift Register
   ↓
  FIFO
   ↓
  DMA
   ↓
  SRAM

Result:
Memory[addr]= received UART byte

---------------------------------------------------------------------------

This project taught me practical RTL concepts:

UART protocol implementation
Clock domain synchronization
FIFO buffering
DMA architecture
Memory-mapped register interfaces
Hardware data pipelines

Tools Used
Vivado Simulator
Verilog / SystemVerilog
Waveform debugging with Vivado

