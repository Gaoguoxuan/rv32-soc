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

    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
    .stack_guard __stack_top - 0x1000 (NOLOAD) : { KEEP(*(.stack_guard)) } > RAM
    __stack_bottom = ADDR(.stack_guard) + SIZEOF(.stack_guard);
    ASSERT(__bss_end <= ADDR(.stack_guard), "ERROR: BSS overlaps stack guard")
    ASSERT(SIZEOF(.stack_guard) == 16, "ERROR: expected four stack guard words")
    ASSERT((__stack_bottom & 15) == 0 && (__stack_top & 15) == 0,
           "ERROR: stack must be 16-byte aligned")
}
