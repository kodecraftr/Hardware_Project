#include "soc_io.h"

static int is_digit(char c) {
    return (c >= '0' && c <= '9');
}

static int is_space(char c) {
    return (c == ' ' || c == '\t');
}

static void skip_spaces(const char **ps) {
    while (is_space(**ps)) {
        (*ps)++;
    }
}

static int parse_signed_i32(const char **ps, int *out_value) {
    int sign = 1;
    int value = 0;
    const char *s = *ps;

    skip_spaces(&s);

    if (*s == '-') {
        sign = -1;
        s++;
    } else if (*s == '+') {
        s++;
    }

    if (!is_digit(*s)) {
        return 0;
    }

    while (is_digit(*s)) {
        value = value * 10 + (*s - '0');
        s++;
    }

    *out_value = sign * value;
    *ps = s;
    return 1;
}

static int parse_pair(const char *line, int *lhs, int *rhs) {
    const char *s = line;

    if (!parse_signed_i32(&s, lhs)) {
        return 0;
    }
    if (!parse_signed_i32(&s, rhs)) {
        return 0;
    }
    skip_spaces(&s);
    return (*s == '\0');
}

int main(void) {
    char line[64];
    int a;
    int b;

    uart_init();
    uart_resync_rx();
    uart_puts("ARITH READY\r\n");
    uart_puts("Enter: <a> <b>\r\n");

    for (;;) {
        uart_puts("PAIR> ");
        uart_readline(line, sizeof(line));

        if (!parse_pair(line, &a, &b)) {
            uart_puts("ERR\r\n");
            continue;
        }

        uart_puts("ADD = ");
        uart_print_i32(a + b);
        uart_puts("\r\nSUB = ");
        uart_print_i32(a - b);
        uart_puts("\r\nMUL = ");
        uart_print_i32(a * b);

        if (b == 0) {
            uart_puts("\r\nDIV = DIV BY ZERO");
            uart_puts("\r\nREM = DIV BY ZERO\r\n");
        } else {
            uart_puts("\r\nDIV = ");
            uart_print_i32(a / b);
            uart_puts("\r\nREM = ");
            uart_print_i32(a % b);
            uart_puts("\r\n");
        }
    }
}
