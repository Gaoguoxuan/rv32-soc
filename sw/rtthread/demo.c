#include "cpuport.h"

static struct rt_semaphore empty_slot;
static struct rt_semaphore full_slot;
static struct rt_mutex app_lock;

struct sample {
    rt_uint32_t sequence;
    rt_uint32_t value;
};

static volatile struct sample sample_slot;
static volatile rt_uint32_t produced;
static volatile rt_uint32_t consumed;
static volatile rt_uint32_t heartbeats;

static struct rt_thread threads[3];
/* Field addresses let the monitor inspect the kernel without hard-coded offsets. */
static volatile rt_ubase_t thread_locations[40];
static volatile rt_ubase_t mutex_locations[7];
static volatile rt_ubase_t sem_locations[8];
static rt_uint32_t stack_a[512]
    __attribute__((section(".thread_stack_a"), aligned(16), used));
static rt_uint32_t stack_b[512]
    __attribute__((section(".thread_stack_b"), aligned(16), used));
static rt_uint32_t stack_check[512]
    __attribute__((section(".thread_stack_check"), aligned(16), used));
static volatile rt_uint32_t stack_guard[4]
    __attribute__((section(".stack_guard"), aligned(16), used));
static volatile rt_uint32_t data_cookie = 0x13579bdfu;

static volatile rt_uint32_t idle_hits;

static void fail(rt_uint32_t line)
{
    (void)rt_hw_interrupt_disable();
    rt_hw_tick_stop();
    rt_kprintf("M11.8 FAIL line %u\n", line);

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
        expect(idle_bottom[i] == 0x23232323u);
    }
}

static void idle_hook(void)
{
    idle_hits++;
}

static void producer_entry(void *parameter)
{
    rt_tick_t next = rt_tick_get();

    expect(parameter == &threads[1]);

    while (1) {
        expect(rt_thread_delay_until(&next, 10u) == RT_EOK);
        expect(rt_sem_take(&empty_slot, RT_WAITING_FOREVER)
               == RT_EOK);

        expect(rt_mutex_take(&app_lock, RT_WAITING_FOREVER)
               == RT_EOK);

        produced++;
        sample_slot.sequence = produced;
        sample_slot.value = produced * 3u + 1u;

        expect(rt_mutex_release(&app_lock) == RT_EOK);
        expect(rt_sem_release(&full_slot) == RT_EOK);
    }
}

static void consumer_entry(void *parameter)
{
    expect(parameter == &threads[0]);

    while (1) {
        expect(rt_sem_take(&full_slot, RT_WAITING_FOREVER) == RT_EOK);
        expect(rt_mutex_take(&app_lock, RT_WAITING_FOREVER) == RT_EOK);

        rt_uint32_t sequence = sample_slot.sequence;
        rt_uint32_t value = sample_slot.value;

        expect(sequence == consumed + 1u);
        expect(sequence == produced);
        expect(value == sequence * 3u + 1u);
        consumed = sequence;
        check_guards();
        rt_kprintf("SAMPLE seq=%u value=%u tick=%u\n",
                   sequence, value, rt_tick_get());

        expect(rt_mutex_release(&app_lock) == RT_EOK);
        expect(rt_sem_release(&empty_slot) == RT_EOK);
    }
}

static void heartbeat_entry(void *parameter)
{
    rt_tick_t next = rt_tick_get();

    expect(parameter == &threads[2]);

    while (1) {
        expect(rt_thread_delay_until(&next, 25u) == RT_EOK);
        expect(rt_mutex_take(&app_lock, RT_WAITING_FOREVER) == RT_EOK);

        expect((rt_uint32_t)(produced - consumed) <= 1u);
        check_guards();
        heartbeats++;
        rt_kprintf("HB tick=%u produced=%u consumed=%u idle=%u\n",
                   rt_tick_get(), produced, consumed, idle_hits);

        expect(rt_mutex_release(&app_lock) == RT_EOK);
    }
}

int main(void)
{
    expect(produced == 0u && consumed == 0u && heartbeats == 0u);
    expect(sample_slot.sequence == 0u && sample_slot.value == 0u);
    expect(idle_hits == 0u && data_cookie == 0x13579bdfu);
    expect(rt_thread_self() == RT_NULL && rt_thread_switch_interrupt_flag == 0);
    for (rt_uint32_t i = 0; i < 4u; i++) {
        stack_a[i] = 0xa55a0001u;
        stack_b[i] = 0xa55a0002u;
        stack_check[i] = 0xa55a0003u;
        stack_guard[i] = 0xc0decafeu;
    }
    rt_kprintf("M11.8 START\n");
    rt_show_version();
    (void)rt_hw_interrupt_disable();
    rt_system_timer_init();
    rt_system_scheduler_init();
    rt_thread_idle_init();
    expect(rt_thread_idle_sethook(idle_hook) == RT_EOK);

    mutex_locations[0] = (rt_ubase_t)&app_lock.value;
    mutex_locations[1] = (rt_ubase_t)&app_lock.owner;
    mutex_locations[2] = (rt_ubase_t)&app_lock.hold;
    mutex_locations[3] = (rt_ubase_t)&app_lock.original_priority;
    mutex_locations[4] = (rt_ubase_t)&app_lock.parent.suspend_thread;
    mutex_locations[5] = (rt_ubase_t)&app_lock.parent.parent.type;
    mutex_locations[6] = (rt_ubase_t)&app_lock.parent.parent.flag;
    for (rt_uint32_t i = 0; i < 2u; i++) {
        struct rt_semaphore *sem = i == 0u ? &empty_slot : &full_slot;
        sem_locations[i * 4u] = (rt_ubase_t)&sem->value;
        sem_locations[i * 4u + 1u] = (rt_ubase_t)&sem->parent.suspend_thread;
        sem_locations[i * 4u + 2u] = (rt_ubase_t)&sem->parent.parent.type;
        sem_locations[i * 4u + 3u] = (rt_ubase_t)&sem->parent.parent.flag;
    }
    expect(rt_sem_init(&empty_slot, "empty", 1, RT_IPC_FLAG_PRIO) == RT_EOK);
    expect(rt_sem_init(&full_slot, "full", 0, RT_IPC_FLAG_PRIO) == RT_EOK);
    expect(rt_mutex_init(&app_lock, "app", RT_IPC_FLAG_PRIO) == RT_EOK);

    expect(rt_thread_init(&threads[0], "consume", consumer_entry, &threads[0],
                          stack_a + 4, sizeof(stack_a) - 16u, 10, 2) == RT_EOK);
    expect(rt_thread_init(&threads[1], "produce", producer_entry, &threads[1],
                          stack_b + 4, sizeof(stack_b) - 16u, 11, 2) == RT_EOK);
    expect(rt_thread_init(&threads[2], "heartbeat", heartbeat_entry, &threads[2],
                          stack_check + 4, sizeof(stack_check) - 16u, 12, 2) == RT_EOK);

    rt_thread_t idle_thread = rt_thread_idle_gethandler();
    expect(idle_thread->stack_size == 1024u);
    for (rt_uint32_t i = 0; i < 4u; i++) {
        rt_thread_t thread = i < 3u ? &threads[i] : idle_thread;
        thread_locations[i] = (rt_ubase_t)&thread->sp;
        thread_locations[i + 4u] = (rt_ubase_t)thread;
        thread_locations[i + 8u] = (rt_ubase_t)&thread->stat;
        thread_locations[i + 12u] = (rt_ubase_t)&thread->thread_timer.timeout_tick;
        thread_locations[i + 16u] = (rt_ubase_t)&thread->type;
        thread_locations[i + 20u] = (rt_ubase_t)&thread->tlist;
        thread_locations[i + 24u] = (rt_ubase_t)&thread->thread_timer.parent.flag;
        thread_locations[i + 28u] = (rt_ubase_t)&thread->thread_timer.row[0];
        thread_locations[i + 32u] = (rt_ubase_t)&thread->current_priority;
        thread_locations[i + 36u] = (rt_ubase_t)&thread->number_mask;
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
