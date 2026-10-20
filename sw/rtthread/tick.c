#include "cpuport.h"

#define MMIO32(address) (*(volatile rt_uint32_t *)(rt_ubase_t)(address))
#define MTIME_LO        MMIO32(0x30000000u)
#define MTIME_HI        MMIO32(0x30000004u)
#define MTIMECMP_LO     MMIO32(0x30000008u)
#define MTIMECMP_HI     MMIO32(0x3000000cu)

/* mtime advances once per clock; the tick test runs the SoC at 10 MHz. */
#define TIMER_CLOCK_HZ  10000000u
#define TICK_CYCLES     (TIMER_CLOCK_HZ / RT_TICK_PER_SECOND)
_Static_assert(TIMER_CLOCK_HZ % RT_TICK_PER_SECOND == 0, "integral tick period");
_Static_assert(TICK_CYCLES > 0, "nonzero tick period");

static rt_uint64_t next_deadline;

static rt_uint64_t timer_read(void)
{
    rt_uint32_t before, low, after;
    do {
        before = MTIME_HI;
        low = MTIME_LO;
        after = MTIME_HI;
    } while (before != after);
    return ((rt_uint64_t)before << 32) | low;
}

static void timer_set_compare(rt_uint64_t value)
{
    MTIMECMP_LO = 0xffffffffu;
    MTIMECMP_HI = (rt_uint32_t)(value >> 32);
    MTIMECMP_LO = (rt_uint32_t)value;
}

void rt_hw_tick_stop(void)
{
    __asm__ volatile ("csrc mie, %0" :: "r"(0x80u) : "memory");
    timer_set_compare(~(rt_uint64_t)0);
}

void rt_hw_tick_init(void)
{
    /* Boot-only initialization: MIE stays clear until the first thread's MRET. */
    (void)rt_hw_interrupt_disable();
    rt_hw_tick_stop();
    __asm__ volatile ("csrw mtvec, %0" :: "r"((rt_ubase_t)rt_hw_trap_entry) : "memory");
    next_deadline = timer_read() + TICK_CYCLES;
    timer_set_compare(next_deadline);
    __asm__ volatile ("csrs mie, %0" :: "r"(0x80u) : "memory");
}

void rt_hw_tick_rearm(void)
{
    /* Advance the previous deadline so handler execution does not add drift. */
    next_deadline += TICK_CYCLES;
    if (next_deadline <= timer_read()) {
        /* This first port reports missed periods; it does not make up ticks. */
        rt_hw_tick_stop();
        rt_kprintf("RT-THREAD TICK OVERRUN\n");
        while (1) {
        }
    }
    timer_set_compare(next_deadline);
}
