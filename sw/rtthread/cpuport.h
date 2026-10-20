#pragma once

#include <stddef.h>
#include <rthw.h>

typedef struct {
    rt_uint32_t gpr[31];  /* x1～x31 */
    rt_uint32_t mepc;
    rt_uint32_t mstatus;
    rt_uint32_t reserved[3];
} rt_hw_stack_frame_t;

_Static_assert(sizeof(rt_ubase_t) == 4, "RV32 required");
_Static_assert(RT_ALIGN_SIZE == 16, "stack alignment");
_Static_assert(sizeof(rt_hw_stack_frame_t) == 144, "frame size");
_Static_assert(offsetof(rt_hw_stack_frame_t, mepc) == 124,
               "mepc offset");
_Static_assert(offsetof(rt_hw_stack_frame_t, mstatus) == 128,
               "mstatus offset");

extern volatile rt_ubase_t rt_interrupt_from_thread;
extern volatile rt_ubase_t rt_interrupt_to_thread;
extern volatile rt_uint32_t rt_thread_switch_interrupt_flag;