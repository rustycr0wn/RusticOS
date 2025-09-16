#include "filesystem.h"
#include <cstddef>

// Global filesystem instance
FileSystem filesystem;

// Static memory pool for filesystem nodes
#define MAX_NODES 256
static FileNode node_pool[MAX_NODES];
static bool node_used[MAX_NODES];
static uint32_t next_node = 0;

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

// Simple memory allocator for filesystem nodes
FileNode* allocate_node() {
    for (uint32_t i = 0; i < MAX_NODES; i++) {
        if (!node_used[i]) {
            node_used[i] = true;
            return &node_pool[i];
        }
    }
    return nullptr; // Out of memory
}

void deallocate_node(FileNode* node) {
    if (!node) return;
    
    // Find the node in the pool
    for (uint32_t i = 0; i < MAX_NODES; i++) {
        if (&node_pool[i] == node) {
            node_used[i] = false;
            break;
        }
    }
}

FileSystem::FileSystem() {
    // Initialize node pool
    for (uint32_t i = 0; i < MAX_NODES; i++) {
        node_used[i] = false;
    }
    
    // Create root directory
    root = allocate_node();
    if (root) {
        safe_strcpy(root->name, "/", MAX_NAME_LENGTH);
        root->type = FILE_TYPE_DIRECTORY;
        root->parent = nullptr;
        root->child_count = 0;
        root->size = 0;
        root->data = nullptr;
        
        // Initialize children array
        for (uint32_t i = 0; i < MAX_DIRECTORY_ENTRIES; i++) {
            root->children[i] = nullptr;
        }
    }
    
    current_directory = root;
}

FileSystem::~FileSystem() {
    // In a real OS, we'd clean up here
    // For now, just leave everything as is
}

void FileSystem::free_node(FileNode* node) {
    if (!node) return;
    
    // Free all children first
    for (uint32_t i = 0; i < node->child_count; i++) {
        free_node(node->children[i]);
    }
    
    // Deallocate the node
    deallocate_node(node);
}

FileNode* FileSystem::find_child(FileNode* parent, const char* name) {
    if (!parent || !name) return nullptr;
    
    for (uint32_t i = 0; i < parent->child_count; i++) {
        if (safe_strcmp(parent->children[i]->name, name)) {
            return parent->children[i];
        }
    }
    return nullptr;
}

bool FileSystem::mkdir(const char* name) {
    if (!name || !current_directory || current_directory->child_count >= MAX_DIRECTORY_ENTRIES) {
        return false;
    }
    
    // Check if directory already exists
    if (find_child(current_directory, name)) {
        return false;
    }
    
    // Create new directory
    FileNode* new_dir = allocate_node();
    if (!new_dir) return false;
    
    safe_strcpy(new_dir->name, name, MAX_NAME_LENGTH);
    new_dir->type = FILE_TYPE_DIRECTORY;
    new_dir->parent = current_directory;
    new_dir->child_count = 0;
    new_dir->size = 0;
    new_dir->data = nullptr;
    
    // Initialize children array
    for (uint32_t i = 0; i < MAX_DIRECTORY_ENTRIES; i++) {
        new_dir->children[i] = nullptr;
    }
    
    // Add to parent's children
    current_directory->children[current_directory->child_count] = new_dir;
    current_directory->child_count++;
    
    return true;
}

bool FileSystem::rmdir(const char* name) {
    if (!name || !current_directory) return false;
    
    FileNode* dir = find_child(current_directory, name);
    if (!dir || dir->type != FILE_TYPE_DIRECTORY || dir->child_count > 0) {
        return false;
    }
    
    // Remove from parent's children
    for (uint32_t i = 0; i < current_directory->child_count; i++) {
        if (current_directory->children[i] == dir) {
            // Shift remaining children
            for (uint32_t j = i; j < current_directory->child_count - 1; j++) {
                current_directory->children[j] = current_directory->children[j + 1];
            }
            current_directory->child_count--;
            break;
        }
    }
    
    // Free the directory
    free_node(dir);
    return true;
}

bool FileSystem::cd(const char* path) {
    if (!path || !current_directory) return false;
    
    if (safe_strcmp(path, "/")) {
        current_directory = root;
        return true;
    }
    
    if (safe_strcmp(path, "..")) {
        if (current_directory->parent) {
            current_directory = current_directory->parent;
            return true;
        }
        return false;
    }
    
    FileNode* target = find_child(current_directory, path);
    if (target && target->type == FILE_TYPE_DIRECTORY) {
        current_directory = target;
        return true;
    }
    
    return false;
}

void FileSystem::ls() {
    // This will be implemented to work with the terminal
    // For now, just a placeholder
}

const char* FileSystem::pwd() {
    // This will be implemented to return current path
    // For now, just return current directory name
    return current_directory ? current_directory->name : "/";
}

bool FileSystem::create_file(const char* name, const char* content) {
    if (!name || !current_directory || current_directory->child_count >= MAX_DIRECTORY_ENTRIES) {
        return false;
    }
    
    // Check if file already exists
    if (find_child(current_directory, name)) {
        return false;
    }
    
    // Create new file
    FileNode* new_file = allocate_node();
    if (!new_file) return false;
    
    safe_strcpy(new_file->name, name, MAX_NAME_LENGTH);
    new_file->type = FILE_TYPE_FILE;
    new_file->parent = current_directory;
    new_file->child_count = 0;
    new_file->size = 0;
    new_file->data = nullptr;
    
    // For now, we'll skip file content storage to keep it simple
    // In a real implementation, you'd need a separate memory pool for file data
    
    // Add to parent's children
    current_directory->children[current_directory->child_count] = new_file;
    current_directory->child_count++;
    
    return true;
}

bool FileSystem::delete_file(const char* name) {
    if (!name || !current_directory) return false;
    
    FileNode* file = find_child(current_directory, name);
    if (!file || file->type != FILE_TYPE_FILE) {
        return false;
    }
    
    // Remove from parent's children
    for (uint32_t i = 0; i < current_directory->child_count; i++) {
        if (current_directory->children[i] == file) {
            // Shift remaining children
            for (uint32_t j = i; j < current_directory->child_count - 1; j++) {
                current_directory->children[j] = current_directory->children[j + 1];
            }
            current_directory->child_count--;
            break;
        }
    }
    
    // Free the file
    free_node(file);
    return true;
}

bool FileSystem::read_file(const char* name, char* buffer, uint32_t max_size) {
    if (!name || !buffer || !current_directory) return false;
    
    FileNode* file = find_child(current_directory, name);
    if (!file || file->type != FILE_TYPE_FILE || !file->data) {
        return false;
    }
    
    uint32_t copy_size = (file->size < max_size - 1) ? file->size : max_size - 1;
    safe_strcpy(buffer, file->data, copy_size + 1);
    return true;
}

bool FileSystem::write_file(const char* name, const char* content) {
    if (!name || !content || !current_directory) return false;
    
    FileNode* file = find_child(current_directory, name);
    if (!file || file->type != FILE_TYPE_FILE) {
        return false;
    }
    
    // For now, we'll skip file content storage to keep it simple
    // In a real implementation, you'd need a separate memory pool for file data
    uint32_t content_len = safe_strlen(content);
    file->size = content_len;
    
    return true;
}

void FileSystem::print_tree(FileNode* node, int depth) {
    if (!node) node = root;
    
    // This will be implemented to work with the terminal
    // For now, just a placeholder
}
