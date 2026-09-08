OUTPUT_ARCH(riscv)
ENTRY(_start)


MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 1K
}


SECTIONS
{
    /* =========================================================
     * Code
     * ========================================================= */

    .text :
    {
        KEEP(*(.text.start))
        *(.text*)
    } > ROM


    /* =========================================================
     * Read-only data
     *
     * String literals, const arrays, etc.
     * Stay in ROM permanently.
     * ========================================================= */

    .rodata :
    {
        . = ALIGN(4);

        *(.rodata*)

        . = ALIGN(4);
    } > ROM


    /* =========================================================
     * Initialized writable data
     *
     * Runtime address: RAM
     * Initial image:   ROM
     * ========================================================= */

    .data :
    {
        . = ALIGN(4);

        __data_start = .;

        *(.data*)

        . = ALIGN(4);

        __data_end = .;

    } > RAM AT> ROM


    /*
     * ROM address containing the initial .data image.
     */
    __data_load_start = LOADADDR(.data);


    /* =========================================================
     * Zero-initialized data
     *
     * Exists in RAM, but does not need bytes in ROM image.
     * ========================================================= */

    .bss (NOLOAD) :
    {
        . = ALIGN(4);

        __bss_start = .;

        *(.bss*)
        *(COMMON)

        . = ALIGN(4);

        __bss_end = .;

    } > RAM


    /* =========================================================
     * Stack
     * ========================================================= */

    __stack_top = ORIGIN(RAM) + LENGTH(RAM);

    /*
     * Reserve the upper 256 bytes for stack for now.
     */
    __stack_bottom = __stack_top - 0x100;


    ASSERT(
        __bss_end <= __stack_bottom,
        "ERROR: .data/.bss collided with stack"
    )
}