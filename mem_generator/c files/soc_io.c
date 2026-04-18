#include "soc_io.h"

void uart_init(void) {
    UART_CONTROL = UART_CTRL_RST_TX | UART_CTRL_RST_RX;
}

void uart_putc(char c) {
    while ((UART_TX_STATUS & UART_TX_READY_MASK) == 0u) {
    }
    UART_TX_DATA = (uint32_t)(uint8_t)c;
}

void uart_puts(const char *s) {
    while (*s) {
        uart_putc(*s++);
    }
}

int uart_getc_nonblock(void) {
    uint32_t status = UART_RX_STATUS;
    if (status & UART_RX_OVERRUN_MASK) {
        UART_CONTROL = UART_CTRL_RST_RX;
    }
    if ((status & UART_RX_VALID_MASK) == 0u) {
        return -1;
    }
    return (int)(UART_RX_DATA & 0xffu);
}

char uart_getc_blocking(void) {
    int c;
    while ((c = uart_getc_nonblock()) < 0) {
    }
    return (char)c;
}

void uart_flush_rx(void) {
    while (uart_getc_nonblock() >= 0) {
    }
}

void uart_resync_rx(void) {
    int idle_count = 0;

    uart_flush_rx();

    while (idle_count < 50000) {
        if (uart_getc_nonblock() >= 0) {
            idle_count = 0;
        } else {
            idle_count++;
        }
    }

    uart_flush_rx();
}

void uart_print_u32(uint32_t value) {
    char buf[10];
    int idx = 0;

    do {
        buf[idx++] = (char)('0' + (value % 10u));
        value /= 10u;
    } while (value != 0u);

    while (idx > 0) {
        uart_putc(buf[--idx]);
    }
}

void uart_print_i32(int32_t value) {
    if (value < 0) {
        uart_putc('-');
        uart_print_u32((uint32_t)(-value));
    } else {
        uart_print_u32((uint32_t)value);
    }
}

void uart_readline(char *buf, int max_len) {
    int idx = 0;

    if (max_len <= 0) {
        return;
    }

    for (;;) {
        char c = uart_getc_blocking();

        if (c == '\r' || c == '\n') {
            uart_putc('\r');
            uart_putc('\n');
            break;
        }

        if ((c == '\b' || c == 127) && idx > 0) {
            idx--;
            uart_putc('\b');
            uart_putc(' ');
            uart_putc('\b');
            continue;
        }

        if (idx < max_len - 1) {
            if ((unsigned char)c < 32u || (unsigned char)c > 126u) {
                continue;
            }
            buf[idx++] = c;
            uart_putc(c);
        }
    }

    buf[idx] = '\0';
}
