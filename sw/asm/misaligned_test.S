.section .text.start
.balign 4
.globl _start

# Each fault has its own label. The handler checks that label, the cause,
# and the full effective address before skipping the known 4-byte test slot.
.macro CHECK_FAULT name, op, reg, offset, base, address
    li      s7, \address
    la      s2, \name
\name:
    \op     \reg, \offset(\base)
    addi    s1, s1, 1
    bne     s4, s8, fail
.endm

.macro CHECK_LOAD op, offset, expected
    \op     t0, \offset(s5)
    li      t1, \expected
    bne     t0, t1, fail
.endm

_start:
    li      t6, 0                  # Result: 0=running, 1=pass, -1=fail
    li      s0, 0                  # Handler entries
    li      s1, 0                  # Successful returns
    li      s3, -1                 # No exception expected during legal accesses
    li      s5, 0x10000000         # RAM base
    li      s6, 0x89abcdef         # Would-be store value
    li      s8, 0x13579bdf         # Destination register sentinel
    mv      s4, s8
    addi    s9, s5, 8              # Base for negative-offset tests
    li      s11, 0x1880            # Expected trap-entry mstatus with old MIE=1

    la      t0, trap_handler
    csrw    mtvec, t0
    li      t0, 0x12345678
    csrw    mscratch, t0
    li      t0, 0xfeedface
    csrw    mtval, t0
    li      t0, 8
    csrw    mstatus, t0

    # Four aligned word stores initialize the data used by the test.
    li      t0, 0x10203040
    sw      t0, 0(s5)
    li      t0, 0x50607080
    sw      t0, 4(s5)
    li      t0, -1
    sw      t0, 16(s5)
    li      t0, 0x24681357
    sw      t0, 20(s5)

    # Byte stores at all four lanes must remain legal.
    li      t0, 0x80
    sb      t0, 16(s5)
    li      t0, 0x7f
    sb      t0, 17(s5)
    li      t0, 0xfe
    sb      t0, 18(s5)
    li      t0, 0x55
    sb      t0, 19(s5)

    CHECK_LOAD lw,  16, 0x55fe7f80
    CHECK_LOAD lb,  16, -128
    CHECK_LOAD lbu, 16, 0x80
    CHECK_LOAD lb,  17, 0x7f
    CHECK_LOAD lbu, 17, 0x7f
    CHECK_LOAD lb,  18, -2
    CHECK_LOAD lbu, 18, 0xfe
    CHECK_LOAD lb,  19, 0x55
    CHECK_LOAD lbu, 19, 0x55

    # Halfword accesses at both offsets 0 and 2 of a word are legal.
    li      t0, 0x8abc
    sh      t0, 22(s5)
    CHECK_LOAD lh,  22, 0xffff8abc
    CHECK_LOAD lhu, 22, 0x8abc
    CHECK_LOAD lh,  20, 0x1357
    li      t0, 0x2468
    sh      t0, 20(s5)
    CHECK_LOAD lh,  20, 0x2468
    CHECK_LOAD lhu, 20, 0x2468
    CHECK_LOAD lw,  20, 0x8abc2468
    lw      zero, 20(s5)           # A legal load with a discarded result

    # Ten load faults, including rd=x0 and signed immediate calculation.
    li      s3, 4
    CHECK_FAULT lw_1,    lw,  s4,   1, s5, 0x10000001
    CHECK_FAULT lw_2,    lw,  s4,   2, s5, 0x10000002
    CHECK_FAULT lw_3,    lw,  s4,   3, s5, 0x10000003
    CHECK_FAULT lh_1,    lh,  s4,   1, s5, 0x10000001
    CHECK_FAULT lh_3,    lh,  s4,   3, s5, 0x10000003
    CHECK_FAULT lhu_1,   lhu, s4,   1, s5, 0x10000001
    CHECK_FAULT lhu_3,   lhu, s4,   3, s5, 0x10000003
    CHECK_FAULT lw_x0,   lw,  zero, 1, s5, 0x10000001
    CHECK_FAULT lw_neg,  lw,  s4,  -1, s9, 0x10000007
    CHECK_FAULT lh_neg,  lh,  s4,  -1, s9, 0x10000007

    # Seven store faults. The original RAM words must stay intact.
    li      s3, 6
    CHECK_FAULT sw_1,    sw, s6,  1, s5, 0x10000001
    CHECK_FAULT sw_2,    sw, s6,  2, s5, 0x10000002
    CHECK_FAULT sw_3,    sw, s6,  3, s5, 0x10000003
    CHECK_FAULT sh_1,    sh, s6,  1, s5, 0x10000001
    CHECK_FAULT sh_3,    sh, s6,  3, s5, 0x10000003
    CHECK_FAULT sw_neg,  sw, s6, -1, s9, 0x10000007
    CHECK_FAULT sh_neg,  sh, s6, -1, s9, 0x10000007

    # Synchronous address exceptions must also work with interrupts disabled.
    li      t0, 0
    csrw    mstatus, t0
    li      s11, 0x1800
    li      s3, 4
    CHECK_FAULT lw_masked, lw, s4, 3, s5, 0x10000003
    li      s3, 6
    CHECK_FAULT sw_masked, sw, s6, 2, s5, 0x10000002

    li      t0, 19
    bne     s0, t0, fail
    bne     s1, t0, fail
    CHECK_LOAD lw, 0, 0x10203040
    CHECK_LOAD lw, 4, 0x50607080
    csrr    t0, mscratch
    li      t1, 0x12345678
    bne     t0, t1, fail
    csrr    t0, mstatus
    li      t1, 0x1880
    bne     t0, t1, fail

    li      t6, 1
pass:
    j       pass


.balign 4
trap_handler:
    # Test-only handler: t0/t1 are deliberately scratch registers.
    csrr    t0, mepc
    bne     t0, s2, fail
    csrr    t1, mcause
    bne     t1, s3, fail
    csrr    t1, mtval
    bne     t1, s7, fail
    csrr    t1, mstatus
    bne     t1, s11, fail
    addi    s0, s0, 1

    # Test recovery policy: skip this instruction; do not emulate its access.
    addi    t0, t0, 4
    csrw    mepc, t0
    mret


fail:
    li      t6, -1
fail_loop:
    j       fail_loop
