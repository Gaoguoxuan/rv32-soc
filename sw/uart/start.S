.section .text.start
.globl _start


_start:

    # ============================================================
    # 1. Initialize stack
    # ============================================================

    la sp, __stack_top


    # ============================================================
    # 2. Copy .data
    #
    # ROM:
    #     __data_load_start
    #
    # RAM:
    #     __data_start ... __data_end
    # ============================================================

    la t0, __data_load_start
    la t1, __data_start
    la t2, __data_end


data_copy_loop:

    bgeu t1, t2, data_copy_done

    lw t3, 0(t0)
    sw t3, 0(t1)

    addi t0, t0, 4
    addi t1, t1, 4

    j data_copy_loop


data_copy_done:


    # ============================================================
    # 3. Clear .bss
    # ============================================================

    la t0, __bss_start
    la t1, __bss_end


bss_clear_loop:

    bgeu t0, t1, bss_clear_done

    sw zero, 0(t0)

    addi t0, t0, 4

    j bss_clear_loop


bss_clear_done:


    # ============================================================
    # 4. Enter C
    # ============================================================

    call main


    # main normally never returns.
    # If it does, stay here.

hang:

    j hang