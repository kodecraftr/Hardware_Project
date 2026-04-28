param(
    [string]$Source = "template_main.c",
    [string]$OutBase = "c_prog",
    [switch]$InstallActive,
    [string]$ActiveImem = "..\\..\\modules\\memory\\imem.hex",
    [string]$ActiveDmem = "..\\..\\modules\\memory\\dmem.hex"
)

$ErrorActionPreference = "Stop"

function Resolve-Tool([string]$toolName) {
    $overrideRoot = $env:RISCV_GNU_TOOLCHAIN
    if ($overrideRoot) {
        $candidates = @(
            (Join-Path $overrideRoot "$toolName.exe"),
            (Join-Path (Join-Path $overrideRoot "bin") "$toolName.exe")
        )
        foreach ($candidate in $candidates) {
            if (Test-Path $candidate) {
                return $candidate
            }
        }
    }

    $cmd = Get-Command $toolName -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    throw "Could not find $toolName. Add it to PATH or set RISCV_GNU_TOOLCHAIN to the toolchain folder."
}

$gcc = Resolve-Tool "riscv-none-elf-gcc"
$objcopy = Resolve-Tool "riscv-none-elf-objcopy"
$size = Resolve-Tool "riscv-none-elf-size"

$python = Get-Command python -ErrorAction SilentlyContinue
if (!$python) {
    throw "Could not find python. Install Python 3 and add it to PATH."
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
& $python.Source $hexPy $imemBin $imemHex 1024
& $python.Source $hexPy $dmemBin $dmemHex 1024

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
