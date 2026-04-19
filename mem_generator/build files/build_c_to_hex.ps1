param(
    [string]$Source = "template_main.c",
    [string]$OutBase = "c_prog",
    [switch]$InstallActive,
    [string]$ActiveImem = "..\\..\\modules\\memory\\imem.hex",
    [string]$ActiveDmem = "..\\..\\modules\\memory\\dmem.hex"
)

$ErrorActionPreference = "Stop"

$toolRoot = "C:\Users\pranj\AppData\Roaming\xPacks\@xpack-dev-tools\riscv-none-elf-gcc\15.2.0-1.1\.content\bin"
$gcc = Join-Path $toolRoot "riscv-none-elf-gcc.exe"
$objcopy = Join-Path $toolRoot "riscv-none-elf-objcopy.exe"
$size = Join-Path $toolRoot "riscv-none-elf-size.exe"

if (!(Test-Path $gcc)) {
    throw "RISC-V GCC not found at $gcc"
}
if (!(Test-Path $objcopy)) {
    throw "RISC-V objcopy not found at $objcopy"
}

$srcDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Split-Path -Parent $srcDir
$codeDir = Join-Path $projectDir "c code"
$hexDir = Join-Path $projectDir "hex files"

$sourcePath = Join-Path $codeDir $Source
$crt0 = Join-Path $codeDir "crt0.S"
$io = Join-Path $codeDir "soc_io.c"
$linker = Join-Path $codeDir "linker.ld"
$hexPy = Join-Path $srcDir "bin_to_word_hex.py"

$elf = Join-Path $hexDir "$OutBase.elf"
$imemBin = Join-Path $hexDir "$OutBase.imem.bin"
$dmemBin = Join-Path $hexDir "$OutBase.dmem.bin"
$imemHex = Join-Path $hexDir "$OutBase.imem.hex"
$dmemHex = Join-Path $hexDir "$OutBase.dmem.hex"
$activeImemPath = Join-Path $srcDir $ActiveImem
$activeDmemPath = Join-Path $srcDir $ActiveDmem
$legacyImemPath = Join-Path $hexDir "imem_latest.hex"
$legacyDmemPath = Join-Path $hexDir "dmem_latest.hex"

$gccArgs = @(
  "-march=rv32im",
  "-mabi=ilp32",
  "-ffreestanding",
  "-nostdlib",
  "-nostartfiles",
  "-Os",
  "-Wl,-T,$linker",
  "-Wl,--gc-sections",
  "-o", $elf,
  $crt0,
  $io,
  $sourcePath
)

& $gcc @gccArgs

& $size $elf
& $objcopy -O binary --only-section=.text $elf $imemBin
& $objcopy -O binary --only-section=.dmem_init $elf $dmemBin
python $hexPy $imemBin $imemHex 1024
python $hexPy $dmemBin $dmemHex 1024

if ($InstallActive) {
    Copy-Item $imemHex $activeImemPath -Force
    Copy-Item $dmemHex $activeDmemPath -Force
    Copy-Item $imemHex $legacyImemPath -Force
    Copy-Item $dmemHex $legacyDmemPath -Force
}

Write-Host "Generated:"
Write-Host "  ELF : $elf"
Write-Host "  IMEM BIN : $imemBin"
Write-Host "  DMEM BIN : $dmemBin"
Write-Host "  IMEM HEX : $imemHex"
Write-Host "  DMEM HEX : $dmemHex"
if ($InstallActive) {
    Write-Host "Installed active FPGA images:"
    Write-Host "  ACTIVE IMEM : $activeImemPath"
    Write-Host "  ACTIVE DMEM : $activeDmemPath"
    Write-Host "  MIRROR IMEM : $legacyImemPath"
    Write-Host "  MIRROR DMEM : $legacyDmemPath"
}
