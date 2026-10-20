#include "trap_frame.h"
#include "../common/irq.h"

#define MMIO32(address) (*(volatile uint32_t *)(uintptr_t)(address))
#define UART_TXDATA    MMIO32(0x20000000u)
#define MTIME_LO       MMIO32(0x30000000u)
#define MTIME_HI       MMIO32(0x30000004u)
#define MTIMECMP_LO    MMIO32(0x30000008u)
#define MTIMECMP_HI    MMIO32(0x3000000cu)
#define PERIOD        UINT64_C(8192)
#define STACK_WORDS    256u
#define RUN_SLICES     3u

typedef struct {
    uint32_t id;                 /* main=0, A=1, B=2 */
    volatile uint32_t done;
    volatile uint32_t slices;
    volatile uint32_t progress;
    volatile uint32_t checksum;
} thread_t;

static thread_t threads[2];
static trap_frame_t *frames[3];
static volatile uint32_t current;
static volatile uint32_t ticks;
static volatile uint32_t switches;
static volatile uint32_t exits;
static volatile uint32_t background;
static volatile uint32_t data_cookie = UINT32_C(0x13579bdf);
static uint64_t next_deadline;

static uint32_t stack_a[STACK_WORDS]
    __attribute__((section(".stack_a"), aligned(16), used));
static uint32_t stack_b[STACK_WORDS]
    __attribute__((section(".stack_b"), aligned(16), used));
static volatile uint32_t main_stack_guard[4]
    __attribute__((section(".main_guard"), aligned(16), used));

static void uart_puts(const char *text)
{
    while (*text != '\0')
        UART_TXDATA = (uint32_t)(unsigned char)*text++;
}

static void fail(const char *message) __attribute__((noreturn));
static void fail(const char *message)
{
    __asm__ volatile ("csrc mstatus, %0" :: "r"(8u) : "memory");
    uart_puts(message);
    while (1) {
    }
}

static uint64_t timer_read(void)
{
    uint32_t before, low, after;
    do {
        before = MTIME_HI;
        low = MTIME_LO;
        after = MTIME_HI;
    } while (before != after);
    return ((uint64_t)before << 32) | low;
}

static void timer_set_compare(uint64_t value)
{
    MTIMECMP_LO = UINT32_MAX;
    MTIMECMP_HI = (uint32_t)(value >> 32);
    MTIMECMP_LO = (uint32_t)value;
}

static void check_guards(void)
{
    for (uint32_t i = 0; i < 4u; i++) {
        if (stack_a[i] != UINT32_C(0xa55a0001) ||
            stack_b[i] != UINT32_C(0xa55a0002) ||
            main_stack_guard[i] != UINT32_C(0xc0decafe))
            fail("STACK GUARD FAIL\n");
    }
}

void thread_exit(void) __attribute__((noreturn, noinline));
void thread_exit(void)
{
    irq_state_t state = irq_save();

    if (current < 1u || current > 2u ||
        threads[current - 1u].done)
        fail("THREAD EXIT FAIL\n");

    exits++;
    threads[current - 1u].done = 1;

    irq_restore(state);

    /* 等待下一次定时器中断切走。 */
    while (1) {
    }
}

static void thread_entry(void *argument) __attribute__((noinline));
static void thread_entry(void *argument)
{
    thread_t *self = argument;
    uint32_t id = current;
    uint32_t seed = UINT32_C(0x12340000) | id;
    uint32_t value = seed;
    uint32_t count = 0;
    uint32_t step = id == 1u ? 3u : 5u;
    volatile uint32_t local[4];
    uint32_t *stack = id == 1u ? stack_a : stack_b;

    if (id < 1u || id > 2u || self != &threads[id - 1u] ||
        self->id != id || (uintptr_t)local < (uintptr_t)(stack + 4) ||
        (uintptr_t)(local + 4) > (uintptr_t)(stack + STACK_WORDS))
        fail("THREAD START FAIL\n");

    /* No yield or context_switch: only timer interrupts switch these loops. */
    while (self->slices < RUN_SLICES) {
        value += step;
        count++;
        local[0] = value;
        local[1] = ~value;
        local[2] = seed;
        local[3] = value ^ seed;
        if (current != id || local[0] != value || local[1] != ~value ||
            local[2] != seed || local[3] != (value ^ seed))
            fail("LOCAL STATE FAIL\n");
        self->progress = count;
    }
    self->checksum = value;
    /* Ordinary C return goes to the ra installed in the initial trap frame. */
}

static void thread_init(uint32_t id)
{
    uint32_t *stack = id == 1u ? stack_a : stack_b;
    uint32_t gp_value, tp_value;
    trap_frame_t *frame = (trap_frame_t *)(stack + STACK_WORDS - 36u);

    for (uint32_t i = 0; i < STACK_WORDS; i++)
        stack[i] = UINT32_C(0xcdcdcdcd);
    for (uint32_t i = 0; i < 4u; i++)
        stack[i] = UINT32_C(0xa55a0000) | id;
    threads[id - 1u].id = id;

    /* Distinct register seeds also let the testbench verify the first MRET. */
    for (uint32_t reg = 1; reg < 32u; reg++)
        frame->gpr[reg - 1u] = UINT32_C(0x5a000000) | (id << 16) | reg;
    __asm__ volatile ("mv %0, gp" : "=r"(gp_value));
    __asm__ volatile ("mv %0, tp" : "=r"(tp_value));
    frame->gpr[0] = (uint32_t)(uintptr_t)thread_exit;  /* ra */
    frame->gpr[1] = (uint32_t)(uintptr_t)(stack + STACK_WORDS); /* sp */
    frame->gpr[2] = gp_value;
    frame->gpr[3] = tp_value;
    frame->gpr[9] = (uint32_t)(uintptr_t)&threads[id - 1u]; /* a0 */
    frame->mepc = (uint32_t)(uintptr_t)thread_entry;
    frame->mstatus = UINT32_C(0x1880); /* MPP=M, MPIE=1, MIE=0 */
    for (uint32_t i = 0; i < 3u; i++)
        frame->reserved[i] = 0;
    frames[id] = frame;
}

trap_frame_t *trap_dispatch(trap_frame_t *frame, uint32_t cause, uint32_t tval)
{
    uint32_t status;
    uint32_t next;
    __asm__ volatile ("csrr %0, mstatus" : "=r"(status));
    if (cause != UINT32_C(0x80000007) || tval != 0 || current > 2u ||
        ((uintptr_t)frame & 15u) != 0 ||
        frame->gpr[1] != (uintptr_t)frame + sizeof(*frame) ||
        (frame->mepc & 3u) != 0 || frame->mepc >= 0x10000u ||
        (status & 0x1888u) != 0x1880u || frame->mstatus != status)
        fail("TRAP FRAME FAIL\n");
    check_guards();
    frames[current] = frame;
    ticks++;
    if (ticks > 32u)
        fail("SCHEDULER TIMEOUT\n");

    /* First prove that returning the same frame resumes main correctly. */
    if (ticks == 1u) {
        next = 0;
    } else if (current == 0u) {
        next = 1;
    } else {
        threads[current - 1u].slices++;
        next = current == 1u ? 2u : 1u;
        if (threads[next - 1u].done)
            next = threads[current - 1u].done ? 0u : current;
    }

    if (next != current)
        switches++;
    current = next;
    if (next == 0u && threads[0].done && threads[1].done) {
        timer_set_compare(UINT64_MAX);
        __asm__ volatile ("csrc mie, %0" :: "r"(0x80u) : "memory");
    } else {
        next_deadline += PERIOD;
        if (next_deadline <= timer_read())
            fail("TICK OVERRUN FAIL\n");
        timer_set_compare(next_deadline);
    }
    return frames[next];
}

int main(void)
{
    if (data_cookie != UINT32_C(0x13579bdf) || ticks || current || exits ||
        background || frames[0] || frames[1] || frames[2])
        fail("STARTUP FAIL\n");
    for (uint32_t i = 0; i < 4u; i++)
        main_stack_guard[i] = UINT32_C(0xc0decafe);
    thread_init(1);
    thread_init(2);
    uart_puts("M10.3 START\n");

    __asm__ volatile ("csrw mtvec, %0" ::
                      "r"((uintptr_t)preempt_trap_entry) : "memory");
    __asm__ volatile ("csrw mtval, %0" ::
                      "r"(UINT32_C(0x89abcdef)) : "memory");
    next_deadline = timer_read() + PERIOD;
    timer_set_compare(next_deadline);
    __asm__ volatile ("csrs mie, %0" :: "r"(0x80u) : "memory");
    __asm__ volatile ("csrs mstatus, %0" :: "r"(8u) : "memory");
    while (!threads[0].done || !threads[1].done)
        background++;
    __asm__ volatile ("csrc mstatus, %0" :: "r"(8u) : "memory");

    check_guards();
    if (current != 0 || exits != 2u || switches < 8u || ticks < 10u ||
        background == 0 || data_cookie != UINT32_C(0x13579bdf))
        fail("SCHEDULER RESULT FAIL\n");
    for (uint32_t i = 0; i < 2u; i++) {
        uint32_t count = threads[i].progress;
        uint32_t sum = i == 0u ? count + (count << 1) : count + (count << 2);
        if (count == 0 || threads[i].slices < RUN_SLICES ||
            threads[i].checksum != (UINT32_C(0x12340000) | (i + 1u)) + sum)
            fail("THREAD RESULT FAIL\n");
    }
    uart_puts("A COMPUTE PASS\n");
    uart_puts("B COMPUTE PASS\n");
    uart_puts("PREEMPT CONTEXT PASS\n");
    uart_puts("M10.3 PASS\n");
    while (1) {
    }
}
