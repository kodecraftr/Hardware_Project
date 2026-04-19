SOURCE ?= calc_main.c
OUT ?= cprog
PS_BUILD = powershell -ExecutionPolicy Bypass -File "..\build files\build_c_to_hex.ps1"

.PHONY: help build install-active clean

help:
	@echo Usage:
	@echo   make build SOURCE=calc_main.c OUT=calc_demo
	@echo   make install-active SOURCE=calc_main.c OUT=calc_demo
	@echo   make clean
	@echo.
	@echo Generated files go to:
	@echo   ..\hex files
	@echo Active files copied to:
	@echo   ..\..\modules\memory\imem.hex
	@echo   ..\..\modules\memory\dmem.hex

build:
	$(PS_BUILD) -Source "$(SOURCE)" -OutBase "$(OUT)"

install-active:
	$(PS_BUILD) -Source "$(SOURCE)" -OutBase "$(OUT)" -InstallActive

clean:
	@if exist "..\hex files\*.elf" del /q "..\hex files\*.elf"
	@if exist "..\hex files\*.bin" del /q "..\hex files\*.bin"
	@if exist "..\hex files\*.hex" del /q "..\hex files\*.hex"
