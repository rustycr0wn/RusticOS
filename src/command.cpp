#include "command.h"
#include "filesystem.h"
#include "terminal.h"
#include <cstddef>

// Global command system instance
CommandSystem command_system;

// Helper function to copy strings safely
static void safe_strcpy(char* dest, const char* src, uint32_t max_len) {
    uint32_t i = 0;
    while (src[i] != '\0' && i < max_len - 1) {
        dest[i] = src[i];
        i++;
    }
    dest[i] = '\0';
}

// Helper function to get string length
static uint32_t safe_strlen(const char* str) {
    uint32_t len = 0;
    while (str[len] != '\0') {
        len++;
    }
    return len;
}

// Helper function to compare strings
static bool safe_strcmp(const char* str1, const char* str2) {
    uint32_t i = 0;
    while (str1[i] != '\0' && str2[i] != '\0') {
        if (str1[i] != str2[i]) return false;
        i++;
    }
    return str1[i] == str2[i];
}

CommandSystem::CommandSystem() 
    : input_pos(0), input_complete(false) {
    input_buffer[0] = '\0';
}

void CommandSystem::process_input(char c) {
    if (input_complete) {
        reset_input();
    }
    
    if (c == '\n' || c == '\r') {
        input_complete = true;
        return;
    }
    
    if (c == '\b' || c == 127) { // Backspace
        if (input_pos > 0) {
            input_pos--;
            input_buffer[input_pos] = '\0';
        }
        return;
    }
    
    if (c >= 32 && c <= 126 && input_pos < MAX_COMMAND_LENGTH - 1) {
        input_buffer[input_pos] = c;
        input_pos++;
        input_buffer[input_pos] = '\0';
    }
}

void CommandSystem::execute_command() {
    if (!input_complete) return;
    
    Command cmd;
    clear_command(cmd);
    parse_command(input_buffer, cmd);
    
    if (cmd.name[0] == '\0') {
        reset_input();
        return;
    }
    
    // Execute command based on name
    if (safe_strcmp(cmd.name, "help")) {
        cmd_help();
    } else if (safe_strcmp(cmd.name, "mkdir")) {
        if (cmd.arg_count > 0) {
            cmd_mkdir(cmd.args[0]);
        } else {
            terminal.write("mkdir: missing operand\n");
        }
    } else if (safe_strcmp(cmd.name, "ls")) {
        cmd_ls();
    } else if (safe_strcmp(cmd.name, "cd")) {
        if (cmd.arg_count > 0) {
            cmd_cd(cmd.args[0]);
        } else {
            cmd_cd("/");
        }
    } else if (safe_strcmp(cmd.name, "pwd")) {
        cmd_pwd();
    } else if (safe_strcmp(cmd.name, "clear")) {
        cmd_clear();
    } else if (safe_strcmp(cmd.name, "echo")) {
        if (cmd.arg_count > 0) {
            cmd_echo(cmd.args[0]);
        } else {
            terminal.write("\n");
        }
    } else {
        terminal.write("Unknown command: ");
        terminal.write(cmd.name);
        terminal.write("\n");
    }
    
    reset_input();
}

void CommandSystem::reset_input() {
    input_pos = 0;
    input_complete = false;
    input_buffer[0] = '\0';
}

void CommandSystem::parse_command(const char* input, Command& cmd) {
    clear_command(cmd);
    
    if (!input || input[0] == '\0') return;
    
    uint32_t pos = 0;
    uint32_t arg_index = 0;
    uint32_t arg_pos = 0;
    bool in_word = false;
    
    while (input[pos] != '\0' && arg_index < MAX_ARGS) {
        char c = input[pos];
        
        if (c == ' ' || c == '\t') {
            if (in_word) {
                // End of current argument
                if (arg_index == 0) {
                    // This was the command name
                    cmd.name[arg_pos] = '\0';
                } else {
                    // This was an argument
                    cmd.args[arg_index - 1][arg_pos] = '\0';
                }
                in_word = false;
                arg_pos = 0;
                if (arg_index > 0) arg_index++;
            }
        } else {
            if (!in_word) {
                in_word = true;
                if (arg_index == 0) {
                    // Start of command name
                } else {
                    // Start of argument
                    arg_index++;
                }
            }
            
            if (arg_index == 0) {
                // Building command name
                if (arg_pos < MAX_COMMAND_LENGTH - 1) {
                    cmd.name[arg_pos] = c;
                    arg_pos++;
                }
            } else {
                // Building argument
                if (arg_pos < MAX_COMMAND_LENGTH - 1) {
                    cmd.args[arg_index - 1][arg_pos] = c;
                    arg_pos++;
                }
            }
        }
        
        pos++;
    }
    
    // Handle end of string
    if (in_word) {
        if (arg_index == 0) {
            cmd.name[arg_pos] = '\0';
        } else {
            cmd.args[arg_index - 1][arg_pos] = '\0';
            arg_index++;
        }
    }
    
    cmd.arg_count = (arg_index > 0) ? arg_index - 1 : 0;
}

void CommandSystem::clear_command(Command& cmd) {
    cmd.name[0] = '\0';
    cmd.arg_count = 0;
    for (uint32_t i = 0; i < MAX_ARGS; i++) {
        cmd.args[i][0] = '\0';
    }
}

void CommandSystem::cmd_help() {
    terminal.write("Available commands:\n");
    terminal.write("  help     - Show this help message\n");
    terminal.write("  mkdir    - Create a directory\n");
    terminal.write("  ls       - List directory contents\n");
    terminal.write("  cd       - Change directory\n");
    terminal.write("  pwd      - Print working directory\n");
    terminal.write("  clear    - Clear the screen\n");
    terminal.write("  echo     - Print text\n");
}

void CommandSystem::cmd_mkdir(const char* name) {
    if (filesystem.mkdir(name)) {
        terminal.write("Directory '");
        terminal.write(name);
        terminal.write("' created successfully\n");
    } else {
        terminal.write("mkdir: cannot create directory '");
        terminal.write(name);
        terminal.write("': Directory already exists or invalid name\n");
    }
}

void CommandSystem::cmd_ls() {
    terminal.write("Directory listing:\n");
    // This will be implemented to show actual directory contents
    terminal.write("  (ls command not fully implemented yet)\n");
}

void CommandSystem::cmd_cd(const char* path) {
    if (filesystem.cd(path)) {
        // Directory changed successfully
    } else {
        terminal.write("cd: ");
        terminal.write(path);
        terminal.write(": No such directory\n");
    }
}

void CommandSystem::cmd_pwd() {
    const char* current_path = filesystem.pwd();
    terminal.write(current_path);
    terminal.write("\n");
}

void CommandSystem::cmd_clear() {
    terminal.clear();
    // Redraw the header
    terminal.setColor(TerminalColor::BLACK, TerminalColor::GREEN);
    const char* title = "RusticOS        Level: Kernel        Version:1.0.0";
    int len = 50;
    int x = (80 - len) / 2;
    for (int col = 0; col < 80; ++col) {
        char ch = (col >= x && col < x + len) ? title[col - x] : ' ';
        terminal.writeAt(&ch, col, 0);
    }
    terminal.setColor(TerminalColor::GREEN, TerminalColor::BLACK);
    terminal.writeAt(">", 0, 1);
    terminal.setCursor(1, 1);
}

void CommandSystem::cmd_echo(const char* text) {
    terminal.write(text);
    terminal.write("\n");
}
