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
        KEEP(*(.text.context))
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

    /* Per-thread stacks are initialized by thread_init, outside CRT BSS. */
    .stack_a ORIGIN(RAM) + 0x8000 (NOLOAD) : { KEEP(*(.stack_a)) } > RAM
    .stack_b ORIGIN(RAM) + 0x9000 (NOLOAD) : { KEEP(*(.stack_b)) } > RAM
    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
    __stack_bottom = __stack_top - 0x800;
    ASSERT(__bss_end <= ADDR(.stack_a), "ERROR: BSS overlaps thread stacks")
    ASSERT(SIZEOF(.stack_a) == 1024 && SIZEOF(.stack_b) == 1024,
           "ERROR: expected two 1 KiB thread stacks")
    ASSERT(ADDR(.stack_b) + SIZEOF(.stack_b) <= __stack_bottom,
           "ERROR: thread stacks overlap main stack")
}
