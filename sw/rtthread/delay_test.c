#include "cpuport.h"

typedef struct {
    rt_uint32_t id;
    rt_tick_t period;
    rt_uint32_t repeats;
} delay_argument_t;

static const delay_argument_t arguments[2] = {
    {1u, 3u, 5u},
    {2u, 5u, 3u}
};

static struct rt_thread threads[3];
/* Four threads: A, B, checker, idle. Export field addresses for the monitor. */
static volatile rt_ubase_t thread_locations[20];
static rt_uint32_t stack_a[512]
    __attribute__((section(".thread_stack_a"), aligned(16), used));
static rt_uint32_t stack_b[512]
    __attribute__((section(".thread_stack_b"), aligned(16), used));
static rt_uint32_t stack_check[512]
    __attribute__((section(".thread_stack_check"), aligned(16), used));
static volatile rt_uint32_t stack_guard[4]
    __attribute__((section(".stack_guard"), aligned(16), used));
static volatile rt_uint32_t data_cookie = 0x13579bdfu;

static volatile rt_uint32_t wake_count[2];
static volatile rt_tick_t sleep_tick[2][5];
static volatile rt_tick_t wake_tick[2][5];

static volatile rt_uint32_t idle_hits;
static volatile rt_uint32_t cleanup_mask;
static volatile rt_uint32_t normal_returns;

static void fail(rt_uint32_t line)
{
    (void)rt_hw_interrupt_disable();
    rt_hw_tick_stop();
    rt_kprintf("M11.5 FAIL line %u\n", line);

    while (1) {
    }
}

#define expect(condition) \
    do { if (!(condition)) fail(__LINE__); } while (0)

static void check_guards(void)
{
    rt_uint32_t *idle_bottom = rt_thread_idle_gethandler()->stack_addr;
    for (rt_uint32_t i = 0; i < 4u; i++) {
        expect(stack_a[i] == 0xa55a0001u);
        expect(stack_b[i] == 0xa55a0002u);
        expect(stack_check[i] == 0xa55a0003u);
        expect(stack_guard[i] == 0xc0decafeu);
        /* The kernel fills idle's stack with '#'; keep 16 bottom bytes intact. */
        expect(idle_bottom[i] == 0x23232323u);
    }
}

static void idle_hook(void)
{
    idle_hits++;
}

static void thread_cleanup(struct rt_thread *thread)
{
    expect(rt_thread_self() == rt_thread_idle_gethandler());

    if (thread == &threads[0])
        cleanup_mask |= 1u;
    else if (thread == &threads[1])
        cleanup_mask |= 2u;
    else
        fail(__LINE__);
}

static void delay_entry(void *parameter)
{
    const delay_argument_t *self = parameter;
    rt_uint32_t id = self->id;
    rt_uint32_t expected = 0x13570000u | id;
    volatile rt_uint32_t local = expected;

    expect(id >= 1u && id <= 2u);
    expect(self == &arguments[id - 1u]);
    expect(rt_thread_self() == &threads[id - 1u]);

    for (rt_uint32_t i = 0; i < self->repeats; i++) {
        rt_tick_t before = rt_tick_get();
        sleep_tick[id - 1u][i] = before;

        rt_err_t result = rt_thread_delay(self->period);

        rt_tick_t after = rt_tick_get();
        expect(result == RT_EOK);
        expect((rt_tick_t)(after - before) >= self->period);
        expect(local == expected);
        expect(rt_thread_self() == &threads[id - 1u]);
        expect(rt_interrupt_get_nest() == 0);
        check_guards();

        wake_tick[id - 1u][i] = after;
        wake_count[id - 1u]++;

        rt_kprintf("THREAD %c WAKE %u\n",
                   id == 1u ? 'A' : 'B', after);
    }

    /* 两个线程共享这个计数，保护读、改、写过程。 */
    rt_base_t level = rt_hw_interrupt_disable();
    normal_returns++;
    rt_hw_interrupt_enable(level);

    /* 正常返回，由内核退出并加入待清理队列。 */
}

static void finish_entry(void *parameter)
{
    expect(parameter == &threads[2]);

    rt_tick_t before = rt_tick_get();
    rt_err_t result = rt_thread_delay(18u);

    (void)rt_hw_interrupt_disable();
    rt_hw_tick_stop();

    expect(result == RT_EOK);
    expect((rt_tick_t)(rt_tick_get() - before) >= 18u);
    expect(rt_thread_self() == &threads[2]);
    expect(wake_count[0] == 5u && wake_count[1] == 3u);
    expect(normal_returns == 2u);
    expect(idle_hits != 0);
    expect(cleanup_mask == 3u);
    expect(rt_interrupt_get_nest() == 0);
    expect(rt_thread_switch_interrupt_flag == 0);
    expect(data_cookie == 0x13579bdfu);
    for (rt_uint32_t i = 0; i < 2u; i++) {
        expect((threads[i].stat & RT_THREAD_STAT_MASK) == RT_THREAD_CLOSE);
        expect(rt_object_get_type((rt_object_t)&threads[i]) == RT_Object_Class_Null);
        for (rt_uint32_t j = 0; j < arguments[i].repeats; j++) {
            expect(sleep_tick[i][j] == j * arguments[i].period);
            expect(wake_tick[i][j] == (j + 1u) * arguments[i].period);
        }
    }
    check_guards();

    rt_kprintf("DELAY WAKE PASS\n");
    rt_kprintf("IDLE CLEANUP PASS\n");
    rt_kprintf("STACK GUARD PASS\n");
    rt_kprintf("M11.5 PASS\n");

    while (1) {
    }
}

int main(void)
{
    expect(wake_count[0] == 0 && wake_count[1] == 0 && idle_hits == 0);
    expect(cleanup_mask == 0 && normal_returns == 0 && data_cookie == 0x13579bdfu);
    expect(rt_thread_self() == RT_NULL && rt_thread_switch_interrupt_flag == 0);
    for (rt_uint32_t i = 0; i < 2u; i++)
        for (rt_uint32_t j = 0; j < 5u; j++)
            expect(sleep_tick[i][j] == 0 && wake_tick[i][j] == 0);
    for (rt_uint32_t i = 0; i < 4u; i++) {
        stack_a[i] = 0xa55a0001u;
        stack_b[i] = 0xa55a0002u;
        stack_check[i] = 0xa55a0003u;
        stack_guard[i] = 0xc0decafeu;
    }
    rt_kprintf("M11.5 START\n");
    (void)rt_hw_interrupt_disable();
    rt_system_timer_init();
    rt_system_scheduler_init();
    rt_thread_idle_init();
    expect(rt_thread_idle_sethook(idle_hook) == RT_EOK);
    expect(rt_thread_init(&threads[0], "workerA", delay_entry, (void *)&arguments[0],
                          stack_a + 4, sizeof(stack_a) - 16u, 10, 2) == RT_EOK);
    expect(rt_thread_init(&threads[1], "workerB", delay_entry, (void *)&arguments[1],
                          stack_b + 4, sizeof(stack_b) - 16u, 11, 2) == RT_EOK);
    expect(rt_thread_init(&threads[2], "check", finish_entry, &threads[2],
                          stack_check + 4, sizeof(stack_check) - 16u, 20, 2) == RT_EOK);
    threads[0].cleanup = thread_cleanup;
    threads[1].cleanup = thread_cleanup;

    rt_thread_t idle_thread = rt_thread_idle_gethandler();
    expect(idle_thread->stack_size == 1024u);
    for (rt_uint32_t i = 0; i < 4u; i++) {
        rt_thread_t thread = i < 3u ? &threads[i] : idle_thread;
        thread_locations[i] = (rt_ubase_t)&thread->sp;
        thread_locations[i + 4u] = (rt_ubase_t)thread;
        thread_locations[i + 8u] = (rt_ubase_t)&thread->stat;
        thread_locations[i + 12u] = (rt_ubase_t)&thread->thread_timer.timeout_tick;
        thread_locations[i + 16u] = (rt_ubase_t)&thread->type;
    }
    for (rt_uint32_t i = 0; i < 3u; i++)
        expect(rt_thread_startup(&threads[i]) == RT_EOK);
    check_guards();
    rt_kprintf("KERNEL READY\n");
    rt_hw_tick_init();
    __asm__ volatile ("csrw mstatus, %0" :: "r"(0x1880u) : "memory");
    rt_system_scheduler_start();
    fail(__LINE__);
}
