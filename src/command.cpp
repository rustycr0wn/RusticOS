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
    } else if (safe_strcmp(cmd.name, "makedir")) {
        if (cmd.arg_count >= 1) {
            cmd_makedir(cmd.args[0]);
        } else {
            terminal.write("makedir: missing operand\n");
        }
    } else if (safe_strcmp(cmd.name, "makefile")) {
        if (cmd.arg_count >= 1) {
            const char* name = cmd.args[0];
            // Join remaining args with spaces as file content
            char content_buf[MAX_COMMAND_LENGTH];
            uint32_t pos = 0;
            for (uint32_t ai = 1; ai < cmd.arg_count && pos < MAX_COMMAND_LENGTH - 1; ++ai) {
                const char* part = cmd.args[ai];
                for (uint32_t i = 0; part[i] != '\0' && pos < MAX_COMMAND_LENGTH - 1; ++i) {
                    content_buf[pos++] = part[i];
                }
                if (ai + 1 < cmd.arg_count && pos < MAX_COMMAND_LENGTH - 1) {
                    content_buf[pos++] = ' ';
                }
            }
            content_buf[pos] = '\0';
            const char* content = content_buf;
            cmd_makefile(name, content);
        } else {
            terminal.write("makefile: missing operand\n");
        }
    } else if (safe_strcmp(cmd.name, "chdir")) {
        if (cmd.arg_count >= 1) {
            cmd_chdir(cmd.args[0]);
        } else {
            terminal.write("chdir: missing operand\n");
        }
    } else if (safe_strcmp(cmd.name, "cwd")) {
        cmd_cwd();
    } else if (safe_strcmp(cmd.name, "clear")) {
        cmd_clear();
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
    if (!input) return;

    // Skip leading spaces
    uint32_t i = 0;
    while (input[i] == ' ' || input[i] == '\t') i++;
    
    // Parse command name
    uint32_t name_pos = 0;
    while (input[i] != '\0' && input[i] != ' ' && input[i] != '\t' && name_pos < MAX_COMMAND_LENGTH - 1) {
        cmd.name[name_pos++] = input[i++];
    }
    cmd.name[name_pos] = '\0';

    // Parse arguments
    uint32_t arg_index = 0;
    while (input[i] != '\0' && arg_index < MAX_ARGS) {
        // Skip whitespace
        while (input[i] == ' ' || input[i] == '\t') i++;
        if (input[i] == '\0') break;
        // Read one argument
        uint32_t ap = 0;
        while (input[i] != '\0' && input[i] != ' ' && input[i] != '\t' && ap < MAX_COMMAND_LENGTH - 1) {
            cmd.args[arg_index][ap++] = input[i++];
        }
        cmd.args[arg_index][ap] = '\0';
            arg_index++;
    }
    cmd.arg_count = arg_index;
}

void CommandSystem::clear_command(Command& cmd) {
    cmd.name[0] = '\0';
    cmd.arg_count = 0;
    for (uint32_t i = 0; i < MAX_ARGS; i++) {
        cmd.args[i][0] = '\0';
    }
}

void CommandSystem::cmd_help() {
    terminal.write("\nAvailable commands:\n");
    terminal.write("  help       - Show this help message\n");
    terminal.write("  makedir    - Create a directory: makedir <name>\n");
    terminal.write("  makefile   - Create a file: makefile <name> [content...]\n");
    terminal.write("  chdir      - Change directory: chdir <path>\n");
    terminal.write("  cwd        - Print working directory\n");
    terminal.write("  clear      - Clear the screen\n");
}

void CommandSystem::cmd_makedir(const char* name) {
    if (filesystem.mkdir(name)) {
        terminal.write("Directory '");
        terminal.write(name);
        terminal.write("' created\n");
    } else {
        terminal.write("makedir: cannot create directory '");
        terminal.write(name);
        terminal.write("'\n");
    }
}

void CommandSystem::cmd_makefile(const char* name, const char* content) {
    if (!filesystem.create_file(name, "")) {
        terminal.write("makefile: cannot create file '");
        terminal.write(name);
        terminal.write("'\n");
        return;
    }
    if (content && content[0] != '\0') {
        filesystem.write_file(name, content);
    }
}

void CommandSystem::cmd_chdir(const char* path) {
    if (!filesystem.cd(path)) {
        terminal.write("chdir: ");
        terminal.write(path);
        terminal.write(": No such directory\n");
    }
}

void CommandSystem::cmd_cwd() {
    const char* current_path = filesystem.pwd();
    terminal.write("\n");
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
}
