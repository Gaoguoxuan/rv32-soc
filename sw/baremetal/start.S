.section .text.start
.globl _start

_start:

    # --------------------------------
    # Initialize stack pointer
    # --------------------------------

    li sp, 0x400


    # --------------------------------
    # Enter C
    #
    # RISC-V ABI:
    # return value is stored in a0/x10
    # --------------------------------

    call main


    # --------------------------------
    # main() should return 42
    # --------------------------------

    li t0, 42

    bne a0, t0, fail


    # PASS signature
    #
    # t6 = x31

    li t6, 1


pass:

    j pass


fail:

    li t6, -1

fail_loop:

    j fail_loop