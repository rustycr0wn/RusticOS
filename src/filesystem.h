#ifndef FILESYSTEM_H
#define FILESYSTEM_H

#include "types.h"

#define MAX_NAME_LENGTH 32
#define MAX_PATH_LENGTH 256
#define MAX_DIRECTORY_ENTRIES 64

#define FILE_TYPE_FILE 1
#define FILE_TYPE_DIRECTORY 0

struct FileNode {
    char name[MAX_NAME_LENGTH];
    uint8_t type;
    bool is_directory;
    uint32_t child_count;
    uint32_t size;
    char* data;
    uint32_t data_capacity;
    FileNode* children[MAX_DIRECTORY_ENTRIES];
    FileNode* parent;
};

struct DiskEntry {
    char name[MAX_NAME_LENGTH];
    uint8_t type;
    uint32_t size;
    uint32_t child_count;
    char data[1024];
};

class FileSystem {
private:
    FileNode* root;
    FileNode* current_dir;
    
    FileNode* find_child(FileNode* parent, const char* name);
    void free_node(FileNode* node);
    void print_tree(FileNode* node, int depth);
    
public:
    FileSystem();
    ~FileSystem();
    
    bool mkdir(const char* path);
    bool rmdir(const char* path);
    bool cd(const char* path);
    void ls();
    bool pwd();
    
    bool create_file(const char* name, const char* content);
    bool delete_file(const char* name);
    bool read_file(const char* name, char* buffer, uint32_t max_size);
    bool write_file(const char* name, const char* content);
    
    void save_to_disk();
    bool load_from_disk();
    
    FileNode* get_current_dir() const { return current_dir; }
};

extern FileSystem filesystem;

#endif // FILESYSTEM_H