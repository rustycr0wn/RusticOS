#include "keyboard.h"

// Global keyboard instance
KeyboardDriver keyboard;

// Scan code to ASCII conversion tables
static const uint8_t scan_code_table[] = {
    0, 0, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 0,
    0, 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', 0,
    0, 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`', 0, '\\',
    'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0, 0, 0, ' '
};

static const uint8_t scan_code_table_shift[] = {
    0, 0, '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', 0,
    0, 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', 0,
    0, 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~', 0, '|',
    'Z', 'X', 'C', 'V', 'B', 'N', 'M', '<', '>', '?', 0, 0, 0, ' '
};

KeyboardDriver::KeyboardDriver() 
    : head(0), tail(0), shift_pressed(false), ctrl_pressed(false), alt_pressed(false) {
}

void KeyboardDriver::init() {
    // Clear buffer
    head = tail = 0;
    
    // Reset modifier states
    shift_pressed = ctrl_pressed = alt_pressed = false;
    
    // Enable keyboard interrupts (this would be done in the interrupt setup)
}

void KeyboardDriver::handle_interrupt(uint8_t scan_code) {
    // Check if this is a key release (bit 7 set)
    bool key_released = (scan_code & 0x80) != 0;
    uint8_t key_code = scan_code & 0x7F;
    
    // Handle modifier keys
    switch (key_code) {
        case 0x2A: // Left Shift
        case 0x36: // Right Shift
            shift_pressed = !key_released;
            break;
        case 0x1D: // Left Ctrl
        case 0x9D: // Right Ctrl
            ctrl_pressed = !key_released;
            break;
        case 0x38: // Left Alt
        case 0xB8: // Right Alt
            alt_pressed = !key_released;
            break;
    }
    
    // Only process key presses, not releases (for now)
    if (key_released) return;
    
    // Convert scan code to ASCII
    uint8_t ascii = scan_code_to_ascii(key_code, shift_pressed);
    
    // Create key event
    KeyEvent event;
    event.scan_code = key_code;
    event.ascii = ascii;
    event.pressed = true;
    event.shift = shift_pressed;
    event.ctrl = ctrl_pressed;
    event.alt = alt_pressed;
    
    // Add to buffer
    uint32_t next_head = (head + 1) % KEYBOARD_BUFFER_SIZE;
    if (next_head != tail) {
        buffer[head] = event;
        head = next_head;
    }
}

uint8_t KeyboardDriver::scan_code_to_ascii(uint8_t scan_code, bool shift) {
    if (scan_code >= sizeof(scan_code_table)) return 0;
    
    if (shift) {
        return scan_code_table_shift[scan_code];
    } else {
        return scan_code_table[scan_code];
    }
}

bool KeyboardDriver::get_key_event(KeyEvent& event) {
    if (head == tail) return false;
    
    event = buffer[tail];
    tail = (tail + 1) % KEYBOARD_BUFFER_SIZE;
    return true;
}

bool KeyboardDriver::is_key_pressed(uint8_t /*scan_code*/) {
    // Simple implementation - in a real OS, you'd track individual key states
    return false;
}