#include "cpuport.h"

static struct rt_mutex resource_lock;
static struct rt_thread threads[3];
/* Field addresses let the monitor inspect the kernel without hard-coded offsets. */
static volatile rt_ubase_t thread_locations[40];
static volatile rt_ubase_t mutex_locations[7];
static rt_uint32_t stack_a[512]
    __attribute__((section(".thread_stack_a"), aligned(16), used));
static rt_uint32_t stack_b[512]
    __attribute__((section(".thread_stack_b"), aligned(16), used));
static rt_uint32_t stack_check[512]
    __attribute__((section(".thread_stack_check"), aligned(16), used));
static volatile rt_uint32_t stack_guard[4]
    __attribute__((section(".stack_guard"), aligned(16), used));
static volatile rt_uint32_t data_cookie = 0x13579bdfu;

static volatile rt_uint32_t high_waiting;
static volatile rt_uint32_t inherit_ok;
static volatile rt_uint32_t high_done;
static volatile rt_uint32_t medium_runs;
static volatile rt_uint32_t low_release_returned;
static volatile rt_uint32_t normal_returns;
static volatile rt_uint32_t cleanup_mask;
static volatile rt_uint32_t idle_hits;

static void fail(rt_uint32_t line)
{
    (void)rt_hw_interrupt_disable();
    rt_hw_tick_stop();
    rt_kprintf("M11.7 FAIL line %u\n", line);

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

static void high_entry(void *parameter)
{
    expect(parameter == &threads[0]);
    expect(rt_thread_delay(2u) == RT_EOK);

    expect(resource_lock.owner == &threads[1]);
    expect(resource_lock.hold == 2u);

    /* H 不是持有者，不能释放 L 的锁。 */
    expect(rt_mutex_release(&resource_lock) == -RT_ERROR);

    /* 不等待获取失败，此时不应提升 L 的优先级。 */
    expect(rt_mutex_take(&resource_lock, RT_WAITING_NO)
           == -RT_ETIMEOUT);
    expect(resource_lock.owner == &threads[1]);
    expect(resource_lock.hold == 2u);
    expect(resource_lock.value == 0u);
    expect(threads[1].current_priority == 12u);

    high_waiting = 1u;
    rt_kprintf("HIGH WAIT\n");

    expect(rt_mutex_take(&resource_lock, RT_WAITING_FOREVER)
           == RT_EOK);

    expect(inherit_ok == 1u);
    expect(resource_lock.owner == &threads[0]);
    expect(resource_lock.hold == 1u);
    expect(resource_lock.value == 0u);
    expect(resource_lock.original_priority == 10u);

    /* L 已恢复优先级，但它的最后一次 release 尚未返回。 */
    expect(threads[1].current_priority == 12u);
    expect(low_release_returned == 0u);
    expect(medium_runs == 0u);
    check_guards();
    rt_kprintf("HIGH ACQUIRE PASS\n");

    expect(rt_mutex_release(&resource_lock) == RT_EOK);
    high_done = 1u;
    mark_returned();
}

static void low_entry(void *parameter)
{
    volatile rt_uint32_t local = 0xcafe1234u;

    expect(parameter == &threads[1]);

    expect(rt_mutex_take(&resource_lock, RT_WAITING_NO) == RT_EOK);
    expect(rt_mutex_take(&resource_lock, RT_WAITING_NO) == RT_EOK);
    expect(resource_lock.owner == &threads[1]);
    expect(resource_lock.hold == 2u);
    expect(resource_lock.original_priority == 12u);
    rt_kprintf("LOW LOCKED\n");

    /* 保持就绪，等待真实 tick 唤醒 H、M。 */
    while (high_waiting == 0u) {
    }

    expect(threads[1].current_priority == 10u);
    expect(resource_lock.original_priority == 12u);
    expect((threads[0].stat & RT_THREAD_STAT_MASK)
           == RT_THREAD_SUSPEND);
    expect((threads[2].stat & RT_THREAD_STAT_MASK)
           == RT_THREAD_READY);
    expect(medium_runs == 0u);
    expect(local == 0xcafe1234u);

    inherit_ok = 1u;
    rt_kprintf("LOW INHERIT PASS\n");

    /* 只减少递归次数，仍持锁并保持继承的优先级。 */
    expect(rt_mutex_release(&resource_lock) == RT_EOK);
    expect(resource_lock.owner == &threads[1]);
    expect(resource_lock.hold == 1u);
    expect(threads[1].current_priority == 10u);
    expect(medium_runs == 0u && high_done == 0u);
    rt_kprintf("LOW RECURSIVE PASS\n");

    /* 最后一次释放将锁交给 H，并触发调度。 */
    expect(rt_mutex_release(&resource_lock) == RT_EOK);

    expect(high_done == 1u);
    expect(medium_runs == 1u);
    expect(threads[1].current_priority == 12u);
    expect(local == 0xcafe1234u);
    check_guards();

    low_release_returned = 1u;
    rt_kprintf("LOW RELEASE RETURN\n");
    mark_returned();
}

static void finish_entry(void *parameter)
{
    expect(parameter == &threads[2]);
    expect(rt_thread_delay(2u) == RT_EOK);

    expect(inherit_ok == 1u && high_done == 1u);
    expect(low_release_returned == 0u);
    medium_runs = 1u;
    rt_kprintf("MID READY PASS\n");

    /* 让 L 返回，让 idle 清理 H、L。 */
    expect(rt_thread_delay(6u) == RT_EOK);

    (void)rt_hw_interrupt_disable();
    rt_hw_tick_stop();

    expect(high_waiting == 1u && inherit_ok == 1u);
    expect(high_done == 1u && medium_runs == 1u);
    expect(low_release_returned == 1u);
    expect(normal_returns == 2u);
    expect(cleanup_mask == 3u && idle_hits != 0u);
    expect(rt_interrupt_get_nest() == 0);
    expect(rt_thread_switch_interrupt_flag == 0);
    expect(data_cookie == 0x13579bdfu);

    for (rt_uint32_t i = 0; i < 2u; i++) {
        expect((threads[i].stat & RT_THREAD_STAT_MASK)
               == RT_THREAD_CLOSE);
        expect(rt_object_get_type((rt_object_t)&threads[i])
               == RT_Object_Class_Null);
    }

    check_guards();
    expect(resource_lock.owner == RT_NULL);
    expect(resource_lock.hold == 0u);
    expect(resource_lock.value == 1u);
    expect(resource_lock.original_priority == 0xffu);
    expect(rt_list_isempty(&resource_lock.parent.suspend_thread));

    expect(rt_mutex_detach(&resource_lock) == RT_EOK);
    expect(rt_object_get_type(&resource_lock.parent.parent)
           == RT_Object_Class_Null);

    rt_kprintf("MUTEX FREE PASS\n");
    rt_kprintf("IDLE CLEANUP PASS\n");
    rt_kprintf("STACK GUARD PASS\n");
    rt_kprintf("M11.7 PASS\n");

    while (1) {
    }
}

int main(void)
{
    expect(high_waiting == 0u && inherit_ok == 0u);
    expect(high_done == 0u && medium_runs == 0u);
    expect(low_release_returned == 0u && normal_returns == 0u);
    expect(cleanup_mask == 0u && idle_hits == 0u);
    expect(data_cookie == 0x13579bdfu);
    expect(rt_thread_self() == RT_NULL && rt_thread_switch_interrupt_flag == 0);
    for (rt_uint32_t i = 0; i < 4u; i++) {
        stack_a[i] = 0xa55a0001u;
        stack_b[i] = 0xa55a0002u;
        stack_check[i] = 0xa55a0003u;
        stack_guard[i] = 0xc0decafeu;
    }
    rt_kprintf("M11.7 START\n");
    (void)rt_hw_interrupt_disable();
    rt_system_timer_init();
    rt_system_scheduler_init();
    rt_thread_idle_init();
    expect(rt_thread_idle_sethook(idle_hook) == RT_EOK);
    mutex_locations[0] = (rt_ubase_t)&resource_lock.value;
    mutex_locations[1] = (rt_ubase_t)&resource_lock.owner;
    mutex_locations[2] = (rt_ubase_t)&resource_lock.hold;
    mutex_locations[3] = (rt_ubase_t)&resource_lock.original_priority;
    mutex_locations[4] = (rt_ubase_t)&resource_lock.parent.suspend_thread;
    mutex_locations[5] = (rt_ubase_t)&resource_lock.parent.parent.type;
    mutex_locations[6] = (rt_ubase_t)&resource_lock.parent.parent.flag;
    expect(rt_mutex_init(&resource_lock, "resource", RT_IPC_FLAG_PRIO) == RT_EOK);
    expect(rt_thread_init(&threads[0], "high", high_entry, &threads[0],
                        stack_a + 4, sizeof(stack_a) - 16u,
                        10, 2) == RT_EOK);

    expect(rt_thread_init(&threads[1], "low", low_entry, &threads[1],
                        stack_b + 4, sizeof(stack_b) - 16u,
                        12, 2) == RT_EOK);
    expect(rt_thread_init(&threads[2], "middle", finish_entry, &threads[2],
                        stack_check + 4, sizeof(stack_check) - 16u,
                        11, 2) == RT_EOK);
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
