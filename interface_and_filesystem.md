# RusticOS Command-Line Interface and Filesystem

## Overview
RusticOS now includes a fully functional command-line interface with a basic filesystem. Users can type commands at the kernel prompt and interact with a root filesystem mounted at "/".

## Features Implemented

### Command-Line Interface
- **Interactive prompt**: The kernel displays a "> " prompt where users can type commands
- **Keyboard input**: Full keyboard support with character input, backspace, and enter
- **Command execution**: Commands are parsed and executed in real-time
- **Error handling**: Invalid commands show appropriate error messages

### Filesystem
- **Root directory**: A filesystem mounted at "/" (root)
- **Directory operations**: Create and navigate directories
- **Static memory allocation**: Uses a memory pool for filesystem nodes (no dynamic allocation)
- **Hierarchical structure**: Supports parent-child directory relationships

### Available Commands

#### `help`
- **Usage**: `help`
- **Description**: Lists all available commands with brief descriptions
- **Example**: 
  ```
  > help
  Available commands:
    help     - Show this help message
    mkdir    - Create a directory
    ls       - List directory contents
    cd       - Change directory
    pwd      - Print working directory
    clear    - Clear the screen
    echo     - Print text
  ```

#### `mkdir`
- **Usage**: `mkdir <directory_name>`
- **Description**: Creates a new directory in the current location
- **Example**:
  ```
  > mkdir testdir
  Directory 'testdir' created successfully
  ```

#### `cd`
- **Usage**: `cd <path>`
- **Description**: Changes the current directory
- **Special paths**:
  - `cd /` - Go to root directory
  - `cd ..` - Go to parent directory
- **Example**:
  ```
  > cd testdir
  > cd ..
  > cd /
  ```

#### `pwd`
- **Usage**: `pwd`
- **Description**: Prints the current working directory
- **Example**:
  ```
  > pwd
  /
  ```

#### `ls`
- **Usage**: `ls`
- **Description**: Lists contents of the current directory
- **Note**: Currently shows placeholder message (implementation in progress)

#### `clear`
- **Usage**: `clear`
- **Description**: Clears the screen and redraws the header
- **Example**:
  ```
  > clear
  [Screen clears and shows fresh prompt]
  ```

#### `echo`
- **Usage**: `echo <text>`
- **Description**: Prints the specified text
- **Example**:
  ```
  > echo Hello, RusticOS!
  Hello, RusticOS!
  ```

## Technical Implementation

### Architecture
- **Kernel**: Main kernel loop with keyboard polling
- **Terminal**: VGA text-mode display with cursor management
- **Keyboard**: PS/2 keyboard input handling
- **Filesystem**: In-memory filesystem with static allocation
- **Command System**: Command parser and executor

### Memory Management
- **Static allocation**: All filesystem nodes use a pre-allocated memory pool
- **No dynamic allocation**: Avoids issues with `new`/`delete` in freestanding environment
- **Memory pool**: 256 FileNode structures for filesystem operations

### File Structure
```
src/
├── kernel.cpp      # Main kernel with command loop
├── terminal.h/cpp  # VGA terminal interface
├── keyboard.h/cpp  # Keyboard input handling
├── filesystem.h/cpp # Filesystem implementation
└── command.h/cpp   # Command parsing and execution
```

## Usage Examples

### Basic Navigation
```
> help
> mkdir projects
> cd projects
> pwd
> mkdir myproject
> cd myproject
> pwd
> cd ../..
> pwd
```

### File Operations
```
> echo "Hello World"
> clear
> help
```

## Building and Running

### Build
```bash
make clean
make all
```

### Run
```bash
# Headless mode (no display)
make run-headless

# With VNC display
make run

# With curses display
make run-curses
```

## Future Enhancements

### Planned Features
- **File operations**: Create, read, write, delete files
- **Directory listing**: Full `ls` implementation
- **Path resolution**: Support for absolute and relative paths
- **File content storage**: Persistent file data
- **More commands**: `rm`, `mv`, `cp`, `cat`, etc.

### Technical Improvements
- **Interrupt-driven keyboard**: Replace polling with proper interrupts
- **Memory management**: Dynamic allocation with heap management
- **Persistent storage**: Save filesystem to disk
- **Command history**: Up/down arrow support
- **Tab completion**: Auto-complete commands and paths

## Notes
- The filesystem is currently in-memory only and resets on reboot
- Keyboard input uses polling (not interrupt-driven)
- File content storage is not yet implemented
- The system is designed for educational purposes and demonstrates basic OS concepts
