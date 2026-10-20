#pragma once

#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint32_t ra;
    uint32_t sp;
    uint32_t s[12];   /* s0～s11 */
} context_t;

/* 确保 C 结构布局与汇编偏移一致。 */
_Static_assert(sizeof(context_t) == 56, "context size");
_Static_assert(offsetof(context_t, sp) == 4, "sp offset");
_Static_assert(offsetof(context_t, s) == 8, "s offset");

void context_switch(context_t *from, const context_t *to);
void thread_bootstrap(void);
void thread_exit(void) __attribute__((noreturn));