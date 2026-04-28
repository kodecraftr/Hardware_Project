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

static int parse_expr(const char *line, int *lhs, char *op, int *rhs) {
    const char *s = line;

    if (!parse_signed_i32(&s, lhs)) {
        return 0;
    }

    skip_spaces(&s);
    if (*s != '+' && *s != '-' && *s != '*' && *s != '/' && *s != '%') {
        return 0;
    }
    *op = *s++;

    if (!parse_signed_i32(&s, rhs)) {
        return 0;
    }

    skip_spaces(&s);
    return (*s == '\0');
}

static void print_result(int lhs, char op, int rhs) {
    if ((op == '/' || op == '%') && rhs == 0) {
        uart_puts("DIV BY ZERO\r\n");
        return;
    }

    uart_putc('=');

    switch (op) {
        case '+':
            uart_print_i32(lhs + rhs);
            break;
        case '-':
            uart_print_i32(lhs - rhs);
            break;
        case '*':
            uart_print_i32(lhs * rhs);
            break;
        case '/':
            uart_print_i32(lhs / rhs);
            break;
        default:
            uart_print_i32(lhs % rhs);
            break;
    }

    uart_puts("\r\n");
}

int main(void) {
    char line[64];
    int lhs;
    int rhs;
    char op;

    uart_init();
    uart_resync_rx();
    uart_puts("CALC READY\r\n");
    uart_resync_rx();

    for (;;) {
        uart_puts("CALC> ");
        uart_readline(line, sizeof(line));

        if (!parse_expr(line, &lhs, &op, &rhs)) {
            uart_puts("ERR\r\n");
            continue;
        }

        print_result(lhs, op, rhs);
    }
}
