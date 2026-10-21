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
        __fsymtab_start = .;
        KEEP(*(FSymTab))
        __fsymtab_end = .;
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
        . = ALIGN(16);
        __bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(16);
        __bss_end = .;
    } > RAM
    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
    __stack_bottom = __stack_top - 0x1000;
    ASSERT(__bss_end <= __stack_bottom, "ERROR: BSS overlaps main stack")
    ASSERT(__fsymtab_end > __fsymtab_start, "ERROR: empty FinSH command table")
    ASSERT((__fsymtab_end - __fsymtab_start) % 12 == 0,
           "ERROR: expected RV32 FinSH entries with descriptions")
}
