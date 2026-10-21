#include "cpuport.h"
#include <finsh.h>
#include <shell.h>

static struct rt_thread worker_thread;
static struct rt_semaphore worker_wakeup;

static rt_uint32_t worker_stack[512]
    __attribute__((aligned(RT_ALIGN_SIZE)));

static volatile rt_uint32_t worker_running = 1u;
static volatile rt_uint32_t work_count;
static volatile rt_uint32_t worker_waiting;

static void worker_entry(void *parameter)
{
    (void)parameter;

    while (1) {
        rt_base_t level = rt_hw_interrupt_disable();

        rt_uint32_t running = worker_running;

        if (!running)
            worker_waiting = 1u;

        rt_hw_interrupt_enable(level);

        if (!running) {
            rt_sem_take(&worker_wakeup, RT_WAITING_FOREVER);
            continue;
        }

        rt_thread_delay(10);

        level = rt_hw_interrupt_disable();

        if (worker_running)
            work_count++;

        rt_hw_interrupt_enable(level);
    }
}

static int stats(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    rt_base_t level = rt_hw_interrupt_disable();

    rt_uint32_t running = worker_running;
    rt_uint32_t count = work_count;
    rt_tick_t tick = rt_tick_get();

    rt_hw_interrupt_enable(level);

    rt_kprintf("tick=%u running=%u count=%u\n",
               tick, running, count);
    return 0;
}
MSH_CMD_EXPORT(stats, show worker status);

static int pause_work(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    rt_base_t level = rt_hw_interrupt_disable();
    worker_running = 0u;
    rt_hw_interrupt_enable(level);

    rt_kprintf("worker paused\n");
    return 0;
}
MSH_CMD_EXPORT_ALIAS(pause_work, pause, pause counting);

static int resume_work(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    rt_base_t level = rt_hw_interrupt_disable();

    worker_running = 1u;

    rt_uint32_t notify = worker_waiting;
    worker_waiting = 0u;

    rt_hw_interrupt_enable(level);

    if (notify)
        rt_sem_release(&worker_wakeup);

    rt_kprintf("worker resumed\n");
    return 0;
}
MSH_CMD_EXPORT_ALIAS(resume_work, resume, resume counting);

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

    if (rt_sem_init(&worker_wakeup, "wakeup",
                    0, RT_IPC_FLAG_PRIO) != RT_EOK) {
        rt_kprintf("worker semaphore init failed\n");
        while (1) {
        }
    }

    if (rt_thread_init(&worker_thread, "worker",
                        worker_entry, RT_NULL,
                        worker_stack, sizeof(worker_stack),
                        21, 2) != RT_EOK ||
        rt_thread_startup(&worker_thread) != RT_EOK) {
        rt_kprintf("worker init failed\n");
        while (1) {
        }
    }

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
