#include "command.h"
#include "terminal.h"
#include "filesystem.h"
#include <cstring>

extern Terminal terminal;
extern FileSystem filesystem;

CommandSystem::CommandSystem()
    : input_pos(0), input_complete(false)
{
    for (int i = 0; i < MAX_COMMAND_LENGTH; ++i) {
        input_buffer[i] = '\0';
    }
    clear_command(current_command);
}

void CommandSystem::process_input(char c)
{
    if (c == '\b' || c == 0x08) {
        if (input_pos > 0) {
            input_pos--;
            input_buffer[input_pos] = '\0';
            terminal.write("\b \b");
        }
        return;
    }
    
    if (c == '\n' || c == '\r') {
        input_complete = true;
        terminal.write("\n");
        return;
    }
    
    if (c >= 32 && c <= 126 && input_pos < MAX_COMMAND_LENGTH - 1) {
        input_buffer[input_pos++] = c;
        input_buffer[input_pos] = '\0';
        char str[2] = {c, '\0'};
        terminal.write(str);
    }
}

void CommandSystem::execute_command()
{
    parse_command(input_buffer, current_command);
    
    if (current_command.name[0] == '\0') {
        return;
    }
    
    // Command dispatch
    if (strcmp(current_command.name, "help") == 0) {
        cmd_help();
    } else if (strcmp(current_command.name, "clear") == 0) {
        cmd_clear();
    } else if (strcmp(current_command.name, "echo") == 0) {
        cmd_echo();
    } else if (strcmp(current_command.name, "mkdir") == 0) {
        if (current_command.arg_count >= 1) {
            cmd_mkdir(current_command.args[0]);
        }
    } else if (strcmp(current_command.name, "cd") == 0) {
        if (current_command.arg_count >= 1) {
            cmd_cd(current_command.args[0]);
        }
    } else if (strcmp(current_command.name, "ls") == 0) {
        cmd_ls();
    } else if (strcmp(current_command.name, "pwd") == 0) {
        cmd_pwd();
    } else if (strcmp(current_command.name, "touch") == 0) {
        if (current_command.arg_count >= 1) {
            cmd_touch(current_command.args[0]);
        }
    } else if (strcmp(current_command.name, "cat") == 0) {
        if (current_command.arg_count >= 1) {
            cmd_cat(current_command.args[0]);
        }
    } else if (strcmp(current_command.name, "write") == 0) {
        if (current_command.arg_count >= 2) {
            char content[256] = {0};
            uint32_t pos = 0;
            for (uint32_t ai = 1; ai < current_command.arg_count && pos < 255; ++ai) {
                const char* part = current_command.args[ai];
                for (uint32_t pi = 0; part[pi] && pos < 255; ++pi) {
                    content[pos++] = part[pi];
                }
                if (ai + 1 < current_command.arg_count && pos < 255) {
                    content[pos++] = ' ';
                }
            }
            content[pos] = '\0';
            cmd_write(current_command.args[0], content);
        }
    } else {
        terminal.write("Unknown command: ");
        terminal.write(current_command.name);
        terminal.write("\n");
    }
}

void CommandSystem::reset_input()
{
    input_pos = 0;
    input_complete = false;
    for (int i = 0; i < MAX_COMMAND_LENGTH; ++i) {
        input_buffer[i] = '\0';
    }
    clear_command(current_command);
}

void CommandSystem::parse_command(const char* input, Command& cmd)
{
    clear_command(cmd);
    
    uint32_t i = 0;
    uint32_t arg_index = 0;
    
    // Parse command name
    uint32_t np = 0;
    while (input[i] && input[i] != ' ' && np < 63) {
        cmd.name[np++] = input[i++];
    }
    cmd.name[np] = '\0';
    
    // Skip spaces
    while (input[i] == ' ') i++;
    
    // Parse arguments
    while (input[i] && arg_index < MAX_ARGS) {
        uint32_t ap = 0;
        while (input[i] && input[i] != ' ' && ap < 63) {
            cmd.args[arg_index][ap++] = input[i++];
        }
        cmd.args[arg_index][ap] = '\0';
        
        if (ap > 0) {
            arg_index++;
        }
        
        while (input[i] == ' ') i++;
    }
    
    cmd.arg_count = arg_index;
}

void CommandSystem::clear_command(Command& cmd)
{
    cmd.name[0] = '\0';
    cmd.arg_count = 0;
    for (int i = 0; i < MAX_ARGS; ++i) {
        cmd.args[i][0] = '\0';
    }
}

// Stub implementations
void CommandSystem::cmd_help() {
    terminal.write("Available commands: help, clear, echo, mkdir, cd, ls, pwd, touch, cat, write\n");
}

void CommandSystem::cmd_clear() {
    terminal.clear();
}

void CommandSystem::cmd_echo() {
    if (current_command.arg_count > 0) {
        for (uint32_t i = 0; i < current_command.arg_count; ++i) {
            terminal.write(current_command.args[i]);
            if (i + 1 < current_command.arg_count) terminal.write(" ");
        }
    }
    terminal.write("\n");
}

void CommandSystem::cmd_mkdir(const char* name) {
    filesystem.mkdir(name);
}

void CommandSystem::cmd_cd(const char* path) {
    filesystem.cd(path);
}

void CommandSystem::cmd_ls() {
    filesystem.ls();
}

void CommandSystem::cmd_pwd() {
    filesystem.pwd();
}

void CommandSystem::cmd_touch(const char* name) {
    filesystem.create_file(name, "");
}

void CommandSystem::cmd_cat(const char* name) {
    char buffer[512] = {0};
    if (filesystem.read_file(name, buffer, 511)) {
        terminal.write(buffer);
        terminal.write("\n");
    }
}

void CommandSystem::cmd_write(const char* name, const char* content) {
    filesystem.write_file(name, content);
}

CommandSystem command_system;
