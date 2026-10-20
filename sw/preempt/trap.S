.section .text.trap, "ax", @progbits
.balign 4
.globl preempt_trap_entry
.type preempt_trap_entry, @function

preempt_trap_entry:
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

    # trap_dispatch(frame, cause, tval)
    mv   a0, sp
    csrr a1, mcause
    csrr a2, mtval
    call trap_dispatch

    # C 返回要恢复的现场地址。
    # 返回原地址：继续当前线程。
    # 返回其他线程的地址：切换线程。
    mv sp, a0

    lw t0, 124(sp)
    csrw mepc, t0

    # 恢复目标线程的状态，但保持 MIE=0，
    # 等所有寄存器恢复完成后再由 mret 恢复中断使能。
    lw t0, 128(sp)
    andi t0, t0, -9
    csrw mstatus, t0

    lw ra,   0(sp)
    lw gp,   8(sp)
    lw tp,  12(sp)
    lw t0,  16(sp)
    lw t1,  20(sp)
    lw t2,  24(sp)
    lw s0,  28(sp)
    lw s1,  32(sp)

    lw a0,  36(sp)
    lw a1,  40(sp)
    lw a2,  44(sp)
    lw a3,  48(sp)
    lw a4,  52(sp)
    lw a5,  56(sp)
    lw a6,  60(sp)
    lw a7,  64(sp)

    lw s2,  68(sp)
    lw s3,  72(sp)
    lw s4,  76(sp)
    lw s5,  80(sp)
    lw s6,  84(sp)
    lw s7,  88(sp)
    lw s8,  92(sp)
    lw s9,  96(sp)
    lw s10, 100(sp)
    lw s11, 104(sp)

    lw t3, 108(sp)
    lw t4, 112(sp)
    lw t5, 116(sp)
    lw t6, 120(sp)

    # 最后恢复中断前的 sp。
    lw sp, 4(sp)
    mret

.size preempt_trap_entry, .-preempt_trap_entry
