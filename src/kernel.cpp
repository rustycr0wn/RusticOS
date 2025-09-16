/* RusticOS kernel with command-line interface and filesystem */
#include <stdint.h>
#include "terminal.h"
#include "keyboard.h"
#include "filesystem.h"
#include "command.h"

// Simple keyboard input polling (since we don't have interrupts set up yet)
static inline uint8_t inb(uint16_t port) {
    uint8_t result;
    __asm__ __volatile__("inb %1, %0" : "=a"(result) : "Nd"(port));
    return result;
}

static inline void outb(uint16_t port, uint8_t value) {
    __asm__ __volatile__("outb %0, %1" : : "a"(value), "Nd"(port));
}

// Simple keyboard polling function
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
        // Process the character
        if (ascii == '\n') {
            // Execute command
            command_system.execute_command();
            // Show new prompt
            terminal.write("> ");
        } else if (ascii == '\b') {
            // Handle backspace
            command_system.process_input(ascii);
            terminal.putChar('\b');
            terminal.putChar(' ');
            terminal.putChar('\b');
        } else {
            // Regular character
            command_system.process_input(ascii);
            terminal.putChar(ascii);
        }
        return true;
    }
    
    return false;
}

extern "C" void kernel_main() {
    // Initialize components
    terminal.clear();
    
    // Draw header (row 0) with green background, black text, full width
    terminal.setColor(TerminalColor::BLACK, TerminalColor::GREEN);
    const char* title = "RusticOS        Level: Kernel        Version:1.0.0";
    int len = 50;
    int x = (80 - len) / 2;
    for (int col = 0; col < 80; ++col) {
        char ch = (col >= x && col < x + len) ? title[col - x] : ' ';
        terminal.writeAt(&ch, col, 0);
    }
    
    // Set colors for normal text
    terminal.setColor(TerminalColor::GREEN, TerminalColor::BLACK);
    
    // Add extra line before welcome message
    terminal.write("\n");
    
    // Print welcome message
    terminal.write("Welcome to RusticOS!\n");
    terminal.write("Type 'help' for available commands.\n");
    terminal.write("Root filesystem mounted at '/'\n\n");
    
    // Show initial prompt
    terminal.write("> ");
    
    // Main kernel loop
    while (true) {
        // Poll keyboard for input
        poll_keyboard();
        
        // Small delay to prevent excessive CPU usage
        for (volatile int i = 0; i < 10000; i++);
    }
}
