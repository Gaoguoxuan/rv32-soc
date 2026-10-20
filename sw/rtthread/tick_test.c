#include "cpuport.h"

#define STOP_TICK 12u

typedef struct {
    rt_uint32_t id;
    rt_uint32_t cookie;
} tick_argument_t;

static const tick_argument_t arguments[2] = {
    {1u, 0x13579bdfu}, {2u, 0x2468ace0u}
};
static struct rt_thread threads[3];
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
static volatile rt_uint32_t progress[2];
static volatile rt_uint32_t checksums[2];
static volatile rt_uint32_t normal_returns;
static volatile rt_uint32_t stopped_tick;
static volatile rt_uint32_t data_cookie = 0x13579bdfu;

static void tick_entry(void *argument) __attribute__((noinline));
static void finish_entry(void *argument) __attribute__((noinline, noreturn));

static void fail(rt_uint32_t line) __attribute__((noreturn));
static void fail(rt_uint32_t line)
{
    (void)rt_hw_interrupt_disable();
    rt_hw_tick_stop();
    rt_kprintf("M11.4 FAIL line %u\n", line);
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

static void tick_entry(void *argument)
{
    const tick_argument_t *self = argument;
    rt_uint32_t id = self->id;
    rt_uint32_t count = 0;
    rt_uint32_t sum = self->cookie;
    rt_uint32_t step = id == 1u ? 3u : 5u;
    volatile rt_uint32_t local[4];
    expect(id >= 1u && id <= 2u && self == &arguments[id - 1u]);
    expect(rt_thread_self() == &threads[id - 1u] && read_status() == 0x1888u);
    for (rt_uint32_t i = 0; i < 4u; i++) local[i] = self->cookie ^ (i << 16);

    /* No yield, delay, or blocking call: only the hardware timer can run a peer. */
    while (rt_tick_get() < STOP_TICK) {
        count++;
        sum += step;
        progress[id - 1u] = count;
    }

    rt_base_t level = rt_hw_interrupt_disable();
    rt_hw_tick_stop();
    stopped_tick = rt_tick_get();
    expect(level == 8 && stopped_tick == STOP_TICK && count != 0);
    expect(rt_thread_self() == &threads[id - 1u]);
    expect(normal_returns == id - 1u && rt_interrupt_get_nest() == 0);
    expect(sum == self->cookie + count + (count << (id == 1u ? 1u : 2u)));
    for (rt_uint32_t i = 0; i < 4u; i++) expect(local[i] == (self->cookie ^ (i << 16)));
    checksums[id - 1u] = sum;
    normal_returns++;
    check_guards();
    rt_kprintf("THREAD %c RETURN\n", id == 1u ? 'A' : 'B');
    rt_hw_interrupt_enable(level);
    /* Return to the real kernel's _thread_exit(). */
}

static void finish_entry(void *argument)
{
    expect(argument == &threads[2] && rt_thread_self() == &threads[2]);
    expect(read_status() == 0x1888u && rt_tick_get() == STOP_TICK);
    expect(normal_returns == 2u && stopped_tick == STOP_TICK);
    expect(progress[0] != 0 && progress[1] != 0);
    for (rt_uint32_t i = 0; i < 2u; i++)
        expect(checksums[i] == arguments[i].cookie + progress[i] + (progress[i] << (i + 1u)));
    expect((threads[0].stat & RT_THREAD_STAT_MASK) == RT_THREAD_CLOSE);
    expect((threads[1].stat & RT_THREAD_STAT_MASK) == RT_THREAD_CLOSE);
    expect((threads[2].stat & RT_THREAD_STAT_MASK) == RT_THREAD_RUNNING);
    expect(rt_interrupt_get_nest() == 0 && rt_thread_switch_interrupt_flag == 0);
    expect(data_cookie == 0x13579bdfu);
    check_guards();
    (void)rt_hw_interrupt_disable();
    rt_kprintf("TICK PREEMPT PASS\n");
    rt_kprintf("IRQ NEST PASS\n");
    rt_kprintf("STACK GUARD PASS\n");
    rt_kprintf("M11.4 PASS\n");
    while (1) {
    }
}

int main(void)
{
    expect(progress[0] == 0 && progress[1] == 0 && checksums[0] == 0 && checksums[1] == 0);
    expect(normal_returns == 0 && stopped_tick == 0 && data_cookie == 0x13579bdfu);
    expect(rt_thread_self() == RT_NULL && rt_thread_switch_interrupt_flag == 0);
    for (rt_uint32_t i = 0; i < 4u; i++) {
        stack_a[i] = 0xa55a0001u;
        stack_b[i] = 0xa55a0002u;
        stack_check[i] = 0xa55a0003u;
        stack_guard[i] = 0xc0decafeu;
    }
    rt_kprintf("M11.4 START\n");
    (void)rt_hw_interrupt_disable();
    rt_system_timer_init();
    rt_system_scheduler_init();
    rt_thread_idle_init();
    expect(rt_thread_init(&threads[0], "workerA", tick_entry, (void *)&arguments[0],
                          stack_a + 4, sizeof(stack_a) - 16u, 10, 2) == RT_EOK);
    expect(rt_thread_init(&threads[1], "workerB", tick_entry, (void *)&arguments[1],
                          stack_b + 4, sizeof(stack_b) - 16u, 10, 2) == RT_EOK);
    expect(rt_thread_init(&threads[2], "check", finish_entry, &threads[2],
                          stack_check + 4, sizeof(stack_check) - 16u, 20, 2) == RT_EOK);
    for (rt_uint32_t i = 3u; i > 0u; i--)
        expect(rt_thread_startup(&threads[i - 1u]) == RT_EOK);
    check_guards();
    rt_kprintf("KERNEL READY\n");
    /* Exercise a carry into mtimecmp's high word at the first deadline. */
    *(volatile rt_uint32_t *)0x30000004u = 0;
    *(volatile rt_uint32_t *)0x30000000u = 0xffffe000u;
    rt_hw_tick_init();
    expect((read_status() & 8u) == 0);
    __asm__ volatile ("csrw mstatus, %0" :: "r"(0x1880u) : "memory");
    rt_system_scheduler_start();
    fail(__LINE__);
}
