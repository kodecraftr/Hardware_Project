#include "soc_io.h"

static int parse_i32(const char *s) {
    int sign = 1;
    int value = 0;

    if (*s == '-') {
        sign = -1;
        s++;
    }

    while (*s >= '0' && *s <= '9') {
        value = value * 10 + (*s - '0');
        s++;
    }

    return sign * value;
}

int main(void) {
    char line[64];

    uart_init();
    uart_resync_rx();
    uart_puts("TIMES9 READY\r\n");
    uart_resync_rx();

    for (;;) {
        uart_puts("IN> ");
        uart_readline(line, sizeof(line));
        uart_puts("OUT ");
        uart_print_i32(parse_i32(line) * 9);
        uart_puts("\r\n");
    }
}
