# FPGA Project Setup Guide

This project is a RISC-V SoC implemented on FPGA with UART-based interaction.

The uploaded project already includes the Vivado project, source files, constraints, memory files, and a generated bitstream. You should not need to rebuild `imem.hex` or `dmem.hex` to run the default demo.

## What this project is expected to do

When programmed on the FPGA, the board runs a UART-based expression calculator.

Expected serial output after reset:

```text
EXPR CALC READY
Supports + - * / % and ()
EXPR>
```

Example:

```text
2+3*4
=14
```

## Required setup

You will need:

- A Windows PC
- Xilinx Vivado with Artix-7 support installed
- A Digilent Nexys A7-100T board
- A USB cable for the board
- PuTTY or any serial terminal

## Important project details

- Vivado project file: `projectfinal.xpr`
- Top module: `fpga_top`
- FPGA part: `xc7a100tcsg324-1`
- Board constraints match: `Nexys A7-100T`
- UART setting: `115200 baud, 8 data bits, no parity, 1 stop bit`
- Reset button: `CPU_RESETN` on pin `C12`

## Will it work on another computer?

Yes, it should work if these conditions are met:

- The zip is fully extracted before opening the project
- Vivado has support for Artix-7 devices
- A `Nexys A7-100T` board is used
- The board USB/JTAG and USB-UART drivers are available

Possible problems:

- If a different FPGA board is used, the constraints will not match.
- If Vivado opens the project in a different version, it may ask to upgrade the project.
- If the zip is opened without extracting, Vivado may fail to find source or memory files.

## Steps to run the project

### 1. Extract the zip

Download the GitHub zip and extract the full folder to the computer.

Do not run Vivado directly from inside the zip.

### 2. Open the project in Vivado

Open Vivado, then open:

`projectfinal.xpr`

This project already points to the correct top module and includes:

- Verilog source files
- `constraints.xdc`
- `imem.hex`
- `dmem.hex`

### 3. Generate the bitstream

In Vivado:

1. Open the project.
2. In the left panel, click `Generate Bitstream`.
3. If Vivado asks to run synthesis and implementation first, click `Yes`.
4. Wait for synthesis, implementation, and bitstream generation to finish.

There is also already a generated bitstream in:

`projectfinal.runs\impl_1\fpga_top.bit`

So even if you do not want to rebuild from scratch, the bitstream is present in the project folder.

### 4. Connect and program the board

1. Connect the Nexys A7-100T board to the PC with USB.
2. Power on the board.
3. In Vivado, open `Hardware Manager`.
4. Click `Open Target` > `Auto Connect`.
5. Select the detected FPGA device.
6. Click `Program Device`.
7. Choose the generated bitstream if Vivado asks for it.

After programming, the design is loaded onto the FPGA.

### 5. Install PuTTY if needed

If PuTTY is not installed, download it from the official site:

[PuTTY download](https://www.putty.org/)

Install it with default options.

### 6. Find the correct COM port

On Windows:

1. Open `Device Manager`
2. Expand `Ports (COM & LPT)`
3. Find the board serial port

It will appear as something like:

- `USB Serial Device (COMx)`
- `Digilent USB Device (COMx)`

Note the COM number.

### 7. Open the serial terminal in PuTTY

In PuTTY:

1. Select `Serial`
2. Set `Serial line` to the detected `COM` port
3. Set `Speed` to `115200`
4. Open the connection

Use standard serial format:

- `115200`
- `8N1`
- No flow control

### 8. Reset the FPGA design

After PuTTY is open, press the reset push-button connected to `CPU_RESETN`.

For this project, that reset signal is constrained to pin `C12`.

After pressing reset, the UART terminal should print the calculator banner and prompt.

## What to test

After reset, type an expression and press Enter.

Examples:

```text
7+8
=15

(9-2)*3
=21

10/0
DIV BY ZERO
```

If the prompt appears and expressions are evaluated correctly, the project is running properly.

## Important note about `imem.hex` and `dmem.hex`

The currently active memory files are already included in the Vivado project:

- `projectfinal.srcs\sources_1\new\imem.hex`
- `projectfinal.srcs\sources_1\new\dmem.hex`

These files currently correspond to the expression-calculator demo.

You do not need to modify them for normal evaluation.

## Short version

1. Extract the zip.
2. Open `projectfinal.xpr` in Vivado.
3. Click `Generate Bitstream`.
4. Open `Hardware Manager` and `Program Device`.
5. Open PuTTY on the board's `COM` port at `115200`.
6. Press the reset button.
7. Type an expression in PuTTY and check the result.
