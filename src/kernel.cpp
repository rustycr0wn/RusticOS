/* RusticOS kernel with command-line interface and filesystem */
#include "terminal.h"
#include "types.h"
#include "keyboard.h"
#include "filesystem.h"
#include "command.h"
#include <cstring>

#define VGA_ATTRIBUTE(fg, bg) (((bg) << 4) | (fg))

// Track prompt start position to protect it from backspace
static uint16_t prompt_start_x = 0;
static uint16_t prompt_start_y = 0;
// Simple keyboard input polling (since we don't have interrupts set up yet)
static inline uint8_t inb(uint16_t port) {
    uint8_t result;
    __asm__ __volatile__("inb %1, %0" : "=a"(result) : "Nd"(port));
    return result;
}

static inline void outb(uint16_t port, uint8_t value) {
    __asm__ __volatile__("outb %0, %1" : : "a"(value), "Nd"(port));
}

// Simple keyboard polling function - just echo input for now
bool poll_keyboard() {
    // Check if keyboard has data
    if ((inb(0x64) & 0x01) == 0) {
        return false; // No data available
    }
    
    uint8_t scan_code = inb(0x60);
    
    // Handle key press/release
    bool key_released = (scan_code & 0x80) != 0;
    uint8_t key_code = scan_code & 0x7F;
    
    if (key_released) {
        return false; // Ignore key releases for now
    }
    
    // Convert scan code to ASCII (simplified)
    char ascii = 0;
    switch (key_code) {
        case 0x02: ascii = '1'; break;
        case 0x03: ascii = '2'; break;
        case 0x04: ascii = '3'; break;
        case 0x05: ascii = '4'; break;
        case 0x06: ascii = '5'; break;
        case 0x07: ascii = '6'; break;
        case 0x08: ascii = '7'; break;
        case 0x09: ascii = '8'; break;
        case 0x0A: ascii = '9'; break;
        case 0x0B: ascii = '0'; break;
        case 0x0E: ascii = '\b'; break; // Backspace
        case 0x1C: ascii = '\n'; break; // Enter
        case 0x39: ascii = ' '; break;  // Space
        case 0x10: ascii = 'q'; break;
        case 0x11: ascii = 'w'; break;
        case 0x12: ascii = 'e'; break;
        case 0x13: ascii = 'r'; break;
        case 0x14: ascii = 't'; break;
        case 0x15: ascii = 'y'; break;
        case 0x16: ascii = 'u'; break;
        case 0x17: ascii = 'i'; break;
        case 0x18: ascii = 'o'; break;
        case 0x19: ascii = 'p'; break;
        case 0x1E: ascii = 'a'; break;
        case 0x1F: ascii = 's'; break;
        case 0x20: ascii = 'd'; break;
        case 0x21: ascii = 'f'; break;
        case 0x22: ascii = 'g'; break;
        case 0x23: ascii = 'h'; break;
        case 0x24: ascii = 'j'; break;
        case 0x25: ascii = 'k'; break;
        case 0x26: ascii = 'l'; break;
        case 0x2C: ascii = 'z'; break;
        case 0x2D: ascii = 'x'; break;
        case 0x2E: ascii = 'c'; break;
        case 0x2F: ascii = 'v'; break;
        case 0x30: ascii = 'b'; break;
        case 0x31: ascii = 'n'; break;
        case 0x32: ascii = 'm'; break;
        default: return false;
    }
    
    if (ascii != 0) {
        // Just echo the character for now
        if (ascii == '\b') {
            uint16_t curX = terminal.getCursorX();
            uint16_t curY = terminal.getCursorY();
            if (curX > 0) {
                terminal.setCursor(curX - 1, curY);
                terminal.putChar(' ');
                terminal.setCursor(curX - 1, curY);
            }
        } else if (ascii == '\n') {
            terminal.putChar('\n');
            terminal.write(">");
        } else {
            terminal.putChar(ascii);
        }
        return true;
    }
    
    return false;
}

// Write title text to row 0 with black on green background
void write_title(const char* title) {
    volatile uint16_t* vga = (volatile uint16_t*)0xB8000;
    
    // GREEN background (2), BLACK foreground (0)
    // Attribute format: (BG << 4) | FG = (2 << 4) | 0 = 0x20
    // Shift left 8 bits for high byte: 0x2000
    uint16_t attr = 0x2000;
    
    // Fill entire row 0 with spaces first
    for (int col = 0; col < 80; col++) {
        vga[col] = (uint16_t)' ' | attr;
    }
    
    // Write each character of the title manually
    //vga[15] = (uint16_t)'R' | attr;
    //vga[16] = (uint16_t)'u' | attr;
    //vga[17] = (uint16_t)'s' | attr;
    //vga[18] = (uint16_t)'t' | attr;
    //vga[19] = (uint16_t)'i' | attr;
    //vga[20] = (uint16_t)'c' | attr;
    //vga[21] = (uint16_t)'O' | attr;
    //vga[22] = (uint16_t)'S' | attr;
    //vga[23] = (uint16_t)' ' | attr;
    //vga[24] = (uint16_t)' ' | attr;
    //vga[25] = (uint16_t)' ' | attr;
    //vga[26] = (uint16_t)' ' | attr;
    //vga[27] = (uint16_t)' ' | attr;
    //vga[28] = (uint16_t)' ' | attr;
    //vga[29] = (uint16_t)' ' | attr;
    //vga[30] = (uint16_t)' ' | attr;
    //vga[31] = (uint16_t)'L' | attr;
    //vga[32] = (uint16_t)'e' | attr;
    //vga[33] = (uint16_t)'v' | attr;
    //vga[34] = (uint16_t)'e' | attr;
    //vga[35] = (uint16_t)'l' | attr;
    //vga[36] = (uint16_t)':' | attr;
    //vga[37] = (uint16_t)'K' | attr;
    //vga[38] = (uint16_t)'e' | attr;
    //vga[39] = (uint16_t)'r' | attr;
    //vga[40] = (uint16_t)'n' | attr;
    //vga[41] = (uint16_t)'e' | attr;
    //vga[42] = (uint16_t)'l' | attr;
    //vga[43] = (uint16_t)' ' | attr;
    //vga[44] = (uint16_t)' ' | attr;
    //vga[45] = (uint16_t)' ' | attr;
    //vga[46] = (uint16_t)' ' | attr;
    //vga[47] = (uint16_t)' ' | attr;
    //vga[48] = (uint16_t)' ' | attr;
    //vga[49] = (uint16_t)' ' | attr;
    //vga[50] = (uint16_t)' ' | attr;
    //vga[51] = (uint16_t)'V' | attr;
    //vga[52] = (uint16_t)'e' | attr;
    //vga[53] = (uint16_t)'r' | attr;
    //vga[54] = (uint16_t)'s' | attr;
    //vga[55] = (uint16_t)'i' | attr;
    //vga[56] = (uint16_t)'o' | attr;
    //vga[57] = (uint16_t)'n' | attr;
    //vga[58] = (uint16_t)':' | attr;
    //vga[59] = (uint16_t)'1' | attr;
    //vga[60] = (uint16_t)'.' | attr;
    //vga[61] = (uint16_t)'0' | attr;
    //vga[62] = (uint16_t)'.' | attr;
    //vga[63] = (uint16_t)'0' | attr;
}

// Serial output helper
static void serial_write(const char* str) {
    while (*str) {
        // Wait for transmit ready
        while ((inb(0x3FD) & 0x20) == 0);
        outb(0x3F8, *str);
        str++;
    }
}

extern "C" void kernel_main() {
    // Initialize serial for debugging
    outb(0x3F8 + 1, 0x00);    // Disable all interrupts
    outb(0x3F8 + 3, 0x80);    // Enable DLAB (set baud rate divisor)
    outb(0x3F8 + 0, 0x03);    // Set divisor to 3 (115200 baud)
    outb(0x3F8 + 1, 0x00);    // Set divisor high byte to 0
    outb(0x3F8 + 3, 0x03);    // Disable DLAB, set 8 bits, no parity, 1 stop bit
    outb(0x3F8 + 2, 0xC7);    // Enable FIFO, clear them, set level to 14 bytes
    
    serial_write("===== KERNEL STARTED =====\n");
    
    // Write to VGA buffer
    volatile uint16_t* vga = (volatile uint16_t*)0xB8000;
    
    serial_write("Writing title to row 0...\n");
    
    // Fill row 0 with spaces first (green background, black text)
    // Use volatile writes and read-modify-write to prevent compiler optimizations
    uint16_t space_attr = (uint16_t)' ' | 0x2000;
    for (int col = 0; col < 80; col++) {
        *(vga + col) = space_attr;
        asm volatile("");  // Memory barrier to force write
    }
    
    serial_write("Row cleared.\n");
    
    // Write title manually at column 15 (like before)
    uint16_t attr = 0x2000;
    
    vga[15] = (uint16_t)'R' | attr; asm volatile("");
    vga[16] = (uint16_t)'u' | attr; asm volatile("");
    vga[17] = (uint16_t)'s' | attr; asm volatile("");
    vga[18] = (uint16_t)'t' | attr; asm volatile("");
    vga[19] = (uint16_t)'i' | attr; asm volatile("");
    vga[20] = (uint16_t)'c' | attr; asm volatile("");
    vga[21] = (uint16_t)'O' | attr; asm volatile("");
    vga[22] = (uint16_t)'S' | attr; asm volatile("");
    vga[23] = (uint16_t)' ' | attr; asm volatile("");
    vga[24] = (uint16_t)' ' | attr; asm volatile("");
    vga[25] = (uint16_t)' ' | attr; asm volatile("");
    vga[26] = (uint16_t)' ' | attr; asm volatile("");
    vga[27] = (uint16_t)' ' | attr; asm volatile("");
    vga[28] = (uint16_t)' ' | attr; asm volatile("");
    vga[29] = (uint16_t)' ' | attr; asm volatile("");
    vga[30] = (uint16_t)' ' | attr; asm volatile("");
    vga[31] = (uint16_t)'L' | attr; asm volatile("");
    vga[32] = (uint16_t)'e' | attr; asm volatile("");
    vga[33] = (uint16_t)'v' | attr; asm volatile("");
    vga[34] = (uint16_t)'e' | attr; asm volatile("");
    vga[35] = (uint16_t)'l' | attr; asm volatile("");
    vga[36] = (uint16_t)':' | attr; asm volatile("");
    vga[37] = (uint16_t)'K' | attr; asm volatile("");
    vga[38] = (uint16_t)'e' | attr; asm volatile("");
    vga[39] = (uint16_t)'r' | attr; asm volatile("");
    vga[40] = (uint16_t)'n' | attr; asm volatile("");
    vga[41] = (uint16_t)'e' | attr; asm volatile("");
    vga[42] = (uint16_t)'l' | attr; asm volatile("");
    vga[43] = (uint16_t)' ' | attr; asm volatile("");
    vga[44] = (uint16_t)' ' | attr; asm volatile("");
    vga[45] = (uint16_t)' ' | attr; asm volatile("");
    vga[46] = (uint16_t)' ' | attr; asm volatile("");
    vga[47] = (uint16_t)' ' | attr; asm volatile("");
    vga[48] = (uint16_t)' ' | attr; asm volatile("");
    vga[49] = (uint16_t)' ' | attr; asm volatile("");
    vga[50] = (uint16_t)' ' | attr; asm volatile("");
    vga[51] = (uint16_t)'V' | attr; asm volatile("");
    vga[52] = (uint16_t)'e' | attr; asm volatile("");
    vga[53] = (uint16_t)'r' | attr; asm volatile("");
    vga[54] = (uint16_t)'s' | attr; asm volatile("");
    vga[55] = (uint16_t)'i' | attr; asm volatile("");
    vga[56] = (uint16_t)'o' | attr; asm volatile("");
    vga[57] = (uint16_t)'n' | attr; asm volatile("");
    vga[58] = (uint16_t)':' | attr; asm volatile("");
    vga[59] = (uint16_t)'1' | attr; asm volatile("");
    vga[60] = (uint16_t)'.' | attr; asm volatile("");
    vga[61] = (uint16_t)'0' | attr; asm volatile("");
    vga[62] = (uint16_t)'.' | attr; asm volatile("");
    vga[63] = (uint16_t)'0' | attr; asm volatile("");
    
    serial_write("Title written.\n");
    
    // Initialize terminal (this sets up VGA text mode)
    serial_write("Initializing terminal...\n");
    terminal.showCursor(true);
    
    // Clear rows 1-24 with black background and light grey text
    serial_write("Clearing screen rows 1-24...\n");
    for (int row = 1; row < 25; ++row) {
        for (int col = 0; col < 80; ++col) {
            vga[row * 80 + col] = (uint16_t)' ' | (((uint16_t)(0 << 4) | 7) << 8);  // BLACK bg, LIGHT_GREY fg
        }
    }
    
    // Set terminal colors to GREEN on BLACK and position cursor at row 2
    serial_write("Setting colors and positioning cursor...\n");
    terminal.setColor(TerminalColor::GREEN, TerminalColor::BLACK);
    terminal.setCursor(0, 2);
    
    // Print welcome messages
    serial_write("Writing welcome messages...\n");
    terminal.write("Welcome to RusticOS!\n");
    terminal.write("Type 'help' for available commands.\n");
    terminal.write("Root filesystem mounted at '/'\n\n");
    
    // Show prompt
    serial_write("Writing prompt...\n");
    terminal.write(">");
    prompt_start_x = terminal.getCursorX();
    prompt_start_y = terminal.getCursorY();
    
    serial_write("Setup complete, entering main loop.\n");
    
    // Main kernel loop
    while (true) {
        poll_keyboard();
        
        // Small delay to prevent excessive CPU usage
        for (volatile int i = 0; i < 10000; i++);
    }
}
