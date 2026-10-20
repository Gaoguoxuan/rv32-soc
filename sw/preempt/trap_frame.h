#pragma once

#include <stddef.h>
#include <stdint.h>

typedef struct {
    /* gpr[n - 1] 对应 xn，按 x1～x31 顺序排列。 */
    uint32_t gpr[31];

    uint32_t mepc;
    uint32_t mstatus;

    /* 补齐到 144 字节，保持栈的 16 字节对齐。 */
    uint32_t reserved[3];
} trap_frame_t;

_Static_assert(sizeof(trap_frame_t) == 144, "frame size");
_Static_assert(offsetof(trap_frame_t, mepc) == 124,
               "mepc offset");
_Static_assert(offsetof(trap_frame_t, mstatus) == 128,
               "mstatus offset");

void preempt_trap_entry(void);

/*
 * frame：刚保存的现场。
 * 返回值：接下来要恢复的现场，必须有效且按 16 字节对齐。
 * 处理期间保持全局中断关闭。
 */
trap_frame_t *trap_dispatch(trap_frame_t *frame,
                            uint32_t cause,
                            uint32_t tval);