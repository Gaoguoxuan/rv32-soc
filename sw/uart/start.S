.section .text.start
.globl _start

_start:

    # RAM top
    li sp, 0x10000400

    call main


hang:
    j hang