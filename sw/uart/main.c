#define UART_TXDATA \
    (*(volatile unsigned int *)0x20000000u)


/*
 * Has an initial value.
 *
 * Should live in .data.
 *
 * Initial value 123 must be copied
 * from ROM to RAM by start.S.
 */
volatile unsigned int global_value = 123;


/*
 * No explicit initial value.
 *
 * Should live in .bss.
 *
 * start.S must clear it to zero.
 */
volatile unsigned int counter;


/*
 * const data.
 *
 * Should stay in ROM (.rodata).
 */
static const char hello_msg[] = "Hello RV32 from ROM!\n";

static const char pass_msg[] = "M6.3 PASS\n";

static const char data_fail_msg[] = "DATA FAIL\n";

static const char bss_fail_msg[] = "BSS FAIL\n";


static void uart_putc(char c)
{
    UART_TXDATA = (unsigned int)(unsigned char)c;
}


static void uart_puts(const char *s)
{
    while (*s != '\0') {

        uart_putc(*s);

        s++;
    }
}


int main(void)
{
    /*
     * Verify .data initialization.
     */
    if (global_value != 123) {

        uart_puts(data_fail_msg);

        while (1) {
        }

    }


    /*
     * Verify .bss initialization.
     */
    if (counter != 0) {

        uart_puts(bss_fail_msg);

        while (1) {
        }

    }


    /*
     * Verify writable RAM globals.
     */
    global_value = global_value + 1;

    counter = 7;


    if (
        global_value != 124 ||
        counter != 7
    ) {

        uart_puts(data_fail_msg);

        while (1) {
        }

    }


    /*
     * Verify .rodata reading from ROM.
     */
    uart_puts(hello_msg);

    uart_puts(pass_msg);


    while (1) {
    }


    return 0;
}