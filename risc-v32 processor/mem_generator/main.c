#include <stdint.h>

#define UART_TX      *((volatile uint32_t*) 0x40000000)
#define UART_STATUS  *((volatile uint32_t*) 0x40000008)

int main() {
    while (1) {
        // Wait until TX is NOT busy
        while ((UART_STATUS & 0x01) == 1); 
        
        // Send the letter 'U' 
        // ('U' is 0x55, which is 01010101 in binary. It is the perfect square wave for testing!)
        UART_TX = 'U'; 
        
        // Add a small software delay so you don't overwhelm the terminal
        for(volatile int j = 0; j < 100000; j++);
    }
    return 0;
}