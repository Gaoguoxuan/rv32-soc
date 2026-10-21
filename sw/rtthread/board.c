#include <rthw.h>
#include <rtthread.h>

#define UART_TXDATA \
    (*(volatile rt_uint32_t *)0x20000000u)

#define UART_RXSTATUS \
    (*(volatile rt_uint32_t *)0x20000004u)

#define UART_RXDATA \
    (*(volatile rt_uint32_t *)0x20000008u)

#define UART_RXACK \
    (*(volatile rt_uint32_t *)0x2000000cu)

char rt_hw_console_getchar(void)
{
    while ((UART_RXSTATUS & 1u) == 0u) {
        rt_thread_delay(1);
    }

    rt_uint8_t value = (rt_uint8_t)UART_RXDATA;

    UART_RXACK = 1u;

    return (char)value;
}

void rt_hw_console_output(const char *str)
{
    while (*str != '\0')
        UART_TXDATA = (rt_uint32_t)(unsigned char)*str++;
}
