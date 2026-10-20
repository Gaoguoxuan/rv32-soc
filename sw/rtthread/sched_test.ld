OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 64K
}

SECTIONS
{
    .text :
    {
        KEEP(*(.text.start))
        *(.text*)
    } > ROM
    .rodata :
    {
        . = ALIGN(4);
        KEEP(*(.rodata.thread_locations))
        *(.rodata*)
        *(.srodata*)
        . = ALIGN(4);
    } > ROM
    .data :
    {
        . = ALIGN(4);
        __data_start = .;
        *(.data*)
        *(.sdata*)
        . = ALIGN(4);
        __data_end = .;
    } > RAM AT> ROM
    __data_load_start = LOADADDR(.data);
    .bss (NOLOAD) :
    {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM

    .thread_stack_a ORIGIN(RAM) + 0x8000 (NOLOAD) : { KEEP(*(.thread_stack_a)) } > RAM
    .thread_stack_b ORIGIN(RAM) + 0x9000 (NOLOAD) : { KEEP(*(.thread_stack_b)) } > RAM
    .thread_stack_check ORIGIN(RAM) + 0xa000 (NOLOAD) : { KEEP(*(.thread_stack_check)) } > RAM
    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
    .stack_guard __stack_top - 0x1000 (NOLOAD) : { KEEP(*(.stack_guard)) } > RAM
    __stack_bottom = ADDR(.stack_guard) + SIZEOF(.stack_guard);
    ASSERT(__bss_end <= ADDR(.thread_stack_a), "ERROR: BSS overlaps thread stacks")
    ASSERT(SIZEOF(.thread_stack_a) == 2048 && SIZEOF(.thread_stack_b) == 2048 &&
           SIZEOF(.thread_stack_check) == 2048, "ERROR: expected three 2 KiB thread stacks")
    ASSERT(ADDR(.thread_stack_a) + SIZEOF(.thread_stack_a) <= ADDR(.thread_stack_b) &&
           ADDR(.thread_stack_b) + SIZEOF(.thread_stack_b) <= ADDR(.thread_stack_check) &&
           ADDR(.thread_stack_check) + SIZEOF(.thread_stack_check) <= ADDR(.stack_guard),
           "ERROR: stacks overlap")
    ASSERT(SIZEOF(.stack_guard) == 16, "ERROR: expected four main stack guard words")
    ASSERT((__stack_bottom & 15) == 0 && (__stack_top & 15) == 0,
           "ERROR: main stack alignment")
}
