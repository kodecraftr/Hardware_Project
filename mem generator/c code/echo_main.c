#include "soc_io.h"

int main(void) {
    char line[64];

    uart_init();
    uart_resync_rx();
    uart_puts("ECHO READY\r\n");

    for (;;) {
        uart_puts("ECHO> ");
        uart_readline(line, sizeof(line));
        uart_puts("YOU TYPED: ");
        uart_puts(line);
        uart_puts("\r\n");
    }
}
