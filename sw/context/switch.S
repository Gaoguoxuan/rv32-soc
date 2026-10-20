.section .text.context, "ax", @progbits
.balign 4
.globl context_switch
.type context_switch, @function

context_switch:
    # a0 = from，a1 = to。

    # 保存当前线程。
    sw ra,   0(a0)
    sw sp,   4(a0)
    sw s0,   8(a0)
    sw s1,  12(a0)
    sw s2,  16(a0)
    sw s3,  20(a0)
    sw s4,  24(a0)
    sw s5,  28(a0)
    sw s6,  32(a0)
    sw s7,  36(a0)
    sw s8,  40(a0)
    sw s9,  44(a0)
    sw s10, 48(a0)
    sw s11, 52(a0)

    # 恢复目标线程。
    lw ra,   0(a1)
    lw s0,   8(a1)
    lw s1,  12(a1)
    lw s2,  16(a1)
    lw s3,  20(a1)
    lw s4,  24(a1)
    lw s5,  28(a1)
    lw s6,  32(a1)
    lw s7,  36(a1)
    lw s8,  40(a1)
    lw s9,  44(a1)
    lw s10, 48(a1)
    lw s11, 52(a1)
    lw sp,   4(a1)

    # 在目标线程的栈上，跳到它保存的返回地址。
    ret

.size context_switch, .-context_switch


.balign 4
.globl thread_bootstrap
.type thread_bootstrap, @function

thread_bootstrap:
    # 新线程初始 s0 = 线程函数地址，s1 = 参数。
    mv a0, s1
    jalr ra, 0(s0)

    # 线程函数正常返回后，由 C 函数处理线程结束。
    call thread_exit

.Lthread_exit_hang:
    j .Lthread_exit_hang

.size thread_bootstrap, .-thread_bootstrap