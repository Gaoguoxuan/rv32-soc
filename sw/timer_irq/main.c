#include <stdint.h>

#define MMIO32(address) (*(volatile uint32_t *)(uintptr_t)(address))
#define UART_TXDATA    MMIO32(0x20000000u)
#define MTIME_LO       MMIO32(0x30000000u)
#define MTIME_HI       MMIO32(0x30000004u)
#define MTIMECMP_LO    MMIO32(0x30000008u)
#define MTIMECMP_HI    MMIO32(0x3000000cu)
#define PERIOD        UINT64_C(4096)
#define GUARD_VALUE   UINT32_C(0xc0decafe)

extern void trap_entry(void);
extern volatile uint32_t __stack_guard;

static volatile uint32_t data_cookie = UINT32_C(0x13579bdf);
static volatile uint32_t ticks;
static volatile uint32_t background;
static uint64_t next_deadline;

static void uart_puts(const char *text)
{
    while (*text != '\0')
        UART_TXDATA = (uint32_t)(unsigned char)*text++;
}

static void fail(const char *message)
{
    __asm__ volatile ("csrc mstatus, %0" :: "r"(8u) : "memory");
    uart_puts(message);
    while (1) {
    }
}

static uint64_t timer_read(void)
{
    uint32_t high_before;
    uint32_t low;
    uint32_t high_after;

    do {
        high_before = MTIME_HI;
        low = MTIME_LO;
        high_after = MTIME_HI;
    } while (high_before != high_after);

    return ((uint64_t)high_before << 32) | low;
}

static void timer_set_compare(uint64_t value)
{
    MTIMECMP_LO = UINT32_MAX;
    MTIMECMP_HI = (uint32_t)(value >> 32);
    MTIMECMP_LO = (uint32_t)value;
}

/* A normal C function: trap.S preserves the interrupted context and MRETs. */
void trap_handler(uint32_t cause, uint32_t epc, uint32_t tval)
{
    uint32_t status;

    if (cause != UINT32_C(0x80000007) || tval != 0 ||
        (epc & 3u) != 0 || epc >= 0x1000u)
        fail("TRAP ARGUMENT FAIL\n");

    __asm__ volatile ("csrr %0, mstatus" : "=r"(status));
    if ((status & 0x1888u) != 0x1880u)
        fail("TRAP STATUS FAIL\n");

    ticks++;
    if (ticks < 3u) {
        /* Advance the previous deadline to retain a fixed tick period. */
        next_deadline += PERIOD;
        timer_set_compare(next_deadline);
    }
    else {
        timer_set_compare(UINT64_MAX);
        __asm__ volatile ("csrc mie, %0" :: "r"(0x80u) : "memory");
    }
}

int main(void)
{
    if (data_cookie != UINT32_C(0x13579bdf) || ticks != 0 || background != 0)
        fail("STARTUP FAIL\n");
    __stack_guard = GUARD_VALUE;
    uart_puts("M9.3.3 START\n");

    /* Install an aligned Direct-mode vector before enabling interrupts. */
    __asm__ volatile ("csrw mtvec, %0" :: "r"((uintptr_t)trap_entry) : "memory");
    /* Leave a nonzero value for the first timer trap to overwrite. */
    __asm__ volatile ("csrw mtval, %0" :: "r"(UINT32_C(0x89abcdef)) : "memory");
    next_deadline = timer_read() + PERIOD;
    timer_set_compare(next_deadline);
    __asm__ volatile ("csrs mie, %0" :: "r"(0x80u) : "memory");
    __asm__ volatile ("csrs mstatus, %0" :: "r"(8u) : "memory");

    /* The ISR changes ticks; ordinary code continues between interrupts. */
    while (ticks < 3u)
        background++;

    __asm__ volatile ("csrc mstatus, %0" :: "r"(8u) : "memory");
    if (ticks != 3u || background == 0 || __stack_guard != GUARD_VALUE ||
        data_cookie != UINT32_C(0x13579bdf))
        fail("CONTEXT FAIL\n");

    uart_puts("TICKS=3\n");
    uart_puts("CONTEXT PASS\n");
    uart_puts("M9.3.3 PASS\n");
    while (1) {
    }
}
