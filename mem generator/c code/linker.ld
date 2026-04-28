OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
  DMEM (rwx) : ORIGIN = 0x20000000, LENGTH = 4K
}

SECTIONS
{
  .text : ALIGN(4)
  {
    KEEP(*(.init))
    *(.text*)
  } > IMEM

  .dmem_init : ALIGN(4)
  {
    __dmem_init_start = .;
    *(.rodata*)
    *(.data*)
    *(.sdata*)
    __dmem_init_end = .;
  } > DMEM

  .bss (NOLOAD) : ALIGN(4)
  {
    __bss_start = .;
    *(.bss*)
    *(COMMON)
    *(.sbss*)
    __bss_end = .;
  } > DMEM

  . = ALIGN(16);
  __stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
}
