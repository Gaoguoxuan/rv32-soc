.section .text.context, "ax", @progbits
.balign 4
.globl rt_hw_context_switch_to
.type rt_hw_context_switch_to, @function

.globl rt_hw_context_switch
.type rt_hw_context_switch, @function

rt_hw_context_switch:
    # a0 = &from_thread->sp
    # a1 = &to_thread->sp
    # 调度器调用前已经关闭中断。
    csrci mstatus, 8
    addi sp, sp, -144

    sw ra,   0(sp)
    sw gp,   8(sp)
    sw tp,  12(sp)
    sw t0,  16(sp)
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

    # t0 已保存，现在可以借用。
    addi t0, sp, 144
    sw t0, 4(sp)             # 分配现场之前的 sp

    # 恢复后，从调度器中调用本函数的下一条指令继续。
    sw ra, 124(sp)

    # 清除 MIE 和 MPIE，让 mret 返回调度器时仍保持关中断。
    csrr t0, mstatus
    andi t0, t0, -137        # ~0x88
    sw t0, 128(sp)

    sw zero, 132(sp)
    sw zero, 136(sp)
    sw zero, 140(sp)

    sw sp, 0(a0)            # from_thread->sp = 当前现场地址
    lw sp, 0(a1)            # sp = to_thread->sp
    j rt_hw_context_restore

.size rt_hw_context_switch, .-rt_hw_context_switch

rt_hw_context_switch_to:
    csrci mstatus, 8
    lw sp, 0(a0)

.size rt_hw_context_switch_to, .-rt_hw_context_switch_to

.globl rt_hw_context_restore
.type rt_hw_context_restore, @function

rt_hw_context_restore:
    lw t0, 124(sp)
    csrw mepc, t0

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

    lw sp, 4(sp)
    mret

.size rt_hw_context_restore, .-rt_hw_context_restore