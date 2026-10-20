#include <rthw.h>

_Static_assert(sizeof(rt_base_t) == 4 && sizeof(rt_ubase_t) == 4, "RV32 ABI");
_Static_assert(RTTHREAD_VERSION == RT_VERSION_CHECK(4, 1, 1), "pinned kernel");
_Static_assert(RT_ALIGN_SIZE == 16, "RISC-V stack alignment");

static volatile rt_uint32_t data_cookie = 0x13579bdfu;
static volatile rt_uint32_t test_stage;
static volatile rt_uint32_t stack_guard[4]
    __attribute__((section(".stack_guard"), aligned(16), used));

static void fail(void) __attribute__((noreturn));
static void fail(void)
{
    (void)rt_hw_interrupt_disable();
    rt_kprintf("M11.1 FAIL\n");
    while (1) {
    }
}

static void expect(int condition)
{
    if (!condition)
        fail();
}

static rt_uint32_t read_status(void)
{
    rt_uint32_t value;
    __asm__ volatile ("csrr %0, mstatus" : "=r"(value) :: "memory");
    return value;
}

static void write_status(rt_uint32_t value)
{
    __asm__ volatile ("csrw mstatus, %0" :: "r"(value) : "memory");
}

static void test_irq_port(void)
{
    /* Exercise the real RT-Thread signatures, including nested calls. */
    for (rt_uint32_t initial = 0; initial <= 8u; initial += 8u) {
        write_status(0x1880u | initial);
        rt_base_t outer = rt_hw_interrupt_disable();
        expect(outer == (rt_base_t)initial && read_status() == 0x1880u);
        rt_base_t inner = rt_hw_interrupt_disable();
        expect(inner == 0 && read_status() == 0x1880u);
        rt_hw_interrupt_enable(inner);
        expect(read_status() == 0x1880u);
        rt_hw_interrupt_enable(outer);
        expect(read_status() == (0x1880u | initial));
    }

    write_status(0x1888u);
    rt_base_t state = rt_hw_interrupt_disable();
    expect(state == 8);
    write_status(0x1800u);
    rt_hw_interrupt_enable(state);
    expect(read_status() == 0x1808u);
    rt_hw_interrupt_enable(0x1880);
    expect(read_status() == 0x1800u);
    write_status(0x1880u);
}

static void test_buffers(void)
{
    char buffer[48];
    struct {
        rt_uint8_t before;
        char text[8];
        rt_uint8_t after;
    } small;
    int length;

    length = rt_snprintf(buffer, sizeof(buffer), "%d %u %08x",
                         -2147483647 - 1, 4294967295u, 0u);
    expect(length == (int)(sizeof("-2147483648 4294967295 00000000") - 1));
    expect(rt_strcmp(buffer, "-2147483648 4294967295 00000000") == 0);

    small.before = 0xa5;
    small.after = 0x5a;
    for (rt_uint32_t i = 0; i < sizeof(small.text); i++)
        small.text[i] = '!';
    length = rt_snprintf(small.text, sizeof(small.text), "%s", "ABCDEFGHIJK");
    expect(length == 11 && rt_strcmp(small.text, "ABCDEFG") == 0);
    expect(small.before == 0xa5 && small.after == 0x5a && small.text[7] == '\0');

    length = rt_snprintf(small.text, 0, "%s", "XYZ");
    expect(length == 3 && rt_strcmp(small.text, "ABCDEFG") == 0);
    length = rt_snprintf(small.text, 1, "%s", "XYZ");
    expect(length == 3 && small.text[0] == '\0' && small.text[1] == 'B');
    expect(small.before == 0xa5 && small.after == 0x5a && small.text[7] == '\0');
}

int main(void)
{
    expect(data_cookie == 0x13579bdfu && test_stage == 0);
    for (rt_uint32_t i = 0; i < 4u; i++)
        stack_guard[i] = 0xc0decafeu;
    test_stage = 1;
    rt_kprintf("M11.1 START\n");
    rt_show_version();

    test_stage = 2;
    test_irq_port();
    rt_kprintf("RTHW IRQ PASS\n");

    test_stage = 3;
    int length = rt_kprintf("FORMAT d=%d u=%u x=%08x s=%s c=%c\n",
                            -12345, 4000000000u, 0x89abcdefu, "RV32", '!');
    expect(length == (int)(sizeof("FORMAT d=-12345 u=4000000000 x=89abcdef s=RV32 c=!\n") - 1));
    /* With fmt in a0, the final three integer arguments must be passed on the stack. */
    length = rt_kprintf("ARGS %d %d %d %d %d %d %d %d %d %d\n",
                        1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
    expect(length == (int)(sizeof("ARGS 1 2 3 4 5 6 7 8 9 10\n") - 1));
    test_buffers();
    rt_kprintf("BUFFER PASS\n");

    for (rt_uint32_t i = 0; i < 4u; i++)
        expect(stack_guard[i] == 0xc0decafeu);
    expect(data_cookie == 0x13579bdfu && read_status() == 0x1880u);
    test_stage = 4;
    rt_kprintf("M11.1 PASS\n");
    while (1) {
    }
}
