#include <stdint.h>

#define MMIO32(address) (*(volatile uint32_t *)(uintptr_t)(address))
#define MMIO8(address)  (*(volatile uint8_t *)(uintptr_t)(address))

#define UART_TXDATA    MMIO32(0x20000000u)
#define MTIME_LO       MMIO32(0x30000000u)
#define MTIME_HI       MMIO32(0x30000004u)
#define MTIMECMP_LO    MMIO32(0x30000008u)
#define MTIMECMP_HI    MMIO32(0x3000000cu)

/* Also exercises the shared startup code's .bss initialization. */
static volatile uint32_t read_retries;

static void uart_putc(char c)
{
    UART_TXDATA = (uint32_t)(unsigned char)c;
}

static void uart_puts(const char *text)
{
    while (*text != '\0')
        uart_putc(*text++);
}

static void fail(const char *message)
{
    uart_puts(message);
    while (1) {
    }
}

static uint64_t timer_read(void)
{
    uint32_t high_before;
    uint32_t low;
    uint32_t high_after;

    for (;;) {
        high_before = MTIME_HI;
        low = MTIME_LO;
        high_after = MTIME_HI;

        if (high_before == high_after)
            return ((uint64_t)high_before << 32) | low;

        /* A carry occurred between the reads; discard the mixed snapshot. */
        read_retries++;
    }
}

static void timer_set_compare(uint64_t value)
{
    /*
     * RV32 little-endian, strongly ordered MMIO:
     * keep the intermediate comparand from becoming spuriously too small.
     */
    MTIMECMP_LO = UINT32_MAX;
    MTIMECMP_HI = (uint32_t)(value >> 32);
    MTIMECMP_LO = (uint32_t)value;
}

static uint64_t timer_read_compare(void)
{
    /* This program is the only writer, and no writes occur between reads. */
    uint32_t high = MTIMECMP_HI;
    uint32_t low = MTIMECMP_LO;

    return ((uint64_t)high << 32) | low;
}

static void timer_wait_until(uint64_t deadline)
{
    uint32_t attempts;

    for (attempts = 0; attempts < 10000u; attempts++) {
        if (timer_read() >= deadline)
            return;
    }
    fail("POLL TIMEOUT\n");
}

int main(void)
{
    uint32_t distance;
    uint32_t tick;
    uint64_t deadline;

    uart_puts("M9.2 START\n");

    if (read_retries != 0 || timer_read_compare() != UINT64_MAX)
        fail("RESET FAIL\n");

    timer_set_compare(UINT64_C(0x1122334455667788));
    if (timer_read_compare() != UINT64_C(0x1122334455667788))
        fail("COMPARE FAIL\n");

    /* Exercise the LSU byte strobes and both ends of the timer address range. */
    MMIO8(0x30000009u) = 0xaau;
    MMIO8(0x3000000fu) = 0x99u;
    if (timer_read_compare() != UINT64_C(0x992233445566aa88))
        fail("BYTE WRITE FAIL\n");

    MMIO32(0x30000010u) = 0xdeadbeefu;
    if (MMIO32(0x30000010u) != 0 ||
        timer_read_compare() != UINT64_C(0x992233445566aa88))
        fail("ADDRESS FAIL\n");

    timer_set_compare(UINT64_MAX);
    uart_puts("MMIO PASS\n");

    /*
     * Test stimulus only: place time near a low-word carry, sweeping its
     * distance so the carry also occurs inside a high/low/high read.
     * Normal timer use below reads time and only programs mtimecmp.
     */
    for (distance = 1; distance <= 64u; distance++) {
        MTIME_HI = 1;
        MTIME_LO = 0u - distance;
        if (timer_read() < UINT64_C(0x0000000100000000))
            fail("READ64 VALUE FAIL\n");
    }
    if (read_retries == 0)
        fail("READ64 RETRY FAIL\n");
    uart_puts("READ64 PASS\n");

    for (tick = 0; tick < 2u; tick++) {
        deadline = timer_read() + UINT64_C(4096);
        timer_set_compare(deadline);
        if (timer_read_compare() != deadline || timer_read() >= deadline)
            fail("ARM FAIL\n");

        /* Poll the time value; CPU interrupt delivery is added in M9.3. */
        timer_wait_until(deadline);
        uart_puts(tick == 0 ? "TICK 1\n" : "TICK 2\n");
    }

    timer_set_compare(UINT64_MAX);
    if (timer_read_compare() != UINT64_MAX)
        fail("DISARM FAIL\n");
    uart_puts("M9.2 PASS\n");

    while (1) {
    }
}
