#include "cpuport.h"
#include <finsh.h>
#include <shell.h>

static int hello(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    rt_kprintf("Hello from my RV32 CPU!\n");
    return 0;
}
MSH_CMD_EXPORT(hello, say hello);

static int ticks(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    rt_kprintf("tick=%u\n", rt_tick_get());
    return 0;
}
MSH_CMD_EXPORT(ticks, show system tick);

int main(void)
{
    (void)rt_hw_interrupt_disable();

    rt_system_timer_init();
    rt_system_scheduler_init();
    rt_thread_idle_init();

    rt_show_version();

    if (finsh_system_init() != RT_EOK) {
        rt_kprintf("FinSH init failed\n");
        while (1) {
        }
    }

    rt_hw_tick_init();

    __asm__ volatile (
        "csrw mstatus, %0"
        ::
        "r"(0x1880u)
        : "memory"
    );

    rt_system_scheduler_start();

    while (1) {
    }
}
