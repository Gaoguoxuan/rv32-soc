.section .text.start
.balign 4
.globl _start

_start:
    li      t6, 0                  # Result: 0=running, 1=pass, -1=fail
    li      s0, 0                  # Handler entry count
    li      s1, 0                  # Successful return count

    li      s10, 0x13579bdf
    mv      s4, s10                # Destination register must survive faults
    li      s5, 7
    li      s6, 9
    li      s7, 0xcafebabe          # Would-be store / CSR write value

    li      s8, 0x12345678
    csrw    mscratch, s8

    # This testbench has separate instruction and data memories.
    li      s9, 0x89abcdef
    sw      s9, 0(zero)            # RAM sentinel; illegal store must not change it

    la      t0, trap_handler
    csrw    mtvec, t0
    li      t0, 0x8
    csrw    mstatus, t0            # MIE=1, MPIE=0
    li      s3, 2                  # Expected illegal-instruction cause

    # 1. All-zero instruction encoding.
    la      s2, bad_opcode
bad_opcode:
    .word   0x00000000
    addi    s1, s1, 1
    bne     s4, s10, fail

    # 2. MUL s4,s5,s6: M is not implemented by this RV32I core.
    # Raw encoding lets the test retain -march=rv32i_zicsr.
    la      s2, unsupported_mul
unsupported_mul:
    .word   0x036a8a33
    addi    s1, s1, 1
    bne     s4, s10, fail

    # 3. Load opcode with unsupported funct3=011, rd=s4, address=0.
    la      s2, bad_load
bad_load:
    .word   0x00003a03
    addi    s1, s1, 1
    bne     s4, s10, fail

    # 4. Store opcode with unsupported funct3=011, rs2=s7, address=0.
    la      s2, bad_store
bad_store:
    .word   0x01703023
    addi    s1, s1, 1
    bne     s4, s10, fail

    # CSR 0x7c0 is deliberately absent from this core's CSR map.
    # 5. A read with rs1=x0 must still detect an unimplemented CSR.
    la      s2, bad_csr_read
bad_csr_read:
    csrrs   s4, 0x7c0, zero
    addi    s1, s1, 1
    bne     s4, s10, fail

    # 6. A CSR read/write must not update its destination on failure.
    la      s2, bad_csr_write
bad_csr_write:
    csrrw   s4, 0x7c0, s7
    addi    s1, s1, 1
    bne     s4, s10, fail

    # 7. Discarding the result with rd=x0 must not suppress the exception.
    la      s2, bad_csr_write_x0
bad_csr_write_x0:
    csrrw   zero, 0x7c0, s7
    addi    s1, s1, 1
    bne     s4, s10, fail

    # 8. The shared trap path must still distinguish ECALL from illegal ops.
    li      s3, 11
    la      s2, ecall_check
ecall_check:
    ecall
    addi    s1, s1, 1
    bne     s4, s10, fail

    li      t0, 8
    bne     s0, t0, fail
    bne     s1, t0, fail

    lw      t0, 0(zero)
    bne     t0, s9, fail
    csrr    t0, mscratch
    bne     t0, s8, fail
    csrr    t0, mstatus
    li      t1, 0x1888
    bne     t0, t1, fail

    li      t6, 1
pass:
    j       pass


.balign 4
trap_handler:
    # Test-only handler: t0/t1/t2 are deliberately scratch registers.
    csrr    t0, mcause
    bne     t0, s3, fail
    csrr    t0, mepc
    bne     t0, s2, fail
    csrr    t1, mstatus
    li      t2, 0x1880
    bne     t1, t2, fail
    csrr    t1, mscratch
    bne     t1, s8, fail
    addi    s0, s0, 1

    # Test recovery policy: skip the known 4-byte slot containing the fault.
    # This is not a general policy for recovering from arbitrary faults.
    addi    t0, t0, 4
    csrw    mepc, t0
    mret


fail:
    li      t6, -1
fail_loop:
    j       fail_loop
