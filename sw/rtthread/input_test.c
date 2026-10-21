#include "cpuport.h"

extern char rt_hw_console_getchar(void);

static const rt_uint8_t input_bytes[] = {
    'A', 0x00, 0xff, 0x80, 'R', 'V', '\n', 'Z'
};
static struct rt_thread threads[3];
/* TCB pointers, then addresses of the receiver's state and timeout fields. */
static volatile rt_ubase_t input_locations[6];
static rt_uint32_t stack_a[512]
    __attribute__((section(".thread_stack_a"), aligned(16), used));
static rt_uint32_t stack_b[512]
    __attribute__((section(".thread_stack_b"), aligned(16), used));
static rt_uint32_t stack_check[512]
    __attribute__((section(".thread_stack_check"), aligned(16), used));
static volatile rt_uint32_t stack_guard[4]
    __attribute__((section(".stack_guard"), aligned(16), used));
static volatile rt_uint32_t received;
static volatile rt_uint8_t received_bytes[8];
static volatile rt_tick_t received_ticks[8];
static volatile rt_uint32_t heartbeats;
static volatile rt_uint32_t before_input_beats;
static volatile rt_uint32_t gap_beats;
static volatile rt_uint32_t idle_hits;
static volatile rt_uint32_t receiver_done;
static volatile rt_uint32_t cleanup_done;

static void fail(rt_uint32_t line)
{
    (void)rt_hw_interrupt_disable();
    rt_hw_tick_stop();
    rt_kprintf("RT-THREAD RX FAIL line %u\n", line);
    while (1) { }
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

static void receiver_cleanup(struct rt_thread *thread)
{
    expect(thread == &threads[0]);
    expect(rt_thread_self() == rt_thread_idle_gethandler());
    expect(receiver_done == 1u);
    cleanup_done = 1u;
}

static void receiver_entry(void *parameter)
{
    expect(parameter == &threads[0]);
    for (rt_uint32_t i = 0; i < sizeof(input_bytes); i++) {
        rt_uint8_t value = (rt_uint8_t)rt_hw_console_getchar();
        rt_tick_t tick = rt_tick_get();
        expect(value == input_bytes[i]);
        expect(rt_thread_self() == &threads[0]);
        expect(rt_interrupt_get_nest() == 0);
        received_bytes[i] = value;
        received_ticks[i] = tick;
        received = i + 1u;
        if (i < 7u)
            expect(tick == 5u);
        else
            expect(tick == 11u);
        check_guards();
    }
    receiver_done = 1u;
}

static void heartbeat_entry(void *parameter)
{
    rt_tick_t next = rt_tick_get();
    expect(parameter == &threads[1]);
    while (1) {
        expect(rt_thread_delay_until(&next, 2u) == RT_EOK);
        heartbeats++;
        if (received == 0u) before_input_beats++;
        if (received == 7u) gap_beats++;
    }
}

static void finish_entry(void *parameter)
{
    expect(parameter == &threads[2]);
    expect(rt_thread_delay(16u) == RT_EOK);
    (void)rt_hw_interrupt_disable();
    rt_hw_tick_stop();
    expect(rt_tick_get() == 16u);
    expect(received == 8u && receiver_done == 1u && cleanup_done == 1u);
    expect(heartbeats == 8u && before_input_beats == 2u && gap_beats == 3u);
    expect(idle_hits != 0u);
    expect(rt_interrupt_get_nest() == 0 && rt_thread_switch_interrupt_flag == 0);
    expect(rt_object_get_type((rt_object_t)&threads[0]) == RT_Object_Class_Null);
    check_guards();
    for (rt_uint32_t i = 0; i < sizeof(input_bytes); i++) {
        expect(received_bytes[i] == input_bytes[i]);
        expect(received_ticks[i] == (i < 7u ? 5u : 11u));
        rt_kprintf("RX BYTE %u=%02x tick=%u\n", i,
                   (rt_uint32_t)received_bytes[i], received_ticks[i]);
    }
    rt_kprintf("HEARTBEAT PASS count=%u before=%u gap=%u\n",
               heartbeats, before_input_beats, gap_beats);
    rt_kprintf("IDLE/STACK/CLEANUP PASS\n");
    rt_kprintf("RT-THREAD RX PASS\n");
    while (1) { }
}

int main(void)
{
    expect(received == 0u && heartbeats == 0u && idle_hits == 0u);
    expect(receiver_done == 0u && cleanup_done == 0u);
    expect(rt_thread_self() == RT_NULL);
    for (rt_uint32_t i = 0; i < 4u; i++) {
        stack_a[i] = 0xa55a0001u;
        stack_b[i] = 0xa55a0002u;
        stack_check[i] = 0xa55a0003u;
        stack_guard[i] = 0xc0decafeu;
    }
    rt_kprintf("RT-THREAD RX START\n");
    (void)rt_hw_interrupt_disable();
    rt_system_timer_init();
    rt_system_scheduler_init();
    rt_thread_idle_init();
    expect(rt_thread_idle_sethook(idle_hook) == RT_EOK);
    expect(rt_thread_init(&threads[0], "rx", receiver_entry, &threads[0],
                          stack_a + 4, sizeof(stack_a) - 16u, 10, 2) == RT_EOK);
    expect(rt_thread_init(&threads[1], "beat", heartbeat_entry, &threads[1],
                          stack_b + 4, sizeof(stack_b) - 16u, 11, 2) == RT_EOK);
    expect(rt_thread_init(&threads[2], "check", finish_entry, &threads[2],
                          stack_check + 4, sizeof(stack_check) - 16u, 20, 2) == RT_EOK);
    threads[0].cleanup = receiver_cleanup;
    for (rt_uint32_t i = 0; i < 3u; i++) {
        input_locations[i] = (rt_ubase_t)&threads[i];
        expect(rt_thread_startup(&threads[i]) == RT_EOK);
    }
    input_locations[3] = (rt_ubase_t)rt_thread_idle_gethandler();
    input_locations[4] = (rt_ubase_t)&threads[0].stat;
    input_locations[5] = (rt_ubase_t)&threads[0].thread_timer.timeout_tick;
    check_guards();
    rt_kprintf("KERNEL READY\n");
    rt_hw_tick_init();
    __asm__ volatile ("csrw mstatus, %0" :: "r"(0x1880u) : "memory");
    rt_system_scheduler_start();
    fail(__LINE__);
}
