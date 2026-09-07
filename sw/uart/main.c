#define UART_TXDATA (*(volatile unsigned int *)0x20000000u)


static void uart_putc(char c)
{
    UART_TXDATA = (unsigned int)c;
}


int main(void)
{
    uart_putc('H');
    uart_putc('e');
    uart_putc('l');
    uart_putc('l');
    uart_putc('o');
    uart_putc(' ');
    uart_putc('R');
    uart_putc('V');
    uart_putc('3');
    uart_putc('2');
    uart_putc('!');
    uart_putc('\n');

    while (1) {
    }

    return 0;
}