#include "cpuport.h"

static struct rt_semaphore event_sem;
static struct rt_thread threads[3];
/* Field addresses let the monitor inspect the kernel without hard-coded offsets. */
static volatile rt_ubase_t thread_locations[32];
static volatile rt_ubase_t sem_locations[3];
static rt_uint32_t stack_a[512]
    __attribute__((section(".thread_stack_a"), aligned(16), used));
static rt_uint32_t stack_b[512]
    __attribute__((section(".thread_stack_b"), aligned(16), used));
static rt_uint32_t stack_check[512]
    __attribute__((section(".thread_stack_check"), aligned(16), used));
static volatile rt_uint32_t stack_guard[4]
    __attribute__((section(".stack_guard"), aligned(16), used));
static volatile rt_uint32_t data_cookie = 0x13579bdfu;

static volatile rt_uint32_t produced;
static volatile rt_uint32_t consumed;
static volatile rt_uint32_t release_returned;
static volatile rt_uint32_t timeout_ok;
static volatile rt_uint32_t credit_ok;
static volatile rt_uint32_t normal_returns;
static volatile rt_uint32_t cleanup_mask;
static volatile rt_uint32_t idle_hits;

static void fail(rt_uint32_t line)
{
    (void)rt_hw_interrupt_disable();
    rt_hw_tick_stop();
    rt_kprintf("M11.6 FAIL line %u\n", line);

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

static void mark_returned(void)
{
    rt_base_t level = rt_hw_interrupt_disable();
    normal_returns++;
    rt_hw_interrupt_enable(level);
}

static void consumer_entry(void *parameter)
{
    volatile rt_uint32_t local = 0xcafe1234u;

    expect(parameter == &threads[0]);

    /* 空信号量：不等待，立即返回超时。 */
    expect(rt_sem_take(&event_sem, RT_WAITING_NO) == -RT_ETIMEOUT);
    rt_kprintf("SEM EMPTY PASS\n");

    for (rt_uint32_t i = 1; i <= 3u; i++) {
        rt_int32_t wait = i == 1u ? RT_WAITING_FOREVER : 5;
        rt_err_t result = rt_sem_take(&event_sem, wait);

        expect(result == RT_EOK);
        expect(local == 0xcafe1234u);
        check_guards();
        expect(produced == i);

        /* 生产者的 release 此时应该还没有返回。 */
        expect(release_returned == i - 1u);

        /* 有等待者时，释放直接交给等待者，计数仍为零。 */
        expect(event_sem.value == 0);
        consumed = i;
        rt_kprintf("CONSUME %u\n", i);
    }

    /* 生产者不再释放，等待两个 tick 后应超时。 */
    rt_tick_t before = rt_tick_get();
    rt_err_t result = rt_sem_take(&event_sem, 2);

    expect(result == -RT_ETIMEOUT);
    expect((rt_tick_t)(rt_tick_get() - before) >= 2u);
    expect(local == 0xcafe1234u);
    expect(event_sem.value == 0);
    timeout_ok = 1;
    rt_kprintf("SEM TIMEOUT PASS\n");

    /* 无等待者时，释放增加计数，随后可以立即取走。 */
    expect(rt_sem_release(&event_sem) == RT_EOK);
    expect(event_sem.value == 1);
    expect(rt_sem_take(&event_sem, RT_WAITING_NO) == RT_EOK);
    expect(event_sem.value == 0);
    expect(rt_sem_take(&event_sem, RT_WAITING_NO) == -RT_ETIMEOUT);
    credit_ok = 1;
    rt_kprintf("SEM COUNT PASS\n");

    mark_returned();
}

static void producer_entry(void *parameter)
{
    expect(parameter == &threads[1]);

    for (rt_uint32_t i = 1; i <= 3u; i++) {
        expect(rt_thread_delay(2u) == RT_EOK);

        produced = i;
        expect(rt_sem_release(&event_sem) == RT_EOK);

        /* 高优先级消费者应已运行并消费本次通知。 */
        expect(consumed == i);
        release_returned = i;
        rt_kprintf("RELEASE RETURN %u\n", i);
    }

    mark_returned();
}

static void finish_entry(void *parameter)
{
    expect(parameter == &threads[2]);
    expect(rt_thread_delay(12u) == RT_EOK);

    (void)rt_hw_interrupt_disable();
    rt_hw_tick_stop();

    expect(produced == 3u && consumed == 3u);
    expect(release_returned == 3u);
    expect(timeout_ok == 1u && credit_ok == 1u);
    expect(normal_returns == 2u);
    expect(cleanup_mask == 3u && idle_hits != 0);
    expect(rt_interrupt_get_nest() == 0);
    expect(rt_thread_switch_interrupt_flag == 0);
    expect(data_cookie == 0x13579bdfu);
    for (rt_uint32_t i = 0; i < 2u; i++) {
        expect((threads[i].stat & RT_THREAD_STAT_MASK) == RT_THREAD_CLOSE);
        expect(rt_object_get_type((rt_object_t)&threads[i]) == RT_Object_Class_Null);
    }
    check_guards();
    expect(event_sem.value == 0);
    expect(rt_list_isempty(&event_sem.parent.suspend_thread));

    expect(rt_sem_detach(&event_sem) == RT_EOK);
    expect(rt_object_get_type(&event_sem.parent.parent)
           == RT_Object_Class_Null);

    rt_kprintf("SEM SYNC PASS\n");
    rt_kprintf("IDLE CLEANUP PASS\n");
    rt_kprintf("STACK GUARD PASS\n");
    rt_kprintf("M11.6 PASS\n");

    while (1) {
    }
}

int main(void)
{
    expect(produced == 0 && consumed == 0 && release_returned == 0);
    expect(timeout_ok == 0 && credit_ok == 0 && normal_returns == 0);
    expect(cleanup_mask == 0 && idle_hits == 0 && data_cookie == 0x13579bdfu);
    expect(rt_thread_self() == RT_NULL && rt_thread_switch_interrupt_flag == 0);
    for (rt_uint32_t i = 0; i < 4u; i++) {
        stack_a[i] = 0xa55a0001u;
        stack_b[i] = 0xa55a0002u;
        stack_check[i] = 0xa55a0003u;
        stack_guard[i] = 0xc0decafeu;
    }
    rt_kprintf("M11.6 START\n");
    (void)rt_hw_interrupt_disable();
    rt_system_timer_init();
    rt_system_scheduler_init();
    rt_thread_idle_init();
    expect(rt_thread_idle_sethook(idle_hook) == RT_EOK);
    expect(rt_sem_init(&event_sem, "event", 0, RT_IPC_FLAG_PRIO) == RT_EOK);
    expect(rt_thread_init(&threads[0], "consume", consumer_entry, &threads[0],
                          stack_a + 4, sizeof(stack_a) - 16u, 10, 2) == RT_EOK);
    expect(rt_thread_init(&threads[1], "produce", producer_entry, &threads[1],
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
        thread_locations[i + 20u] = (rt_ubase_t)&thread->tlist;
        thread_locations[i + 24u] = (rt_ubase_t)&thread->thread_timer.parent.flag;
        thread_locations[i + 28u] = (rt_ubase_t)&thread->thread_timer.row[0];
    }
    sem_locations[0] = (rt_ubase_t)&event_sem.value;
    sem_locations[1] = (rt_ubase_t)&event_sem.parent.suspend_thread;
    sem_locations[2] = (rt_ubase_t)&event_sem.parent.parent.type;
    for (rt_uint32_t i = 0; i < 3u; i++)
        expect(rt_thread_startup(&threads[i]) == RT_EOK);
    check_guards();
    rt_kprintf("KERNEL READY\n");
    rt_hw_tick_init();
    __asm__ volatile ("csrw mstatus, %0" :: "r"(0x1880u) : "memory");
    rt_system_scheduler_start();
    fail(__LINE__);
}
