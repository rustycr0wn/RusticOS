#ifndef COMMAND_H
#define COMMAND_H

#include "types.h"

#define MAX_COMMAND_LENGTH 256
#define MAX_ARGS 16

struct Command {
    char name[64];
    char args[MAX_ARGS][64];
    uint32_t arg_count;
};

class CommandSystem {
private:
    char input_buffer[MAX_COMMAND_LENGTH];
    uint32_t input_pos;
    bool input_complete;
    Command current_command;
    
    void parse_command(const char* input, Command& cmd);
    void clear_command(Command& cmd);
    
public:
    CommandSystem();
    
    void process_input(char c);
    void execute_command();
    void reset_input();
    
    bool is_input_complete() const { return input_complete; }
    const char* get_input_buffer() const { return input_buffer; }
    uint32_t get_input_pos() const { return input_pos; }
    
    // Command implementations
    void cmd_help();
    void cmd_clear();
    void cmd_echo();
    void cmd_mkdir(const char* name);
    void cmd_cd(const char* path);
    void cmd_ls();
    void cmd_pwd();
    void cmd_touch(const char* name);
    void cmd_cat(const char* name);
    void cmd_write(const char* name, const char* content);
};

extern CommandSystem command_system;

#endif // COMMAND_H
