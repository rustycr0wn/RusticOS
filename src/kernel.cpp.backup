/* Minimal RusticOS kernel: clear screen, print header, halt */
#include <stdint.h>

static inline void outb(uint16_t port, uint8_t value) {
    __asm__ __volatile__("outb %0, %1" : : "a"(value), "Nd"(port));
}

static inline void vga_clear(uint8_t fg, uint8_t bg) {
    volatile uint16_t* const vga = (volatile uint16_t*)0xB8000;
    uint16_t attr = (uint16_t)(((uint16_t)bg << 4) | (fg & 0x0F)) << 8;
    for (int i = 0; i < 80 * 25; ++i) vga[i] = attr | ' ';
}

static inline void vga_puts_at(int x, int y, const char* s, uint8_t fg, uint8_t bg) {
    volatile uint16_t* const vga = (volatile uint16_t*)0xB8000;
    uint16_t attr = (uint16_t)(((uint16_t)bg << 4) | (fg & 0x0F)) << 8;
    int idx = y * 80 + x;
    while (*s && idx < 80 * 25) {
        vga[idx++] = attr | (uint8_t)(*s++);
    }
}

static inline void set_cursor_position(int x, int y) {
    uint16_t pos = y * 80 + x;
    
    // VGA cursor control ports
    outb(0x3D4, 0x0F);  // Low byte
    outb(0x3D5, (uint8_t)(pos & 0xFF));
    outb(0x3D4, 0x0E);  // High byte
    outb(0x3D5, (uint8_t)((pos >> 8) & 0xFF));
}

extern "C" void kernel_main() {
    // Colors
    const uint8_t FG_BLACK = 0x0;
    const uint8_t FG_GREEN = 0x2;
    const uint8_t BG_GREEN = 0x2;
    const uint8_t BG_BLACK = 0x0;
    // Clear screen to black
    vga_clear(FG_GREEN, BG_BLACK);

    // Draw header (row 0) with green background, black text, full width
    const char* title = "RusticOS        Level: Kernel        Version:1.0.0";
    int len = 50;
    int x = (80 - len) / 2;
    for (int col = 0; col < 80; ++col) {
        char ch = (col >= x && col < x + len) ? title[col - x] : ' ';
        vga_puts_at(col, 0, &ch, FG_BLACK, BG_GREEN);
    }

    // Print prompt "> " at start of row 1
    vga_puts_at(0, 1, ">", FG_GREEN, BG_BLACK);

    // Place cursor right after the "> " prompt (position 2,1)
    set_cursor_position(1, 1);

    // Halt forever
    for (;;) { 
        __asm__ __volatile__("hlt"); 
    }
}
