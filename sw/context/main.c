#include "context.h"

#define UART_TXDATA (*(volatile uint32_t *)(uintptr_t)0x20000000u)
#define STACK_WORDS 256u
#define ROUNDS 3u

typedef struct {
    context_t *context;
    uint32_t id;
    volatile uint32_t done;
    volatile uint32_t count;
    volatile uint32_t last_local;
} thread_t;

static context_t contexts[3];  /* main, A, B */
static thread_t threads[2];
static thread_t * volatile current;
static volatile uint32_t yields;
static volatile uint32_t exits;
static volatile uint32_t resume_checks;
static volatile uint32_t data_cookie = UINT32_C(0x13579bdf);

static uint32_t stack_a[STACK_WORDS]
    __attribute__((section(".stack_a"), aligned(16), used));
static uint32_t stack_b[STACK_WORDS]
    __attribute__((section(".stack_b"), aligned(16), used));

static void uart_puts(const char *text)
{
    while (*text != '\0')
        UART_TXDATA = (uint32_t)(unsigned char)*text++;
}

static void fail(const char *message) __attribute__((noreturn));
static void fail(const char *message)
{
    uart_puts(message);
    while (1) {
    }
}

static uint32_t *thread_stack(uint32_t id)
{
    return id == 0 ? stack_a : stack_b;
}

static void check_guards(void)
{
    uint32_t i;
    for (i = 0; i < 4u; i++) {
        if (stack_a[i] != UINT32_C(0xa55a0000) ||
            stack_b[i] != UINT32_C(0xa55a0001))
            fail("STACK GUARD FAIL\n");
    }
}

static void switch_to(thread_t *next) __attribute__((noinline));
static void switch_to(thread_t *next)
{
    thread_t *from = current;
    if (from == next || next->done)
        fail("SCHEDULE FAIL\n");
    current = next;
    context_switch(from->context, next->context);
    /* A later switch resumes this call with the original local 'from'. */
    if (current != from)
        fail("CURRENT THREAD FAIL\n");
}

static void thread_yield(void)
{
    yields++;
    check_guards();
    switch_to(&threads[current->id ^ 1u]);
}

static void thread_entry(void *argument)
{
    thread_t *self = argument;
    uint32_t seed = UINT32_C(0x12340000) | self->id;
    uint32_t local = seed;
    volatile uint32_t stack_local[4];
    uint32_t *stack = thread_stack(self->id);
    uint32_t round;

    if (self != current || (uintptr_t)stack_local < (uintptr_t)(stack + 4) ||
        (uintptr_t)(stack_local + 4) > (uintptr_t)(stack + STACK_WORDS))
        fail("THREAD START FAIL\n");

    for (round = 1; round <= ROUNDS; round++) {
        local += 16u;
        stack_local[0] = seed + round;
        stack_local[1] = ~(seed + round);
        stack_local[2] = (uint32_t)(uintptr_t)self;
        stack_local[3] = UINT32_C(0xface0000) | self->id;
        self->count++;
        self->last_local = local;
        UART_TXDATA = self->id == 0 ? 'A' : 'B';
        UART_TXDATA = '0' + round;
        UART_TXDATA = '\n';

        thread_yield();

        if (current != self || local != seed + (round << 4) ||
            stack_local[0] != seed + round || stack_local[1] != ~(seed + round) ||
            stack_local[2] != (uint32_t)(uintptr_t)self ||
            stack_local[3] != (UINT32_C(0xface0000) | self->id))
            fail("LOCAL STATE FAIL\n");
        resume_checks++;
    }
    /* A normal C return goes back to thread_bootstrap, then thread_exit. */
}

void thread_exit(void)
{
    thread_t *finished = current;
    thread_t *next;
    if (finished == 0 || finished->done || finished->count != ROUNDS)
        fail("THREAD EXIT FAIL\n");
    finished->done = 1;
    exits++;
    check_guards();
    next = &threads[finished->id ^ 1u];
    if (!next->done) {
        current = next;
        context_switch(finished->context, next->context);
    }
    else {
        current = 0;
        context_switch(finished->context, &contexts[0]);
    }
    fail("FINISHED THREAD RESUMED\n");
}

static void thread_init(uint32_t id)
{
    thread_t *thread = &threads[id];
    context_t *context = &contexts[id + 1u];
    uint32_t *stack = thread_stack(id);
    uint32_t i;
    for (i = 0; i < STACK_WORDS; i++)
        stack[i] = UINT32_C(0xcccc0000) | i;
    for (i = 0; i < 4u; i++)
        stack[i] = UINT32_C(0xa55a0000) | id;
    for (i = 0; i < 12u; i++)
        context->s[i] = UINT32_C(0x5a000000) | (id << 16) | i;
    context->ra = (uint32_t)(uintptr_t)thread_bootstrap;
    context->sp = (uint32_t)(uintptr_t)(stack + STACK_WORDS);
    context->s[0] = (uint32_t)(uintptr_t)thread_entry;
    context->s[1] = (uint32_t)(uintptr_t)thread;
    thread->context = context;
    thread->id = id;
}

int main(void)
{
    if (data_cookie != UINT32_C(0x13579bdf) || current != 0 || yields != 0 ||
        exits != 0 || resume_checks != 0 || threads[0].done != 0 || threads[1].done != 0)
        fail("STARTUP FAIL\n");
    thread_init(0);
    thread_init(1);
    uart_puts("M10.2 START\n");
    current = &threads[0];
    context_switch(&contexts[0], threads[0].context);

    if (current != 0 || !threads[0].done || !threads[1].done ||
        threads[0].count != ROUNDS || threads[1].count != ROUNDS ||
        threads[0].last_local != UINT32_C(0x12340030) ||
        threads[1].last_local != UINT32_C(0x12340031) ||
        yields != 6u || exits != 2u || resume_checks != 6u ||
        data_cookie != UINT32_C(0x13579bdf))
        fail("MAIN RESUME FAIL\n");
    check_guards();
    uart_puts("CONTEXT PASS\n");
    uart_puts("M10.2 PASS\n");
    while (1) {
    }
}
