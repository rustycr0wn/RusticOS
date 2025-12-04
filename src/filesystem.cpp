#include "filesystem.h"
#include "terminal.h"
#include <cstring>

extern Terminal terminal;

FileSystem::FileSystem() : root(nullptr), current_dir(nullptr) {
    root = new FileNode();
    root->name[0] = '\0';
    root->type = FILE_TYPE_DIRECTORY;
    root->is_directory = true;
    root->child_count = 0;
    root->size = 0;
    root->data = nullptr;
    root->parent = nullptr;
    current_dir = root;
}

FileSystem::~FileSystem() {
    if (root) {
        free_node(root);
    }
}

void FileSystem::free_node(FileNode* node) {
    if (!node) return;
    for (uint32_t i = 0; i < node->child_count; ++i) {
        free_node(node->children[i]);
    }
    if (node->data) {
        delete[] node->data;
    }
    delete node;
}

FileNode* FileSystem::find_child(FileNode* parent, const char* name) {
    if (!parent || !name) return nullptr;
    for (uint32_t i = 0; i < parent->child_count; ++i) {
        if (strcmp(parent->children[i]->name, name) == 0) {
            return parent->children[i];
        }
    }
    return nullptr;
}

bool FileSystem::mkdir(const char* name) {
    if (!name || !current_dir || current_dir->child_count >= MAX_DIRECTORY_ENTRIES) {
        return false;
    }
    
    if (find_child(current_dir, name)) {
        return false; // Already exists
    }
    
    FileNode* new_dir = new FileNode();
    strncpy(new_dir->name, name, MAX_NAME_LENGTH - 1);
    new_dir->name[MAX_NAME_LENGTH - 1] = '\0';
    new_dir->type = FILE_TYPE_DIRECTORY;
    new_dir->is_directory = true;
    new_dir->child_count = 0;
    new_dir->size = 0;
    new_dir->data = nullptr;
    new_dir->parent = current_dir;
    
    current_dir->children[current_dir->child_count++] = new_dir;
    return true;
}

bool FileSystem::rmdir(const char* name) {
    if (!name || !current_dir) return false;
    
    FileNode* dir = find_child(current_dir, name);
    if (!dir || dir->type != FILE_TYPE_DIRECTORY || dir->child_count > 0) {
        return false;
    }
    
    // Find and remove from parent
    for (uint32_t i = 0; i < current_dir->child_count; ++i) {
        if (current_dir->children[i] == dir) {
            for (uint32_t j = i; j < current_dir->child_count - 1; ++j) {
                current_dir->children[j] = current_dir->children[j + 1];
            }
            current_dir->child_count--;
            break;
        }
    }
    
    free_node(dir);
    return true;
}

bool FileSystem::cd(const char* path) {
    if (!path || !current_dir) return false;
    
    if (strcmp(path, "/") == 0) {
        current_dir = root;
        return true;
    } else if (strcmp(path, "..") == 0) {
        if (current_dir->parent) {
            current_dir = current_dir->parent;
        }
        return true;
    }
    
    FileNode* target = find_child(current_dir, path);
    if (target && target->type == FILE_TYPE_DIRECTORY) {
        current_dir = target;
        return true;
    }
    return false;
}

void FileSystem::ls() {
    if (!current_dir) {
        terminal.write("Error: no current directory\n");
        return;
    }
    
    for (uint32_t i = 0; i < current_dir->child_count; i++) {
        FileNode* child = current_dir->children[i];
        terminal.write(child->name);
        if (child->type == FILE_TYPE_DIRECTORY) {
            terminal.write("/");
        }
        terminal.write("\n");
    }
}

bool FileSystem::pwd() {
    if (!current_dir) return false;
    terminal.write("/\n");
    return true;
}

bool FileSystem::create_file(const char* name, const char* content) {
    if (!name || !current_dir || current_dir->child_count >= MAX_DIRECTORY_ENTRIES) {
        return false;
    }
    
    if (find_child(current_dir, name)) {
        return false;
    }
    
    FileNode* new_file = new FileNode();
    strncpy(new_file->name, name, MAX_NAME_LENGTH - 1);
    new_file->name[MAX_NAME_LENGTH - 1] = '\0';
    new_file->type = FILE_TYPE_FILE;
    new_file->is_directory = false;
    new_file->child_count = 0;
    new_file->parent = current_dir;
    
    uint32_t content_len = content ? strlen(content) : 0;
    new_file->data_capacity = (content_len > 0) ? content_len + 1 : 64;
    new_file->data = new char[new_file->data_capacity];
    new_file->size = content_len;
    
    if (content && content_len > 0) {
        strncpy(new_file->data, content, new_file->data_capacity - 1);
        new_file->data[new_file->data_capacity - 1] = '\0';
    } else {
        new_file->data[0] = '\0';
    }
    
    current_dir->children[current_dir->child_count++] = new_file;
    return true;
}

bool FileSystem::delete_file(const char* name) {
    if (!name || !current_dir) return false;
    
    FileNode* file = find_child(current_dir, name);
    if (!file || file->type != FILE_TYPE_FILE) {
        return false;
    }
    
    for (uint32_t i = 0; i < current_dir->child_count; ++i) {
        if (current_dir->children[i] == file) {
            for (uint32_t j = i; j < current_dir->child_count - 1; ++j) {
                current_dir->children[j] = current_dir->children[j + 1];
            }
            current_dir->child_count--;
            break;
        }
    }
    
    free_node(file);
    return true;
}

bool FileSystem::read_file(const char* name, char* buffer, uint32_t max_size) {
    if (!name || !buffer || !current_dir) return false;
    
    FileNode* file = find_child(current_dir, name);
    if (!file || file->type != FILE_TYPE_FILE || !file->data) {
        return false;
    }
    
    uint32_t copy_len = (file->size < max_size) ? file->size : max_size - 1;
    strncpy(buffer, file->data, copy_len);
    buffer[copy_len] = '\0';
    return true;
}

bool FileSystem::write_file(const char* name, const char* content) {
    if (!name || !content || !current_dir) return false;
    
    FileNode* file = find_child(current_dir, name);
    if (!file || file->type != FILE_TYPE_FILE) {
        return false;
    }
    
    uint32_t content_len = strlen(content);
    if (content_len > file->data_capacity) {
        delete[] file->data;
        file->data_capacity = content_len + 1;
        file->data = new char[file->data_capacity];
    }
    
    strncpy(file->data, content, file->data_capacity - 1);
    file->data[file->data_capacity - 1] = '\0';
    file->size = content_len;
    return true;
}

void FileSystem::save_to_disk() {
    // Stub: save filesystem to disk
}

bool FileSystem::load_from_disk() {
    // Stub: load filesystem from disk
    return true;
}

void FileSystem::print_tree(FileNode* node, int depth) {
    if (!node) return;
    for (int i = 0; i < depth; ++i) terminal.write("  ");
    terminal.write(node->name);
    if (node->type == FILE_TYPE_DIRECTORY) terminal.write("/");
    terminal.write("\n");
    for (uint32_t i = 0; i < node->child_count; ++i) {
        print_tree(node->children[i], depth + 1);
    }
}

FileSystem filesystem;
