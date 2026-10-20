#pragma once

#include <stdint.h>

/* 只记录原来的 mstatus.MIE，取值为 0 或 8。 */
typedef uint32_t irq_state_t;

static inline irq_state_t irq_save(void)
{
    uint32_t previous;

    /* 一条指令完成：读取旧 mstatus，并清除 MIE。 */
    __asm__ volatile (
        "csrrci %0, mstatus, 8"
        : "=r"(previous)
        :
        : "memory"
    );

    return previous & 8u;
}

static inline void irq_restore(irq_state_t state)
{
    if (state & 8u) {
        __asm__ volatile (
            "csrsi mstatus, 8"
            :
            :
            : "memory"
        );
    } else {
        __asm__ volatile (
            "csrci mstatus, 8"
            :
            :
            : "memory"
        );
    }
}