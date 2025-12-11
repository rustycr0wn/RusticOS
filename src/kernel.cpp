/*
 * RusticOS Kernel Main Module
 * 
 * This module handles:
 * - Hardware initialization (serial, VGA, keyboard)
 * - Kernel startup and main event loop
 * - Command-line interface integration
 * - Keyboard input polling and processing
 * 
 * The kernel runs in protected mode with no interrupts (polling-based).
 * All hardware access is done via direct I/O port operations.
 */

#include "terminal.h"
#include "types.h"
#include "keyboard.h"
#include "filesystem.h"
#include "command.h"
#include <cstring>

/* ============================================================================
 * HARDWARE CONSTANTS & MACROS
 * ============================================================================ */

// VGA Text Mode Constants
#define VGA_BUFFER      ((volatile uint16_t*)0xB8000)
#define VGA_WIDTH       80
#define VGA_HEIGHT      25
#define VGA_ATTR(fg, bg) (((bg) << 4) | (fg))

// VGA I/O Port Constants
#define VGA_STATUS_PORT 0x3DA  // Read-only status register
#define VGA_CRTC_INDEX  0x3D4  // Index register for cursor control
#define VGA_CRTC_DATA   0x3D5  // Data register for cursor control
#define CRTC_CURSOR_HIGH 0x0E  // Cursor location high byte
#define CRTC_CURSOR_LOW  0x0F  // Cursor location low byte

// Serial Port (COM1) Constants
#define SERIAL_PORT     0x3F8
#define SERIAL_BAUD_DIV 0x03   // Divisor for 115200 baud
#define SERIAL_IER      (SERIAL_PORT + 1)
#define SERIAL_FCR      (SERIAL_PORT + 2)
#define SERIAL_LCR      (SERIAL_PORT + 3)

// PS/2 Keyboard Port Constants
#define KBD_DATA_PORT   0x60
#define KBD_STAT_PORT   0x64
#define KBD_STATUS_HAVE_DATA 0x01

// Keyboard Commands
#define KBD_CMD_DISABLE 0xF5
#define KBD_CMD_SET_SCANCODE 0xF0
#define KBD_SCANCODE_SET_1 0x01
#define KBD_CMD_ENABLE  0xF4
#define KBD_SCANCODE_RELEASE 0x80

// VGA Color Attributes (BLACK bg, BLACK text)
#define VGA_BLACK_BLACK 0x0700
// VGA Color Attributes (GREEN bg, BLACK text)
#define VGA_GREEN_BLACK 0x2000

// Timing Constants (loop counts for delays)
#define DELAY_SHORT     10000
#define DELAY_MEDIUM    100000

/* ============================================================================
 * GLOBAL VARIABLES
 * ============================================================================ */

extern CommandSystem command_system;

// Prompt position tracking (prevents backspace from deleting the prompt '>')
static uint16_t prompt_start_x = 0;
static uint16_t prompt_start_y = 0;

/* ============================================================================
 * INLINE I/O PORT OPERATIONS
 * ============================================================================ */

/**
 * Read a byte from an I/O port
 * @param port The port address to read from
 * @return The byte read from the port
 */
static inline uint8_t inb(uint16_t port) {
    uint8_t result;
    __asm__ __volatile__("inb %1, %0" : "=a"(result) : "Nd"(port));
    return result;
}

/**
 * Write a byte to an I/O port
 * @param port The port address to write to
 * @param value The byte to write
 */
static inline void outb(uint16_t port, uint8_t value) {
    __asm__ __volatile__("outb %0, %1" : : "a"(value), "Nd"(port));
}

/* ============================================================================
 * SIMPLE VGA TEXT PRINTER
 * ============================================================================ */

/**
 * Print a string to VGA at a specific row
 * Uses individual character writes to bypass compiler optimization
 * 
 * @param row Screen row (0-24)
 * @param text String to print
 * @param color VGA attribute byte (foreground and background colors)
 */
static void print_at_row(int row, const char* text, uint16_t color) {
    volatile uint16_t* vga = VGA_BUFFER;
    int offset = row * VGA_WIDTH;
    
    for (int i = 0; text[i] != '\0'; i++) {
        uint16_t entry = ((uint16_t)text[i]) | color;
        vga[offset + i] = entry;
        // Memory barrier to prevent compiler optimization
        __asm__ __volatile__("" : : : "memory");
    }
}

/* ============================================================================
 * KEYBOARD INPUT HANDLING
 * ============================================================================ */

/**
 * PS/2 Keyboard scan code to ASCII conversion table
 * Maps PS/2 scan codes to ASCII characters
 */
static const char scancode_to_ascii[] = {
    // 0x00-0x09
    0, 0, '1', '2', '3', '4', '5', '6', '7', '8',
    // 0x0A-0x13
    '9', '0', 0, 0, '\b', 0, 'q', 'w', 'e', 'r',
    // 0x14-0x1D
    't', 'y', 'u', 'i', 'o', 'p', 0, 0, '\n', 0,
    // 0x1E-0x27
    'a', 's', 'd', 'f', 'g', 'h', 'j', 'k',
    // 0x28-0x31
    'l', 0, 0, 0, 0, 0, 'z', 'x', 'c', 'v',
    // 0x32-0x3B
    'b', 'n', 'm', 0, 0, 0, ' ', 0
};

/**
 * Convert PS/2 scan code to ASCII character
 * Handles key press/release detection
 * 
 * @param scan_code Raw PS/2 scan code from keyboard
 * @return ASCII character (0 if invalid/release code)
 */
static char scancode_to_char(uint8_t scan_code) {
    // Check if this is a key release event (high bit set)
    if (scan_code & KBD_SCANCODE_RELEASE) {
        return 0;  // Ignore key releases
    }
    
    // Get the base scan code
    uint8_t key_code = scan_code & 0x7F;
    
    // Check bounds
    if (key_code >= sizeof(scancode_to_ascii)) {
        return 0;
    }
    
    return scancode_to_ascii[key_code];
}

/**
 * Poll keyboard for input and process any keypresses
 * 
 * This function:
 * - Checks if keyboard has data available
 * - Reads the scan code from the keyboard
 * - Converts scan code to ASCII
 * - Sends input to the command system
 * - Executes commands when user presses Enter
 * 
 * @return true if a key was processed, false if no key available
 */
bool poll_keyboard() {
    // Check if keyboard has data available
    if ((inb(KBD_STAT_PORT) & KBD_STATUS_HAVE_DATA) == 0) {
        return false;  // No data in keyboard buffer
    }
    
    uint8_t scan_code = inb(KBD_DATA_PORT);
    char ascii = scancode_to_char(scan_code);
    
    if (ascii == 0) {
        return false;  // Invalid or release code
    }
    
    // Send the input character to the command system for processing
    command_system.process_input(ascii);
    
    // Check if a complete command has been entered (user pressed Enter)
    if (command_system.is_input_complete()) {
        command_system.execute_command();
        command_system.reset_input();
        terminal.write(">");  // Display prompt for next command
    }
    
    return true;
}

/* ============================================================================
 * VGA TEXT MODE HELPERS
 * ============================================================================
 * Write title text to row 0 with green background
 * 
 * Title format: "RusticOS        Level:Kernel        Version:1.0.0"
 * - Displayed on row 0 with green background and black text
 * - Spans the full 80-character width
*/

static void write_title() {
    volatile uint16_t* vga = VGA_BUFFER;
    uint16_t attr = VGA_GREEN_BLACK;
    
    // Clear the entire first row with spaces
    for (int col = 0; col < VGA_WIDTH; col++) {
        vga[col] = (uint16_t)' ' | attr;
    }
    
    // Write title string character by character with explicit delays
    // Position 15: "RusticOS"
    vga[15] = (uint16_t)'R' | attr;
    vga[16] = (uint16_t)'u' | attr;
    vga[17] = (uint16_t)'s' | attr;
    vga[18] = (uint16_t)'t' | attr;
    vga[19] = (uint16_t)'i' | attr;
    vga[20] = (uint16_t)'c' | attr;
    vga[21] = (uint16_t)'O' | attr;
    vga[22] = (uint16_t)'S' | attr;
    
    // Position 31: "Level:Kernel"
    vga[31] = (uint16_t)'L' | attr;
    vga[32] = (uint16_t)'e' | attr;
    vga[33] = (uint16_t)'v' | attr;
    vga[34] = (uint16_t)'e' | attr;
    vga[35] = (uint16_t)'l' | attr;
    vga[36] = (uint16_t)':' | attr;
    vga[37] = (uint16_t)'K' | attr;
    vga[38] = (uint16_t)'e' | attr;
    vga[39] = (uint16_t)'r' | attr;
    vga[40] = (uint16_t)'n' | attr;
    vga[41] = (uint16_t)'e' | attr;
    vga[42] = (uint16_t)'l' | attr;
    
    // Position 51: "Version:1.0.0"
    vga[51] = (uint16_t)'V' | attr;
    vga[52] = (uint16_t)'e' | attr;
    vga[53] = (uint16_t)'r' | attr;
    vga[54] = (uint16_t)'s' | attr;
    vga[55] = (uint16_t)'i' | attr;
    vga[56] = (uint16_t)'o' | attr;
    vga[57] = (uint16_t)'n' | attr;
    vga[58] = (uint16_t)':' | attr;
    vga[59] = (uint16_t)'1' | attr;
    vga[60] = (uint16_t)'.' | attr;
    vga[61] = (uint16_t)'0' | attr;
    vga[62] = (uint16_t)'.' | attr;
    vga[63] = (uint16_t)'0' | attr;
}

/* ============================================================================
 * HARDWARE INITIALIZATION
 * ============================================================================ */

/**
 * Write a string to serial port for debugging
 * 
 * Used during boot to provide status messages.
 * Output appears on COM1 (115200 baud).
 * 
 * @param str Null-terminated string to output
 */
static void serial_write(const char* str) {
    while (*str) {
        outb(SERIAL_PORT, *str);
        // Small delay to ensure output completes
        for (volatile int i = 0; i < DELAY_SHORT; i++);
        str++;
    }
}

/**
 * Initialize serial port (COM1) for debugging output
 * 
 * Configuration:
 * - Baud rate: 115200
 * - Data bits: 8
 * - Parity: None
 * - Stop bits: 1
 */
static void init_serial() {
    outb(SERIAL_IER, 0x00);        // Disable all interrupts
    outb(SERIAL_LCR, 0x80);        // Enable DLAB (set baud rate divisor)
    outb(SERIAL_PORT, SERIAL_BAUD_DIV);     // Set divisor low byte (115200 baud)
    outb(SERIAL_IER, 0x00);        // Set divisor high byte to 0
    outb(SERIAL_LCR, 0x03);        // Disable DLAB, set 8 bits, no parity, 1 stop
    outb(SERIAL_FCR, 0xC7);        // Enable FIFO, clear it, set level to 14 bytes
}

/**
 * Initialize VGA text mode display for QEMU compatibility
 * 
 * CRITICAL: Must write to VGA memory FIRST to trigger QEMU display init.
 * Then we can safely access VGA control registers.
 * 
 * Steps:
 * 1. Fill VGA buffer with spaces (triggers display init)
 * 2. Access VGA control registers to confirm display is active
 * 3. Set initial cursor position
 */
static void init_vga() {
    volatile uint16_t* vga = VGA_BUFFER;
    
    // Step 1: Write to VGA memory to trigger QEMU display initialization
    // MUST happen before any register access
    for (int i = 0; i < VGA_WIDTH * VGA_HEIGHT; i++) {
        vga[i] = (uint16_t)' ' | VGA_BLACK_BLACK;  // BLACK text on BLACK bg
    }
    
    // Small delay to ensure writes are processed
    for (volatile int delay = 0; delay < DELAY_MEDIUM; delay++);
    
    // Step 2: Access VGA status register to confirm display is active
    uint8_t status = inb(VGA_STATUS_PORT);
    (void)status;  // Suppress unused variable warning
    for (volatile int i = 0; i < DELAY_SHORT; i++);
    
    // Step 3: Set initial cursor position to 0,0 via CRTC registers
    outb(VGA_CRTC_INDEX, CRTC_CURSOR_HIGH);
    outb(VGA_CRTC_DATA, 0x00);
    outb(VGA_CRTC_INDEX, CRTC_CURSOR_LOW);
    outb(VGA_CRTC_DATA, 0x00);
    
    for (volatile int i = 0; i < DELAY_SHORT; i++);
}

/**
 * Set cursor position via VGA CRTC registers
 * Position is calculated as: row * 80 + col
 * 
 * @param row Row number (0-24)
 * @param col Column number (0-79)
 */
static void set_cursor_position(uint8_t row, uint8_t col) {
    uint16_t pos = row * VGA_WIDTH + col;
    
    // Set high byte of cursor position
    outb(VGA_CRTC_INDEX, CRTC_CURSOR_HIGH);
    outb(VGA_CRTC_DATA, (uint8_t)(pos >> 8));
    
    // Set low byte of cursor position
    outb(VGA_CRTC_INDEX, CRTC_CURSOR_LOW);
    outb(VGA_CRTC_DATA, (uint8_t)(pos & 0xFF));
    
    for (volatile int i = 0; i < DELAY_SHORT; i++);
}

/**
 * Initialize PS/2 keyboard controller
 * 
 * Sends a series of commands to the keyboard controller:
 * 1. Disable scanning (0xF5)
 * 2. Set scan code set 1 (0xF0 0x01)
 * 3. Enable scanning (0xF4)
 * 
 * This ensures QEMU and real hardware use consistent scan code format.
 */
static void init_keyboard() {
    // Wait for keyboard controller to be ready
    for (volatile int i = 0; i < DELAY_MEDIUM; i++);
    
    // Command: Disable scanning (0xF5)
    outb(KBD_DATA_PORT, KBD_CMD_DISABLE);
    for (volatile int i = 0; i < DELAY_SHORT; i++);
    
    // Read and discard the ACK response
    uint8_t response = inb(KBD_DATA_PORT);
    (void)response;  // Suppress unused variable warning
    for (volatile int i = 0; i < DELAY_SHORT; i++);
    
    // Command: Set scan code set 1 (0xF0)
    outb(KBD_DATA_PORT, KBD_CMD_SET_SCANCODE);
    for (volatile int i = 0; i < DELAY_SHORT; i++);
    inb(KBD_DATA_PORT);  // Read ACK
    for (volatile int i = 0; i < DELAY_SHORT; i++);
    
    // Subcommand: Use scan code set 1 (0x01)
    outb(KBD_DATA_PORT, KBD_SCANCODE_SET_1);
    for (volatile int i = 0; i < DELAY_SHORT; i++);
    inb(KBD_DATA_PORT);  // Read ACK
    for (volatile int i = 0; i < DELAY_SHORT; i++);
    
    // Command: Enable scanning (0xF4)
    outb(KBD_DATA_PORT, KBD_CMD_ENABLE);
    for (volatile int i = 0; i < DELAY_SHORT; i++);
    inb(KBD_DATA_PORT);  // Read ACK
    for (volatile int i = 0; i < DELAY_SHORT; i++);
}

/* ============================================================================
 * KERNEL MAIN ENTRY POINT
 * ============================================================================ */

/**
 * Kernel main entry point
 * 
 * Initialization sequence:
 * 1. Serial port setup for debugging
 * 2. VGA display initialization
 * 3. Terminal display setup
 * 4. Welcome messages display
 * 5. Command prompt display
 * 6. Keyboard controller setup
 * 7. Main event loop (keyboard polling)
 * 
 * NOTE: The kernel runs in protected mode with no interrupts.
 * All I/O is polling-based.
 */
extern "C" void kernel_main() {
    // Initialize serial port for debug output
    init_serial();
    serial_write("===== KERNEL STARTED =====\n");
    
    // Initialize VGA display (CRITICAL: write buffer before register access)
    serial_write("Initializing VGA display...\n");
    init_vga();
    
    // Write the green title bar to row 0
    serial_write("Writing title bar...\n");
    for (int i = 0; i < VGA_WIDTH; i++) {
        VGA_BUFFER[i] = (uint16_t)' ' | VGA_GREEN_BLACK;
    }

    write_title();
    
    // Write text directly to VGA using simple print function
    serial_write("Writing welcome text...\n");
    uint16_t attr = VGA_ATTR(TerminalColor::GREEN, TerminalColor::BLACK);
    
    // Row 2: Welcome message
    print_at_row(2, "Welcome to RusticOS!", attr);
    
    // Row 3: Help text
    print_at_row(3, "Type 'help' for available commands.", attr);
    
    // Row 4: Filesystem info
    print_at_row(4, "Root filesystem mounted at '/'", attr);
    
    // Row 6: Command prompt
    print_at_row(6, ">", attr);
    
    // Set cursor position to right after the '>' prompt (row 6, col 1)
    set_cursor_position(6, 1);
    
    serial_write("Display ready.\n");
    
    // Initialize keyboard controller
    serial_write("Initializing keyboard...\n");
    init_keyboard();
    serial_write("===== KERNEL READY =====\n");
    
    // Main kernel event loop - poll keyboard for input
    while (true) {
        poll_keyboard();
        
        // Small delay to prevent excessive CPU usage
        for (volatile int i = 0; i < DELAY_SHORT; i++);
    }
}
