#include "cpuport.h"

typedef struct {
    rt_uint32_t id;
    rt_uint32_t cookie;
} start_argument_t;

static const start_argument_t arguments[2] = {
    {1u, 0x13579bdfu}, {2u, 0x2468ace0u}
};
/* Real kernel structure, but this test calls only the CPU port directly. */
static struct rt_thread threads[2];
static rt_uint8_t probe[384] __attribute__((aligned(16)));
static rt_uint32_t stack_a[256]
    __attribute__((section(".thread_stack_a"), aligned(16), used));
static rt_uint32_t stack_b[256]
    __attribute__((section(".thread_stack_b"), aligned(16), used));
static volatile rt_uint32_t stack_guard[4]
    __attribute__((section(".stack_guard"), aligned(16), used));
static volatile rt_uint32_t current;
static volatile rt_uint32_t entries;
static volatile rt_uint32_t exits;
static volatile rt_uint32_t data_cookie = 0x13579bdfu;

static void start_entry(void *argument) __attribute__((noinline));
static void start_exit(void) __attribute__((noreturn, noinline));

static void fail(void) __attribute__((noreturn));
static void fail(void)
{
    (void)rt_hw_interrupt_disable();
    rt_kprintf("M11.2 FAIL\n");
    while (1) {
    }
}

static void expect(int condition)
{
    if (!condition)
        fail();
}

static rt_uint32_t read_status(void)
{
    rt_uint32_t status;
    __asm__ volatile ("csrr %0, mstatus" : "=r"(status) :: "memory");
    return status;
}

static void check_guards(void)
{
    for (rt_uint32_t i = 0; i < 4u; i++) {
        expect(stack_a[i] == 0xa55a0001u);
        expect(stack_b[i] == 0xa55a0002u);
        expect(stack_guard[i] == 0xc0decafeu);
        /* B's aligned stack top is 16 bytes below the array end. */
        expect(stack_b[252u + i] == 0xcdcdcdcdu);
    }
}

static void check_frame(rt_hw_stack_frame_t *frame, rt_ubase_t top,
                        const start_argument_t *argument)
{
    rt_ubase_t gp_value, tp_value;
    __asm__ volatile ("mv %0, gp" : "=r"(gp_value));
    __asm__ volatile ("mv %0, tp" : "=r"(tp_value));
    expect((rt_ubase_t)frame == top - sizeof(*frame));
    expect(((rt_ubase_t)frame & 15u) == 0);
    for (rt_uint32_t reg = 1; reg < 32u; reg++) {
        rt_uint32_t value = 0;
        switch (reg) {
        case 1: value = (rt_ubase_t)start_exit; break;
        case 2: value = top; break;
        case 3: value = gp_value; break;
        case 4: value = tp_value; break;
        case 10: value = (rt_ubase_t)argument; break;
        default: break;
        }
        expect(frame->gpr[reg - 1u] == value);
    }
    expect(frame->mepc == (rt_ubase_t)start_entry && frame->mstatus == 0x1880u);
    for (rt_uint32_t i = 0; i < 3u; i++)
        expect(frame->reserved[i] == 0);
}

static void test_alignment(void)
{
    /* For these 16 ends, the usable aligned top is always probe + 256. */
    for (rt_uint32_t offset = 0; offset < 16u; offset++) {
        rt_memset(probe, 0xa5, sizeof(probe));
        const start_argument_t *argument = &arguments[offset & 1u];
        rt_hw_stack_frame_t *frame = (rt_hw_stack_frame_t *)rt_hw_stack_init(
            (void *)start_entry, (void *)argument,
            probe + 256u + offset - sizeof(rt_ubase_t), (void *)start_exit);
        check_frame(frame, (rt_ubase_t)(probe + 256), argument);
        for (rt_uint32_t i = 0; i < sizeof(probe); i++) {
            if (i < 112u || i >= 256u)
                expect(probe[i] == 0xa5);
        }
    }
}

static void init_threads(void)
{
    for (rt_uint32_t i = 0; i < 256u; i++) {
        stack_a[i] = 0xcdcdcdcdu;
        stack_b[i] = 0xcdcdcdcdu;
    }
    for (rt_uint32_t i = 0; i < 4u; i++) {
        stack_a[i] = 0xa55a0001u;
        stack_b[i] = 0xa55a0002u;
    }

    threads[0].sp = rt_hw_stack_init((void *)start_entry, (void *)&arguments[0],
            (rt_uint8_t *)stack_a + 1024u - sizeof(rt_ubase_t), (void *)start_exit);
    threads[1].sp = rt_hw_stack_init((void *)start_entry, (void *)&arguments[1],
            (rt_uint8_t *)stack_b + 1020u - sizeof(rt_ubase_t), (void *)start_exit);
    check_frame(threads[0].sp, (rt_ubase_t)stack_a + 1024u, &arguments[0]);
    check_frame(threads[1].sp, (rt_ubase_t)stack_b + 1008u, &arguments[1]);

    /* Deliberately set saved MIE to exercise the assembly's pre-MRET mask. */
    ((rt_hw_stack_frame_t *)threads[1].sp)->mstatus |= 8u;
    check_guards();
}

static void start_entry(void *argument)
{
    const start_argument_t *self = argument;
    rt_uint32_t id = current;
    rt_uint32_t *stack = id == 1u ? stack_a : stack_b;
    rt_ubase_t top = (rt_ubase_t)stack + (id == 1u ? 1024u : 1008u);
    volatile rt_uint32_t local[4];

    expect(id >= 1u && id <= 2u && self == &arguments[id - 1u]);
    expect(self->id == id && read_status() == 0x1888u && entries == id - 1u);
    expect((rt_ubase_t)local >= (rt_ubase_t)(stack + 4));
    expect((rt_ubase_t)(local + 4) <= top);
    local[0] = self->cookie;
    local[1] = ~self->cookie;
    local[2] = id;
    local[3] = 0xface0000u | id;
    rt_kprintf(id == 1u ? "THREAD A START\n" : "THREAD B START\n");
    expect(local[0] == self->cookie && local[1] == ~self->cookie &&
           local[2] == id && local[3] == (0xface0000u | id));
    check_guards();
    entries++;
    /* C's normal return must use the ra installed by rt_hw_stack_init(). */
}

static void start_exit(void)
{
    expect(current >= 1u && current <= 2u && entries == current);
    expect(exits == current - 1u && read_status() == 0x1888u);
    exits++;
    rt_kprintf(current == 1u ? "THREAD A RETURN\n" : "THREAD B RETURN\n");
    if (current == 1u) {
        current = 2;
        rt_hw_context_switch_to((rt_ubase_t)&threads[1].sp);
        fail();
    }

    expect(entries == 2u && exits == 2u && data_cookie == 0x13579bdfu);
    check_guards();
    (void)rt_hw_interrupt_disable();
    rt_kprintf("STACK GUARD PASS\n");
    rt_kprintf("M11.2 PASS\n");
    while (1) {
    }
}

int main(void)
{
    expect(current == 0 && entries == 0 && exits == 0 && data_cookie == 0x13579bdfu);
    for (rt_uint32_t i = 0; i < 4u; i++)
        stack_guard[i] = 0xc0decafeu;
    rt_kprintf("M11.2 START\n");
    test_alignment();
    init_threads();
    rt_kprintf("STACK FRAME PASS\n");

    current = 1;
    /* Start with MIE=1 so the assembly must disable it before restoring. */
    __asm__ volatile ("csrw mstatus, %0" :: "r"(0x1888u) : "memory");
    __asm__ volatile ("csrw mepc, %0" :: "r"(0x1234u) : "memory");
    rt_hw_context_switch_to((rt_ubase_t)&threads[0].sp);
    fail();
}
