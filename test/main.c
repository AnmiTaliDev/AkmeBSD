/* This file is based on code from the NovariaOS project. 
The source code in NovariaOS is licensed under GPLv3. In this project, the file is available under the MIT license. 
See LICENSE in the root of the repository. 

https://github.com/novariaos/novariaos-src
*/


#include <core/kernel/vge/fb_render.h>
#include <core/kernel/kstd.h>
#include <core/kernel/exec.h>
#include <stdint.h>

#define PORT 0x3f8 // COM1

static inline uint8_t inb(uint16_t port) {
    uint8_t res;
    __asm__("inb %w1, %b0" : "=a"(res) : "Nd"(port) : "memory");
    return res;
}

static inline void outb(uint16_t port, uint8_t val) {
    __asm__("outb %b0, %w1" : : "a"(val), "Nd"(port) : "memory");
}

int init_serial() {
    outb(PORT + 1, 0x00);    // Disable all interrupts
    outb(PORT + 3, 0x80);    // Enable DLAB (set baud rate divisor)
    outb(PORT + 0, 0x03);    // Set divisor to 3 (lo byte) 38400 baud
    outb(PORT + 1, 0x00);    //                  (hi byte)
    outb(PORT + 3, 0x03);    // 8 bits, no parity, one stop bit
    outb(PORT + 2, 0xC7);    // Enable FIFO, clear them, with 14-byte threshold
    outb(PORT + 4, 0x0B);    // IRQs enabled, RTS/DSR set
    outb(PORT + 4, 0x1E);    // Set in loopback mode, test the serial chip
    outb(PORT + 0, 0xAE);    // Test serial chip (send byte 0xAE and check if serial returns same byte)

    // Check if serial is faulty (i.e: not same byte as sent)
    if(inb(PORT + 0) != 0xAE) {
        return 1;
    }

    // If serial is not faulty set it in normal operation mode
    // (not-loopback with IRQs enabled and OUT#1 and OUT#2 bits enabled)
    outb(PORT + 4, 0x0F);
    
    return 0;
}

int serial_received() {
    return inb(PORT + 5) & 1;
}

char read_serial() {
    while (serial_received() == 0);

    return inb(PORT);
}

int is_transmit_empty() {
    return inb(PORT + 5) & 0x20;
}

void write_serial(char a) {
    while (is_transmit_empty() == 0);

    outb(PORT, a);
}

void serial_print(const char* str) {
    while (*str) {
        write_serial(*str++);
    }
}


void _start() {
    serial_print("Work!!!\n");
    return;
}