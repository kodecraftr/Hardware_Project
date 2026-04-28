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

static int is_prime(uint32_t n) {
    uint32_t d;

    if (n < 2u) {
        return 0;
    }
    if (n == 2u) {
        return 1;
    }
    if ((n % 2u) == 0u) {
        return 0;
    }

    for (d = 3u; d * d <= n; d += 2u) {
        if ((n % d) == 0u) {
            return 0;
        }
    }
    return 1;
}

int main(void) {
    char line[32];
    uint32_t n;

    uart_init();
    uart_resync_rx();
    uart_puts("PRIME READY\r\n");

    for (;;) {
        uart_puts("NUM> ");
        uart_readline(line, sizeof(line));

        if (!parse_u32(line, &n)) {
            uart_puts("ERR\r\n");
            continue;
        }

        uart_print_u32(n);
        if (is_prime(n)) {
            uart_puts(" IS PRIME\r\n");
        } else {
            uart_puts(" IS NOT PRIME\r\n");
        }
    }
}
