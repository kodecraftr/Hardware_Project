.section .init
.globl _start

_start:
    .option push
    .option norelax
    lui  sp, %hi(__stack_top)
    addi sp, sp, %lo(__stack_top)

    lui  t0, %hi(__bss_start)
    addi t0, t0, %lo(__bss_start)
    lui  t1, %hi(__bss_end)
    addi t1, t1, %lo(__bss_end)
    .option pop
1:
    bgeu t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b
2:
    call main
3:
    j    3b
