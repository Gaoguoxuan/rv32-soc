#include "../common/irq.h"

#define MMIO32(address) (*(volatile uint32_t *)(uintptr_t)(address))
#define UART_TXDATA    MMIO32(0x20000000u)
#define MTIME_LO       MMIO32(0x30000000u)
#define MTIME_HI       MMIO32(0x30000004u)
#define MTIMECMP_LO    MMIO32(0x30000008u)
#define MTIMECMP_HI    MMIO32(0x3000000cu)

enum {
    PHASE_SETUP,
    PHASE_STATE_MATRIX,
    PHASE_RESTORE_MASK,
    PHASE_DISABLED_PENDING,
    PHASE_NESTED_PENDING,
    PHASE_OUTER_RESTORE,
    PHASE_FINISHED
};

extern void trap_entry(void);
static volatile uint32_t phase;
static volatile uint32_t irq_count;
static volatile uint32_t isr_checks_done;
/* Ordinary memory: the IRQ API's compiler barriers publish this to the ISR. */
static uint32_t protected_value;
static volatile uint32_t data_cookie = UINT32_C(0x13579bdf);
static volatile uint32_t stack_guard[4]
    __attribute__((section(".stack_guard"), aligned(16), used));

static void uart_puts(const char *text)
{
    while (*text != '\0')
        UART_TXDATA = (uint32_t)(unsigned char)*text++;
}

static void fail(const char *message) __attribute__((noreturn));
static void fail(const char *message)
{
    (void)irq_save();
    uart_puts(message);
    while (1) {
    }
}

static void expect32(uint32_t actual, uint32_t expected)
{
    if (actual != expected)
        fail("IRQ API FAIL\n");
}

static uint32_t read_status(void)
{
    uint32_t value;
    __asm__ volatile ("csrr %0, mstatus" : "=r"(value) :: "memory");
    return value;
}

static void write_status(uint32_t value)
{
    __asm__ volatile ("csrw mstatus, %0" :: "r"(value) : "memory");
}

static uint32_t read_mie(void)
{
    uint32_t value;
    __asm__ volatile ("csrr %0, mie" : "=r"(value) :: "memory");
    return value;
}

static void write_mie(uint32_t value)
{
    __asm__ volatile ("csrw mie, %0" :: "r"(value) : "memory");
}

static uint32_t read_pending(void)
{
    uint32_t value;
    __asm__ volatile ("csrr %0, mip" : "=r"(value) :: "memory");
    return value;
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

static void wait_pending(void)
{
    for (uint32_t attempt = 0; attempt < 4096u; attempt++) {
        if (read_pending() & 0x80u)
            return;
    }
    fail("TIMER PENDING TIMEOUT\n");
}

static void hold_pending(void)
{
    /* Leave a real level-triggered IRQ pending long enough to expose early enable. */
    for (uint32_t i = 0; i < 64u; i++)
        __asm__ volatile ("nop" ::: "memory");
    expect32(read_pending(), 0x80u);
    expect32(irq_count, 0);
    expect32(read_status(), 0x1880u);
    expect32(read_mie(), 0x80u);
}

static void test_state_matrix(void)
{
    phase = PHASE_STATE_MATRIX;
    /* Both values of MIE, MPIE and MTIE: eight starting states. */
    for (uint32_t mtie = 0; mtie < 2u; mtie++) {
        uint32_t enables = mtie ? 0x80u : 0;
        write_mie(enables);
        for (uint32_t mpie = 0; mpie < 2u; mpie++) {
            uint32_t base = 0x1800u | (mpie ? 0x80u : 0);
            for (uint32_t mie = 0; mie < 2u; mie++) {
                uint32_t initial = base | (mie ? 8u : 0);
                write_status(initial);
                irq_state_t outer = irq_save();
                expect32(outer, initial & 8u);
                expect32(read_status(), base);
                expect32(read_mie(), enables);
                irq_state_t inner = irq_save();
                expect32(inner, 0);
                expect32(read_status(), base);
                irq_restore(inner);
                expect32(read_status(), base);
                irq_restore(outer);
                expect32(read_status(), initial);
                expect32(read_mie(), enables);
                expect32(irq_count, 0);
            }
        }
    }
    write_status(0x1880u);
    write_mie(0);
    uart_puts("STATE MATRIX PASS\n");
}

static void test_restore_mask(void)
{
    phase = PHASE_RESTORE_MASK;
    write_status(0x1888u);
    irq_state_t state = irq_save();
    expect32(state, 8);
    /* Change MPIE during the critical section: restore must preserve that change. */
    write_status(0x1800u);
    irq_restore(state);
    expect32(read_status(), 0x1808u);
    /* Other bits in an input token must never be written into mstatus. */
    irq_restore(0x1880u);
    expect32(read_status(), 0x1800u);
    irq_restore(0x1888u);
    expect32(read_status(), 0x1808u);
    irq_restore(0);
    expect32(read_status(), 0x1800u);
    write_status(0x1880u);
    uart_puts("RESTORE MASK PASS\n");
}

static void test_disabled_pending(void)
{
    phase = PHASE_DISABLED_PENDING;
    irq_state_t outer = irq_save();
    irq_state_t inner = irq_save();
    expect32(outer, 0);
    expect32(inner, 0);
    write_mie(0x80u);
    timer_set_compare(timer_read() + UINT64_C(1024));
    wait_pending();
    irq_restore(inner);
    hold_pending();
    irq_restore(outer);
    hold_pending();
    /* Originally disabled means still disabled, even with MTIP=1 and MTIE=1. */
    timer_set_compare(UINT64_MAX);
    expect32(read_pending(), 0);
    write_mie(0);
    uart_puts("DISABLED RESTORE PASS\n");
}

static void test_nested_pending(void)
{
    phase = PHASE_NESTED_PENDING;
    write_status(0x1888u);
    irq_state_t outer = irq_save();
    irq_state_t inner = irq_save();
    expect32(outer, 8);
    expect32(inner, 0);
    write_mie(0x80u);
    timer_set_compare(timer_read() + UINT64_C(1024));
    wait_pending();
    protected_value = UINT32_C(0x12345678);
    irq_restore(inner);
    hold_pending();

    protected_value = UINT32_C(0x2468ace0);
    phase = PHASE_OUTER_RESTORE;
    irq_restore(outer);
    for (uint32_t attempt = 0; irq_count == 0; attempt++) {
        if (attempt >= 4096u)
            fail("DEFERRED IRQ TIMEOUT\n");
    }
    expect32(irq_count, 1);
    expect32(isr_checks_done, 1);
    expect32(read_status(), 0x1888u);
    expect32(read_mie(), 0);
    expect32(read_pending(), 0);
    expect32(protected_value, UINT32_C(0x2468ace0));
    irq_restore(0);
    uart_puts("PENDING DEFER PASS\n");
    uart_puts("ISR CRITICAL PASS\n");
}

void trap_handler(uint32_t cause, uint32_t epc, uint32_t tval)
{
    if (phase != PHASE_OUTER_RESTORE || irq_count != 0 ||
        cause != UINT32_C(0x80000007) || tval != 0 ||
        (epc & 3u) != 0 || epc >= 0x10000u ||
        read_status() != 0x1880u || read_pending() != 0x80u ||
        protected_value != UINT32_C(0x2468ace0))
        fail("ISR ENTRY FAIL\n");

    /* Hardware entered with MIE=0. Neither nested restore may enable it. */
    irq_state_t outer = irq_save();
    irq_state_t inner = irq_save();
    if (outer != 0 || inner != 0)
        fail("ISR SAVE FAIL\n");
    irq_restore(inner);
    if (read_status() != 0x1880u || read_pending() != 0x80u)
        fail("ISR INNER RESTORE FAIL\n");
    irq_restore(outer);
    if (read_status() != 0x1880u || read_pending() != 0x80u || read_mie() != 0x80u)
        fail("ISR OUTER RESTORE FAIL\n");

    timer_set_compare(UINT64_MAX);
    write_mie(0);
    isr_checks_done = 1;
    irq_count = 1;
}

int main(void)
{
    if (phase != PHASE_SETUP || irq_count || isr_checks_done || protected_value ||
        data_cookie != UINT32_C(0x13579bdf))
        fail("STARTUP FAIL\n");
    for (uint32_t i = 0; i < 4u; i++)
        stack_guard[i] = UINT32_C(0xc0decafe);
    __asm__ volatile ("csrw mtvec, %0" :: "r"((uintptr_t)trap_entry) : "memory");
    __asm__ volatile ("csrw mtval, %0" :: "r"(UINT32_C(0x89abcdef)) : "memory");
    uart_puts("M10.4 START\n");

    test_state_matrix();
    test_restore_mask();
    test_disabled_pending();
    test_nested_pending();

    for (uint32_t i = 0; i < 4u; i++)
        expect32(stack_guard[i], UINT32_C(0xc0decafe));
    expect32(read_status(), 0x1880u);
    expect32(irq_count, 1);
    expect32(data_cookie, UINT32_C(0x13579bdf));
    phase = PHASE_FINISHED;
    uart_puts("M10.4 PASS\n");
    while (1) {
    }
}
