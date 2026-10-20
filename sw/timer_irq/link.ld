OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 1K
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

    /* Main, the 128-byte trap frame, and C calls share this 512-byte stack. */
    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
    __stack_bottom = __stack_top - 0x200;
    __stack_guard = __stack_bottom - 4;

    ASSERT(__bss_end <= __stack_guard,
           "ERROR: .data/.bss collided with interrupt stack guard")
    ASSERT((__stack_top & 15) == 0, "ERROR: stack must be 16-byte aligned")
}
