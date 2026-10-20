#include <rthw.h>
#include "cpuport.h"
#include "../common/irq.h"

rt_base_t rt_hw_interrupt_disable(void)
{
    return (rt_base_t)irq_save();
}

void rt_hw_interrupt_enable(rt_base_t level)
{
    irq_restore((irq_state_t)level);
}

rt_uint8_t *rt_hw_stack_init(void *entry,
                            void *parameter,
                            rt_uint8_t *stack_addr,
                            void *exit)
{
    rt_ubase_t top;
    rt_ubase_t gp_value;
    rt_ubase_t tp_value;
    rt_hw_stack_frame_t *frame;

    /* stack_addr 指向栈内最后一个字，先换算为栈顶。 */
    top = (rt_ubase_t)stack_addr + sizeof(rt_ubase_t);
    top = RT_ALIGN_DOWN(top, RT_ALIGN_SIZE);

    frame = (rt_hw_stack_frame_t *)(top - sizeof(*frame));
    rt_memset(frame, 0, sizeof(*frame));

    __asm__ volatile ("mv %0, gp" : "=r"(gp_value));
    __asm__ volatile ("mv %0, tp" : "=r"(tp_value));

    frame->gpr[0] = (rt_ubase_t)exit;       /* ra */
    frame->gpr[1] = top;                   /* sp */
    frame->gpr[2] = gp_value;              /* gp */
    frame->gpr[3] = tp_value;              /* tp */
    frame->gpr[9] = (rt_ubase_t)parameter;  /* a0 */

    frame->mepc = (rt_ubase_t)entry;
    frame->mstatus = 0x1880u;  /* MPP=M，MPIE=1，MIE=0 */

    return (rt_uint8_t *)frame;
}