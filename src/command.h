#ifndef COMMAND_H
#define COMMAND_H

#include <stdint.h>

// Maximum command length
#define MAX_COMMAND_LENGTH 256
#define MAX_ARGS 16

// Command structure
struct Command {
    char name[MAX_COMMAND_LENGTH];
    char args[MAX_ARGS][MAX_COMMAND_LENGTH];
    uint32_t arg_count;
};

// Command system class
class CommandSystem {
private:
    char input_buffer[MAX_COMMAND_LENGTH];
    uint32_t input_pos;
    bool input_complete;
    
    // Command parsing
    void parse_command(const char* input, Command& cmd);
    void clear_command(Command& cmd);
    
    // Individual command handlers
    void cmd_help();
    void cmd_makedir(const char* name);
    void cmd_makefile(const char* name, const char* content);
    void cmd_chdir(const char* path);
    void cmd_cwd();
    void cmd_clear();
    
public:
    CommandSystem();
    
    // Input handling
    void process_input(char c);
    void execute_command();
    void reset_input();
    
    // Query state
    bool is_input_complete() const { return input_complete; }
    const char* get_input_buffer() const { return input_buffer; }
    uint32_t get_input_pos() const { return input_pos; }
};

// Global command system instance
extern CommandSystem command_system;

#endif // COMMAND_H
