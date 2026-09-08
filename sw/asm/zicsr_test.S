.section .text.start
.globl _start

_start:

    # ============================================================
    # CSRRW
    #
    # mscratch = 0x55
    # t1 should receive old value 0
    # ============================================================

    li      t0, 0x55

    csrrw   t1, mscratch, t0

    bne     t1, zero, fail


    # ============================================================
    # CSRRS
    #
    # old = 0x55
    # source = 0x0f
    #
    # new = 0x55 | 0x0f = 0x5f
    # ============================================================

    li      t2, 0x0f

    csrrs   t3, mscratch, t2

    li      t4, 0x55

    bne     t3, t4, fail


    # ============================================================
    # CSRRC
    #
    # old = 0x5f
    # source = 0x0c
    #
    # new = 0x5f & ~0x0c = 0x53
    # ============================================================

    li      t2, 0x0c

    csrrc   t3, mscratch, t2

    li      t4, 0x5f

    bne     t3, t4, fail


    # ============================================================
    # CSRRWI
    #
    # old = 0x53
    # new = 3
    # ============================================================

    csrrwi  t3, mscratch, 3

    li      t4, 0x53

    bne     t3, t4, fail


    # ============================================================
    # CSRRSI
    #
    # old = 3
    # new = 3 | 4 = 7
    # ============================================================

    csrrsi  t3, mscratch, 4

    li      t4, 3

    bne     t3, t4, fail


    # ============================================================
    # CSRRCI
    #
    # old = 7
    # new = 7 & ~1 = 6
    # ============================================================

    csrrci  t3, mscratch, 1

    li      t4, 7

    bne     t3, t4, fail


    # ============================================================
    # CSRRS with rs1=x0
    #
    # Pure CSR read.
    # mscratch must stay 6.
    # ============================================================

    csrrs   t3, mscratch, zero

    li      t4, 6

    bne     t3, t4, fail


    # ============================================================
    # CSRRWI with rd=x0
    #
    # Old value is discarded,
    # but CSR write MUST still happen.
    #
    # mscratch = 9
    # ============================================================

    csrrwi  zero, mscratch, 9


    # Read it back without modifying CSR

    csrrs   t3, mscratch, zero

    li      t4, 9

    bne     t3, t4, fail


    # ============================================================
    # PASS
    #
    # x31 / t6 = 1
    # ============================================================

    li      t6, 1


pass:
    j       pass


fail:

    li      t6, -1


fail_loop:
    j       fail_loop