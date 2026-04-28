SOURCE ?= calc_main.c
OUT ?= final_calc
PS_BUILD = powershell -ExecutionPolicy Bypass -File ".\mem generator\build files\build_c_to_hex.ps1"

.PHONY: help build install-active clean

help:
	@echo Usage:
	@echo   make build SOURCE=calc_main.c OUT=final_calc
	@echo   make install-active SOURCE=calc_main.c OUT=final_calc
	@echo   make clean
	@echo.
	@echo Defaults:
	@echo   SOURCE=$(SOURCE)
	@echo   OUT=$(OUT)

build:
	$(PS_BUILD) -Source "$(SOURCE)" -OutBase "$(OUT)"

install-active:
	$(PS_BUILD) -Source "$(SOURCE)" -OutBase "$(OUT)" -InstallActive

clean:
	@if exist ".\mem generator\hex files\*.elf" del /q ".\mem generator\hex files\*.elf"
	@if exist ".\mem generator\hex files\*.bin" del /q ".\mem generator\hex files\*.bin"
	@if exist ".\mem generator\hex files\*.hex" del /q ".\mem generator\hex files\*.hex"
