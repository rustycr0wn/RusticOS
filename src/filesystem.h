#ifndef FILESYSTEM_H
#define FILESYSTEM_H

#include <stdint.h>

// Maximum length for file/directory names
#define MAX_NAME_LENGTH 32
#define MAX_PATH_LENGTH 256
#define MAX_DIRECTORY_ENTRIES 64

// File types
enum FileType {
    FILE_TYPE_DIRECTORY = 0,
    FILE_TYPE_FILE = 1
};

// File system node structure
struct FileNode {
    char name[MAX_NAME_LENGTH];
    FileType type;
    FileNode* parent;
    FileNode* children[MAX_DIRECTORY_ENTRIES];
    uint32_t child_count;
    uint32_t size;
    char* data; // For files, this contains the file data
    uint32_t data_capacity; // capacity in bytes of data buffer
};

// File system class
class FileSystem {
private:
    FileNode* root;
    FileNode* current_directory;
    
    // Persistence helpers
    void save_to_disk();
    bool load_from_disk();

    // Helper functions
    FileNode* find_child(FileNode* parent, const char* name);
    void free_node(FileNode* node);
    
public:
    FileSystem();
    ~FileSystem();
    
    // Directory operations
    bool mkdir(const char* name);
    bool rmdir(const char* name);
    bool cd(const char* path);
    void ls();
    const char* pwd();
    
    // File operations
    bool create_file(const char* name, const char* content = nullptr);
    bool delete_file(const char* name);
    bool read_file(const char* name, char* buffer, uint32_t max_size);
    bool write_file(const char* name, const char* content);
    
    // Utility functions
    FileNode* get_current_directory() { return current_directory; }
    FileNode* get_root() { return root; }
    void print_tree(FileNode* node = nullptr, int depth = 0);
};

// Global filesystem instance
extern FileSystem filesystem;

#endif // FILESYSTEM_H
