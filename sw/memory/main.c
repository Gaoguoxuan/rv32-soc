#include <stdint.h>

#define MMIO32(address) (*(volatile uint32_t *)(uintptr_t)(address))
#define MMIO16(address) (*(volatile uint16_t *)(uintptr_t)(address))
#define MMIO8(address)  (*(volatile uint8_t *)(uintptr_t)(address))
#define UART_TXDATA    MMIO32(0x20000000u)
#define LAST_RAM_WORD  0x1000fffcu
#define ROM_TAIL_VALUE UINT32_C(0x5aa59669)

static volatile uint32_t data_cookie = UINT32_C(0x13579bdf);
static volatile uint32_t zero_probe[4];

/* The linker places code and read-only data above the original 4 KiB ROM. */
__attribute__((section(".high_text"), noinline))
uint32_t high_rom_probe(uint32_t value)
{
    return value ^ UINT32_C(0xa55aa55a);
}

__attribute__((section(".high_rodata"), used))
const volatile uint32_t high_rom_cookie = UINT32_C(0xcafebabe);

static const uint32_t probe_addresses[] = {
    0x10000000u, 0x10000400u, 0x10001000u, 0x10008000u, LAST_RAM_WORD
};
static const uint32_t probe_values[] = {
    0x11223344u, 0x55667788u, 0x89abcdefu, 0x13579bdfu, 0xa1b2c3d4u
};
static const uint32_t unmapped_addresses[] = {
    0x00010000u, 0x0ffffffcu, 0x10010000u, 0xfffffffcu
};

static void uart_puts(const char *text)
{
    while (*text != '\0')
        UART_TXDATA = (uint32_t)(unsigned char)*text++;
}

static void fail(const char *message)
{
    uart_puts(message);
    while (1) {
    }
}

int main(void)
{
    uint32_t i;

    /* .data starts at RAM+0x2000; .bss starts at RAM+0x6000. */
    if ((uintptr_t)&data_cookie != 0x10002000u ||
        (uintptr_t)zero_probe != 0x10006000u ||
        data_cookie != UINT32_C(0x13579bdf))
        fail("HIGH DATA FAIL\n");
    for (i = 0; i < 4u; i++) {
        if (zero_probe[i] != 0)
            fail("HIGH BSS FAIL\n");
    }
    uart_puts("M10.1 START\n");

    if ((uintptr_t)high_rom_probe != 0x2000u ||
        high_rom_probe(UINT32_C(0x12345678)) != UINT32_C(0xb76ef322) ||
        (uintptr_t)&high_rom_cookie != 0x4000u ||
        high_rom_cookie != UINT32_C(0xcafebabe))
        fail("HIGH ROM FAIL\n");
    uart_puts("HIGH ROM PASS\n");

    /* Each address must refer to a distinct physical word. */
    for (i = 0; i < 5u; i++)
        MMIO32(probe_addresses[i]) = probe_values[i];
    for (i = 0; i < 5u; i++) {
        if (MMIO32(probe_addresses[i]) != probe_values[i])
            fail("RAM ALIAS FAIL\n");
    }
    uart_puts("RAM RANGE PASS\n");

    /* The final 16 RAM bytes are outside the software stack. */
    MMIO8(0x1000ffffu) = 0x5au;
    if (MMIO32(LAST_RAM_WORD) != UINT32_C(0x5ab2c3d4))
        fail("LAST BYTE FAIL\n");
    MMIO16(0x1000fffeu) = 0x9abcu;
    if (MMIO32(LAST_RAM_WORD) != UINT32_C(0x9abcc3d4))
        fail("LAST HALF FAIL\n");
    MMIO16(LAST_RAM_WORD) = 0x1234u;
    if (MMIO32(LAST_RAM_WORD) != UINT32_C(0x9abc1234) ||
        MMIO8(0x1000ffffu) != 0x9au || MMIO16(0x1000fffeu) != 0x9abcu)
        fail("LAST WORD FAIL\n");

    if (MMIO32(0x0000fffcu) != ROM_TAIL_VALUE || MMIO8(0x0000ffffu) != 0x5au)
        fail("ROM TAIL FAIL\n");
    MMIO32(0x0000fffcu) = 0xdeadbeefu;
    if (MMIO32(0x0000fffcu) != ROM_TAIL_VALUE)
        fail("ROM WRITE FAIL\n");

    for (i = 0; i < 4u; i++) {
        MMIO32(unmapped_addresses[i]) = 0xdeadbeefu;
        if (MMIO32(unmapped_addresses[i]) != 0)
            fail("UNMAPPED READ FAIL\n");
    }
    for (i = 0; i < 5u; i++) {
        uint32_t expected = i == 4u ? UINT32_C(0x9abc1234) : probe_values[i];
        if (MMIO32(probe_addresses[i]) != expected)
            fail("UNMAPPED WRITE FAIL\n");
    }
    if (data_cookie != UINT32_C(0x13579bdf))
        fail("DATA CORRUPTION\n");
    for (i = 0; i < 4u; i++) {
        if (zero_probe[i] != 0)
            fail("BSS CORRUPTION\n");
    }
    uart_puts("BOUNDARY PASS\n");
    uart_puts("M10.1 PASS\n");
    while (1) {
    }
}
