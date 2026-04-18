#ifndef SOC_IO_H
#define SOC_IO_H

#include <stdint.h>

#define UART_BASE      0x10000000u
#define UART_TX_DATA   (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_TX_STATUS (*(volatile uint32_t *)(UART_BASE + 0x04))
#define UART_RX_DATA   (*(volatile uint32_t *)(UART_BASE + 0x08))
#define UART_RX_STATUS (*(volatile uint32_t *)(UART_BASE + 0x0C))
#define UART_CONTROL   (*(volatile uint32_t *)(UART_BASE + 0x10))

#define UART_TX_READY_MASK   0x1u
#define UART_RX_VALID_MASK   0x1u
#define UART_RX_OVERRUN_MASK 0x2u
#define UART_CTRL_RST_TX     0x1u
#define UART_CTRL_RST_RX     0x2u

void uart_init(void);
void uart_putc(char c);
void uart_puts(const char *s);
int  uart_getc_nonblock(void);
char uart_getc_blocking(void);
void uart_flush_rx(void);
void uart_resync_rx(void);
void uart_print_u32(uint32_t value);
void uart_print_i32(int32_t value);
void uart_readline(char *buf, int max_len);

#endif
