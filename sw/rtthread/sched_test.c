#include "cpuport.h"

typedef struct {
    rt_uint32_t id;
    rt_uint32_t cookie;
} sched_argument_t;

static const sched_argument_t arguments[2] = {
    {1u, 0x13579bdfu}, {2u, 0x2468ace0u}
};
static struct rt_thread threads[3];
/* Let the testbench find fields without assuming a kernel structure layout. */
static const void *const thread_locations[6] __attribute__((used)) = {
    &threads[0].sp, &threads[1].sp, &threads[2].sp,
    &threads[0], &threads[1], &threads[2]
};
static rt_uint32_t stack_a[512]
    __attribute__((section(".thread_stack_a"), aligned(16), used));
static rt_uint32_t stack_b[512]
    __attribute__((section(".thread_stack_b"), aligned(16), used));
static rt_uint32_t stack_check[512]
    __attribute__((section(".thread_stack_check"), aligned(16), used));
static volatile rt_uint32_t stack_guard[4]
    __attribute__((section(".stack_guard"), aligned(16), used));
static volatile rt_uint32_t rounds[2];
static volatile rt_uint32_t normal_returns;
static volatile rt_uint32_t critical_passes[2];
static volatile rt_uint32_t trace[6];
static volatile rt_uint32_t trace_count;
static volatile rt_uint32_t data_cookie = 0x13579bdfu;

static void sched_entry(void *argument) __attribute__((noinline));
static void finish_entry(void *argument) __attribute__((noinline, noreturn));

static void fail(rt_uint32_t line) __attribute__((noreturn));
static void fail(rt_uint32_t line)
{
    (void)rt_hw_interrupt_disable();
    rt_kprintf("M11.3 FAIL line %u\n", line);
    while (1) {
    }
}

#define expect(condition) do { if (!(condition)) fail(__LINE__); } while (0)

static rt_uint32_t read_status(void)
{
    rt_uint32_t value;
    __asm__ volatile ("csrr %0, mstatus" : "=r"(value) :: "memory");
    return value;
}

static void check_guards(void)
{
    for (rt_uint32_t i = 0; i < 4u; i++) {
        expect(stack_a[i] == 0xa55a0001u);
        expect(stack_b[i] == 0xa55a0002u);
        expect(stack_check[i] == 0xa55a0003u);
        expect(stack_guard[i] == 0xc0decafeu);
    }
}

static void test_interrupt_requests(void)
{
    rt_ubase_t a = (rt_ubase_t)&threads[0].sp;
    rt_ubase_t b = (rt_ubase_t)&threads[1].sp;
    rt_ubase_t c = (rt_ubase_t)&threads[2].sp;
    expect(rt_thread_switch_interrupt_flag == 0);
    expect(rt_interrupt_from_thread == 0 && rt_interrupt_to_thread == 0);

    rt_hw_context_switch_interrupt(a, b);
    expect(rt_thread_switch_interrupt_flag == 1);
    expect(rt_interrupt_from_thread == a && rt_interrupt_to_thread == b);
    rt_hw_context_switch_interrupt(b, c);
    expect(rt_interrupt_from_thread == a && rt_interrupt_to_thread == c);
    rt_hw_context_switch_interrupt(c, a);
    expect(rt_interrupt_from_thread == a && rt_interrupt_to_thread == a);

    rt_thread_switch_interrupt_flag = 0;
    rt_hw_context_switch_interrupt(b, c);
    expect(rt_thread_switch_interrupt_flag == 1);
    expect(rt_interrupt_from_thread == b && rt_interrupt_to_thread == c);
    rt_thread_switch_interrupt_flag = 0;
    rt_interrupt_from_thread = 0;
    rt_interrupt_to_thread = 0;
    rt_kprintf("IRQ REQUEST PASS\n");
}

static void sched_entry(void *argument)
{
    const sched_argument_t *self = argument;
    rt_uint32_t id = self->id;
    volatile rt_uint32_t local[8];
    expect(id >= 1u && id <= 2u && self == &arguments[id - 1u]);
    expect(rt_thread_self() == &threads[id - 1u]);
    expect(read_status() == 0x1888u);
    for (rt_uint32_t i = 0; i < 8u; i++)
        local[i] = self->cookie ^ (i << 16) ^ id;

    for (rt_uint32_t round = 0; round < 3u; round++) {
        expect(rt_thread_self() == &threads[id - 1u]);
        expect(read_status() == 0x1888u && rounds[id - 1u] == round);
        expect(trace_count < 6u);
        trace[trace_count++] = (id << 8) | (round + 1u);
        rounds[id - 1u]++;
        rt_kprintf("THREAD %c ROUND %u\n", id == 1u ? 'A' : 'B', round + 1u);

        if (round == 1u) {
            rt_base_t outer = rt_hw_interrupt_disable();
            rt_base_t inner = rt_hw_interrupt_disable();
            expect(outer == 8 && inner == 0 && read_status() == 0x1880u);
            expect(rt_thread_yield() == RT_EOK);
            expect(read_status() == 0x1880u);
            rt_hw_interrupt_enable(inner);
            expect(read_status() == 0x1880u);
            rt_hw_interrupt_enable(outer);
            expect(read_status() == 0x1888u);
            critical_passes[id - 1u]++;
        } else {
            expect(rt_thread_yield() == RT_EOK);
            expect(read_status() == 0x1888u);
        }

        expect(rt_thread_self() == &threads[id - 1u]);
        for (rt_uint32_t i = 0; i < 8u; i++)
            expect(local[i] == (self->cookie ^ (i << 16) ^ id));
        check_guards();
    }
    expect(normal_returns == id - 1u);
    normal_returns++;
    rt_kprintf("THREAD %c RETURN\n", id == 1u ? 'A' : 'B');
    /* Return through the real kernel's _thread_exit(). */
}

static void finish_entry(void *argument)
{
    expect(argument == &threads[2] && rt_thread_self() == &threads[2]);
    expect(read_status() == 0x1888u);
    expect(rounds[0] == 3u && rounds[1] == 3u && normal_returns == 2u);
    expect(critical_passes[0] == 1u && critical_passes[1] == 1u);
    expect(trace_count == 6u);
    for (rt_uint32_t i = 0; i < 6u; i++)
        expect(trace[i] == (((i & 1u) + 1u) << 8 | (i / 2u + 1u)));
    expect((threads[0].stat & RT_THREAD_STAT_MASK) == RT_THREAD_CLOSE);
    expect((threads[1].stat & RT_THREAD_STAT_MASK) == RT_THREAD_CLOSE);
    expect((threads[2].stat & RT_THREAD_STAT_MASK) == RT_THREAD_RUNNING);
    expect(rt_interrupt_get_nest() == 0 && rt_tick_get() == 0);
    expect(rt_thread_switch_interrupt_flag == 0 && data_cookie == 0x13579bdfu);
    check_guards();
    (void)rt_hw_interrupt_disable();
    rt_kprintf("SCHEDULER PASS\n");
    rt_kprintf("CRITICAL RESTORE PASS\n");
    rt_kprintf("STACK GUARD PASS\n");
    rt_kprintf("M11.3 PASS\n");
    while (1) {
    }
}

int main(void)
{
    expect(rounds[0] == 0 && rounds[1] == 0 && normal_returns == 0);
    expect(critical_passes[0] == 0 && critical_passes[1] == 0 && trace_count == 0);
    expect(data_cookie == 0x13579bdfu && rt_thread_self() == RT_NULL);
    for (rt_uint32_t i = 0; i < 4u; i++) {
        stack_a[i] = 0xa55a0001u;
        stack_b[i] = 0xa55a0002u;
        stack_check[i] = 0xa55a0003u;
        stack_guard[i] = 0xc0decafeu;
    }
    rt_kprintf("M11.3 START\n");
    test_interrupt_requests();
    (void)rt_hw_interrupt_disable();
    rt_system_timer_init();
    rt_system_scheduler_init();
    rt_thread_idle_init();
    expect(rt_thread_init(&threads[0], "workerA", sched_entry, (void *)&arguments[0],
                          stack_a + 4, sizeof(stack_a) - 16u, 10, 5) == RT_EOK);
    expect(rt_thread_init(&threads[1], "workerB", sched_entry, (void *)&arguments[1],
                          stack_b + 4, sizeof(stack_b) - 16u, 10, 5) == RT_EOK);
    expect(rt_thread_init(&threads[2], "check", finish_entry, &threads[2],
                          stack_check + 4, sizeof(stack_check) - 16u, 20, 5) == RT_EOK);
    /* v4.1.1 puts a newly started peer at the ready-list head: start A last. */
    for (rt_uint32_t i = 3u; i > 0u; i--)
        expect(rt_thread_startup(&threads[i - 1u]) == RT_EOK);
    check_guards();
    rt_kprintf("KERNEL READY\n");
    __asm__ volatile ("csrw mstatus, %0" :: "r"(0x1880u) : "memory");
    rt_system_scheduler_start();
    fail(__LINE__);
}
