OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
    . = 0x00000000;

    /* =========================================================
     * Code
     * ========================================================= */

    .text :
    {
        *(.text.start)
        *(.text*)
    }


    .rodata :
    {
        *(.rodata*)
    }


    /* =========================================================
     * Writable data
     *
     * Put it immediately after program code for now.
     * ========================================================= */

    . = ALIGN(4);

    .data :
    {
        __data_start = .;

        *(.data*)

        __data_end = .;
    }


    . = ALIGN(4);

    .bss :
    {
        __bss_start = .;

        *(.bss*)
        *(COMMON)

        __bss_end = .;
    }


    . = ALIGN(4);


    /* =========================================================
     * Stack
     * ========================================================= */

    __stack_top = 0x00000400;


    /*
     * Catch an overflow early.
     */
    ASSERT(
        __bss_end <= __stack_top,
        "ERROR: .data/.bss collided with stack"
    )
}