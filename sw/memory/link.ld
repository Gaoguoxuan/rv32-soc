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

    /* Exercise CRT initialization beyond the old 1 KiB RAM. */
    .data ORIGIN(RAM) + 0x2000 :
    {
        __data_start = .;
        *(.data*)
        *(.sdata*)
        . = ALIGN(4);
        __data_end = .;
    } > RAM AT> ROM
    __data_load_start = LOADADDR(.data);
    ASSERT(__data_load_start + SIZEOF(.data) <= 0x2000,
           "ERROR: startup image overlaps high ROM probe")

    .bss ORIGIN(RAM) + 0x6000 (NOLOAD) :
    {
        __bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM

    .high_text ORIGIN(ROM) + 0x2000 :
    {
        KEEP(*(.high_text))
    } > ROM
    .high_rodata ORIGIN(ROM) + 0x4000 :
    {
        KEEP(*(.high_rodata))
    } > ROM
    .rom_tail ORIGIN(ROM) + LENGTH(ROM) - 4 :
    {
        LONG(0x5aa59669)
    } > ROM

    /* Reserve the final 16 RAM bytes for boundary probes above the stack. */
    __stack_top = ORIGIN(RAM) + LENGTH(RAM) - 16;
    __stack_bottom = __stack_top - 0x400;
    ASSERT(__bss_end <= __stack_bottom, "ERROR: BSS collided with stack")
}
