#include "soc_io.h"

static int is_digit(char c) {
    return (c >= '0' && c <= '9');
}

static int parse_u32(const char *s, uint32_t *value) {
    uint32_t acc = 0;
    int saw_digit = 0;

    while (*s == ' ' || *s == '\t') {
        s++;
    }

    while (is_digit(*s)) {
        saw_digit = 1;
        acc = acc * 10u + (uint32_t)(*s - '0');
        s++;
    }

    while (*s == ' ' || *s == '\t') {
        s++;
    }

    if (!saw_digit || *s != '\0') {
        return 0;
    }

    *value = acc;
    return 1;
}

int main(void) {
    char line[32];
    uint32_t n;

    uart_init();
    uart_resync_rx();
    uart_puts("FIB READY\r\n");

    for (;;) {
        uint32_t a = 0;
        uint32_t b = 1;
        uint32_t i;

        uart_puts("N> ");
        uart_readline(line, sizeof(line));

        if (!parse_u32(line, &n)) {
            uart_puts("ERR\r\n");
            continue;
        }

        uart_puts("FIB: ");
        for (i = 0; i < n; i++) {
            uart_print_u32(a);
            if (i + 1 < n) {
                uart_puts(", ");
            }

            {
                uint32_t next = a + b;
                a = b;
                b = next;
            }
        }
        uart_puts("\r\n");
    }
}
