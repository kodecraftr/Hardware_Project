#include "soc_io.h"

int main(void) {
    volatile char x = '7';
    uart_init();
    uart_putc((char)x);
    uart_putc('\r');
    uart_putc('\n');
    for (;;)
        ;
}
