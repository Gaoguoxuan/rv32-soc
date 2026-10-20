.section .text.trap, "ax", @progbits
.balign 4
.globl rt_hw_trap_entry
.type rt_hw_trap_entry, @function

rt_hw_trap_entry:
    # 完整现场共 144 字节。
    addi sp, sp, -144

    sw ra,   0(sp)

    # 必须先保存 t0，再借用它计算中断前的 sp。
    sw t0,  16(sp)
    addi t0, sp, 144
    sw t0,   4(sp)

    sw gp,   8(sp)
    sw tp,  12(sp)
    sw t1,  20(sp)
    sw t2,  24(sp)
    sw s0,  28(sp)
    sw s1,  32(sp)

    sw a0,  36(sp)
    sw a1,  40(sp)
    sw a2,  44(sp)
    sw a3,  48(sp)
    sw a4,  52(sp)
    sw a5,  56(sp)
    sw a6,  60(sp)
    sw a7,  64(sp)

    sw s2,  68(sp)
    sw s3,  72(sp)
    sw s4,  76(sp)
    sw s5,  80(sp)
    sw s6,  84(sp)
    sw s7,  88(sp)
    sw s8,  92(sp)
    sw s9,  96(sp)
    sw s10, 100(sp)
    sw s11, 104(sp)

    sw t3, 108(sp)
    sw t4, 112(sp)
    sw t5, 116(sp)
    sw t6, 120(sp)

    csrr t0, mepc
    sw t0, 124(sp)

    csrr t0, mstatus
    sw t0, 128(sp)

    sw zero, 132(sp)
    sw zero, 136(sp)
    sw zero, 140(sp)

    # rt_hw_trap_dispatch(frame, cause, tval)
    mv a0, sp
    csrr a1, mcause
    csrr a2, mtval
    call rt_hw_trap_dispatch

    # C 函数已经返回，现在才能换到目标现场。
    mv sp, a0
    j rt_hw_context_restore

.size rt_hw_trap_entry, .-rt_hw_trap_entry
