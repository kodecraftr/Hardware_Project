# Final Project Setup Guide

This folder is a self-contained submission copy of the FPGA project.

It includes:

- Verilog source files in `modules`
- memory files in `modules\memory`
- the DFA accelerator in `modules\accelerator`
- C build flow in `mem generator`
- a prebuilt bitstream: `fpga_top.bit`

## What this project does

The FPGA runs a UART-based calculator demo.

Expected serial output after reset:

```text
CALC READY
CALC>
```

Example:

```text
12*3
=36
```

## Required setup

- A Windows PC
- Xilinx Vivado with Artix-7 support
- A Digilent Nexys A7-100T board
- A USB cable
- PuTTY or any serial terminal

## Important details

- Top module: `fpga_top`
- FPGA part: `xc7a100tcsg324-1`
- UART: `115200`, `8N1`, no flow control
- Reset button signal: `CPU_RESETN`

## Files included in this folder

- `fpga_top.bit`
- `README.md`
- `modules\fpga_top.v`
- `modules\constraints.xdc`
- `modules\memory\imem.hex`
- `modules\memory\dmem.hex`
- `modules\accelerator\dfa_accelerator.v`
- `mem generator\build files\build_c_to_hex.ps1`
- `mem generator\c code\*.c`

## Fastest way to run the project

If you only want to run the design on hardware:

1. Open Vivado.
2. Open `Hardware Manager`.
3. Connect the Nexys A7-100T board.
4. Click `Open Target` > `Auto Connect`.
5. Click `Program Device`.
6. Select `fpga_top.bit`.
7. Open PuTTY on the board COM port at `115200`.
8. Press the reset button.

## If you want to rebuild the bitstream in Vivado

This folder does not include a `.xpr` project file. To rebuild:

1. Create a new Vivado RTL project.
2. Select part `xc7a100tcsg324-1`.
3. Choose `Do not specify sources at this time` or add the files immediately.
4. After the project opens, add the design sources listed below.
5. Add the constraints file `modules\constraints.xdc`.
6. Set the top module to `fpga_top`.
7. Make sure the memory files remain available in the project working area.
8. Run synthesis, implementation, and bitstream generation.

## Design sources to add in Vivado

Add these Verilog files as design sources:

- `modules\fpga_top.v`
- `modules\bus\bus.v`
- `modules\cpu core\IF_ID.v`
- `modules\cpu core\div_module.v`
- `modules\cpu core\execute.v`
- `modules\cpu core\mul_module.v`
- `modules\cpu core\opcode.vh`
- `modules\cpu core\pipeline.v`
- `modules\cpu core\wb.v`
- `modules\memory\memory.v`
- `modules\soc\soc_top.v`
- `modules\uart\uart_peripheral.v`
- `modules\uart\uart_rx.v`
- `modules\uart\uart_tx.v`

Also include this extra module in the submission:

- `modules\accelerator\dfa_accelerator.v`

The DFA accelerator is included as part of the submitted design files even though the current `fpga_top` hardware demo runs the UART calculator flow.

## Memory files to keep with the Vivado project

These files are required by `memory.v`:

- `modules\memory\imem.hex`
- `modules\memory\dmem.hex`

If these files are missing from the project directory when Vivado builds the design, memory initialization may fail.

## Constraints file

Add this constraints file:

- `modules\constraints.xdc`

Then set the top module to:

- `fpga_top`

## Exact Vivado flow

1. Open Vivado.
2. Create a new RTL project.
3. Select FPGA part `xc7a100tcsg324-1`.
4. Add all design source files listed above.
5. Add `modules\constraints.xdc`.
6. Set top module to `fpga_top`.
7. Click `Generate Bitstream`.
8. If Vivado asks to run synthesis and implementation first, click `Yes`.
9. Wait until bitstream generation finishes.
10. Open `Hardware Manager`.
11. Click `Open Target` > `Auto Connect`.
12. Select the connected Nexys A7-100T board.
13. Click `Program Device`.
14. Program the generated bitstream.

## How to find the COM port

1. Open `Device Manager`
2. Expand `Ports (COM & LPT)`
3. Find the board serial port

It may appear as:

- `USB Serial Device (COMx)`
- `Digilent USB Device (COMx)`

## How to open PuTTY

1. Open PuTTY
2. Select `Serial`
3. Set the serial line to your board COM port
4. Set speed to `115200`
5. Keep `8N1` and no flow control
6. Open the connection

Then press reset on the board.

## How to test the programmed FPGA

After programming the FPGA and opening PuTTY:

1. Press the reset button on the board.
2. Wait for the UART banner.
3. Type an expression and press Enter.

Example:

```text
12*3
=36
```

Other examples:

```text
7+8
=15

10/0
DIV BY ZERO
```

## Building your own C program

Example programs are in:

`mem generator\c code`

Available packaged examples include:

- `calc_main.c`
- `arith_demo_main.c`
- `times9_main.c`
- `template_main.c`
- `echo_main.c`
- `fib_main.c`
- `prime_main.c`

### Dependencies

- Python 3 in `PATH`
- `riscv-none-elf-gcc` toolchain in `PATH`

The build script also supports `RISCV_GNU_TOOLCHAIN` if the toolchain is not in `PATH`.

### Build command

From this `final project` folder, run:

```powershell
powershell -ExecutionPolicy Bypass -File ".\mem generator\build files\build_c_to_hex.ps1" -Source "calc_main.c" -OutBase "final_calc" -InstallActive
```

You can replace `calc_main.c` with another C file from `mem generator\c code`.

### What the build updates

The build script compiles the selected program and updates:

- `modules\memory\imem.hex`
- `modules\memory\dmem.hex`

After that:

1. Rebuild the bitstream in Vivado, or
2. If you already have a Vivado project open, rerun synthesis/implementation and program the FPGA again.

## Summary

This folder now contains the files needed to:

- program the FPGA directly using `fpga_top.bit`
- rebuild the project manually in Vivado
- compile and install a new C program into the memory images
- submit the full design source set, including the DFA accelerator
