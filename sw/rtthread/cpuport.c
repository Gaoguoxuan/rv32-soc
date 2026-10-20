#include <rthw.h>

#include "../common/irq.h"

rt_base_t rt_hw_interrupt_disable(void)
{
    return (rt_base_t)irq_save();
}

void rt_hw_interrupt_enable(rt_base_t level)
{
    irq_restore((irq_state_t)level);
}