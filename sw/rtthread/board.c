#include <rthw.h>

#define UART_TXDATA \
    (*(volatile rt_uint32_t *)0x20000000u)

void rt_hw_console_output(const char *str)
{
    while (*str != '\0')
        UART_TXDATA = (rt_uint32_t)(unsigned char)*str++;
}
