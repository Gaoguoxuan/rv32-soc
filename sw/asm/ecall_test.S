.section .text.start
.balign 4
.globl _start

_start:
    li      t6, 0                  # Result: 0=running, 1=pass, -1=fail
    li      s0, 0                  # Number of handler entries
    li      s1, 0                  # Number of successful returns

    la      t0, trap_handler
    csrw    mtvec, t0             # Direct mode; handler is 4-byte aligned

    # Case 1: MIE=1, MPIE=0 before ECALL.
    # Entry must produce MIE=0, MPIE=1, MPP=3.
    li      t0, 0x8
    csrw    mstatus, t0
    la      s2, ecall_enabled     # Expected mepc at handler entry
    li      s3, 0x1880            # Expected mstatus at handler entry

ecall_enabled:
    ecall

    addi    s1, s1, 1
    li      t0, 1
    bne     s0, t0, fail

    # MRET restores MIE from MPIE and sets MPIE=1.
    csrr    t0, mstatus
    li      t1, 0x1888
    bne     t0, t1, fail

    # Case 2: MIE=0, MPIE=1 before ECALL.
    # ECALL is a synchronous exception, so MIE=0 must not mask it.
    # Entry must overwrite the old MPIE with MIE=0.
    li      t0, 0x80
    csrw    mstatus, t0
    la      s2, ecall_disabled
    li      s3, 0x1800

ecall_disabled:
    ecall

    addi    s1, s1, 1
    li      t0, 2
    bne     s0, t0, fail
    bne     s1, t0, fail

    # MRET leaves MIE=0 and sets MPIE=1.
    csrr    t0, mstatus
    li      t1, 0x1880
    bne     t0, t1, fail

    li      t6, 1

pass:
    j       pass


.balign 4
trap_handler:
    # Test-only handler: t0/t1 are deliberately used as scratch registers.
    # A general interrupt handler must preserve interrupted register state.
    csrr    t0, mcause
    li      t1, 11
    bne     t0, t1, fail

    csrr    t0, mepc
    bne     t0, s2, fail         # mepc must point at ECALL itself

    csrr    t1, mstatus
    bne     t1, s3, fail

    addi    s0, s0, 1

    # Skip this 32-bit ECALL in software; MRET itself does not add 4.
    addi    t0, t0, 4
    csrw    mepc, t0
    mret


fail:
    li      t6, -1

fail_loop:
    j       fail_loop
