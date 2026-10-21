typedef unsigned int u32;
typedef unsigned char u8;

#define MMIO32(addr) (*(volatile u32 *)(addr))
#define MMIO16(addr) (*(volatile unsigned short *)(addr))
#define MMIO8(addr)  (*(volatile u8 *)(addr))
#define UART_TX     MMIO32(0x20000000u)
#define RX_STATUS   MMIO32(0x20000004u)
#define RX_DATA     MMIO32(0x20000008u)
#define RX_ACK      MMIO32(0x2000000cu)

static const u8 stream[] = {
    'A', 0x00, 0xff, 0x7f, 0x80, 'R', 'I', 'S', 'C', '-', 'V', '\n'
};

static void put_string(const char *text)
{
    while (*text != '\0')
        UART_TX = (u8)*text++;
}

static void fail(char code)
{
    put_string("\nCONSOLE RX FAIL ");
    UART_TX = (u8)code;
    UART_TX = '\n';
    for (;;) { }
}

static void check_first_byte(void)
{
    if (RX_STATUS != 1u || RX_DATA != 'A')
        fail('A');
}

static u32 read_byte(void)
{
    while ((RX_STATUS & 1u) == 0u) { }
    u32 value = RX_DATA;
    // Reading DATA and ACK must not consume the byte.
    if (RX_DATA != value || RX_STATUS != 1u || RX_ACK != 0u)
        fail('R');
    return value;
}

int main(void)
{
    if (RX_STATUS != 0u || RX_DATA != 0u || RX_ACK != 0u)
        fail('E');
    RX_ACK = 1u; // An ACK on an empty mailbox has no effect.
    if (RX_STATUS != 0u || RX_DATA != 0u)
        fail('E');

    put_string("CONSOLE RX READY\n");
    for (u32 i = 0; i < sizeof(stream); i++)
    {
        u32 value = read_byte();
        if (value != stream[i])
            fail('D');

        if (i == 0u)
        {
            // The host keeps the next byte pending throughout these writes.
            RX_STATUS = 1u;
            check_first_byte();
            RX_DATA = 1u;
            check_first_byte();
            RX_ACK = 0xfffffffeu;
            check_first_byte();
            MMIO8(0x2000000du) = 1u;
            check_first_byte();
            MMIO16(0x2000000eu) = 1u;
            check_first_byte();
            MMIO32(0x20000010u) = 1u;
            check_first_byte();
            MMIO32(0x2000010cu) = 1u;
            check_first_byte();
            if (MMIO32(0x20000000u) != 0u ||
                MMIO8(0x20000005u) != 0u ||
                MMIO8(0x20000009u) != 0u ||
                MMIO8(0x2000000fu) != 0u ||
                MMIO32(0x20000010u) != 0u ||
                MMIO32(0x20000104u) != 0u ||
                MMIO32(0x20000108u) != 0u)
                fail('U');
        }

        RX_ACK = 1u;
        UART_TX = value;
        // The host supplies consecutive bytes on ACK edges, then stops.
        if (RX_STATUS != (i + 1u < sizeof(stream) ? 1u : 0u))
            fail('S');
    }

    if (RX_DATA != 0u)
        fail('E');

    // A delayed final byte proves polling still works after draining.
    if (read_byte() != 'Z')
        fail('Z');
    MMIO8(0x2000000cu) = 1u; // Low-byte ACK is also valid.
    if (RX_STATUS != 0u || RX_DATA != 0u)
        fail('E');
    UART_TX = 'Z';
    put_string("\nCONSOLE RX PASS\n");
    return 0;
}
