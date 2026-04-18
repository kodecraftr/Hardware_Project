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
    uart_puts("C TEMPLATE READY\r\n");

    for (;;) {
        uart_puts("NUM> ");
        uart_readline(line, sizeof(line));
        uart_puts("ECHO ");
        uart_print_i32(parse_i32(line));
        uart_puts("\r\n");
    }
}
