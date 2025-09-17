#include "filesystem.h"
#include <cstddef>
#include "terminal.h"
#include "virtual_disk.h"

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
    
    // Try loading from disk; if not present, format a fresh FS
    if (!load_from_disk()) {
    root = allocate_node();
    if (root) {
        safe_strcpy(root->name, "/", MAX_NAME_LENGTH);
        root->type = FILE_TYPE_DIRECTORY;
        root->parent = nullptr;
        root->child_count = 0;
        root->size = 0;
        root->data = nullptr;
        for (uint32_t i = 0; i < MAX_DIRECTORY_ENTRIES; i++) {
            root->children[i] = nullptr;
        }
    }
        current_directory = root;
        save_to_disk();
    } else {
    current_directory = root;
    }
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
    save_to_disk();
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
    save_to_disk();
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
    if (!current_directory) {
        terminal.write("\n");
        return;
    }
    for (uint32_t i = 0; i < current_directory->child_count; i++) {
        FileNode* child = current_directory->children[i];
        if (!child) continue;
        if (child->type == FILE_TYPE_DIRECTORY) {
            terminal.write("[DIR] ");
        } else {
            terminal.write("      ");
        }
        terminal.write(child->name);
        terminal.write("\n");
    }
}

const char* FileSystem::pwd() {
    static char path_buffer[MAX_PATH_LENGTH];
    if (!current_directory) {
        path_buffer[0] = '/';
        path_buffer[1] = '\0';
        return path_buffer;
    }
    // Collect nodes up to root
    const FileNode* stack_nodes[64];
    uint32_t depth = 0;
    const FileNode* node = current_directory;
    while (node) {
        stack_nodes[depth++] = node;
        if (node == root) break;
        node = node->parent;
        if (depth >= 64) break;
    }
    // Build path in buffer
    uint32_t pos = 0;
    path_buffer[pos++] = '/';
    // Iterate from root's child downwards (skip duplicating root slash)
    for (int i = (int)depth - 2; i >= 0; i--) {
        const char* name = stack_nodes[i]->name;
        // Append name
        uint32_t j = 0;
        while (name[j] != '\0' && pos < MAX_PATH_LENGTH - 1) {
            path_buffer[pos++] = name[j++];
        }
        if (i > 0 && pos < MAX_PATH_LENGTH - 1) {
            path_buffer[pos++] = '/';
        }
    }
    path_buffer[pos] = '\0';
    return path_buffer;
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
    save_to_disk();
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
    save_to_disk();
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

// Very simple on-disk serialization of the directory tree (names and types only)
// Layout:
//  LBA 0: signature "RSTFS1\0" (8 bytes), uint16_t entry_count, reserved
//  Subsequent LBAs: array of fixed-size entries:
//    struct Entry { char name[32]; uint8_t type; uint16_t parentIndex; } packed

struct __attribute__((packed)) FsEntryDisk {
    char name[MAX_NAME_LENGTH];
    uint8_t type; // 0=dir,1=file
    uint16_t parentIndex; // index in this flat list; 0 is root
};

void FileSystem::save_to_disk() {
    // Flatten nodes into an array using simple BFS from root
    if (!root) return;
    const uint16_t MAX_ENTRIES = 256;
    FsEntryDisk entries[256];
    FileNode* node_index[256];
    uint16_t count = 0;

    // Queue
    FileNode* queue[256];
    uint16_t qh = 0, qt = 0;
    queue[qt++] = root;
    node_index[count] = root;
    // Pre-fill root entry
    entries[count].type = (uint8_t)root->type;
    entries[count].parentIndex = 0;
    safe_strcpy(entries[count].name, root->name, MAX_NAME_LENGTH);
    count++;

    while (qh < qt && count < MAX_ENTRIES) {
        FileNode* cur = queue[qh++];
        // Find index of cur
        uint16_t curIdx = 0;
        for (uint16_t i = 0; i < count; ++i) {
            if (node_index[i] == cur) { curIdx = i; break; }
        }
        for (uint32_t i = 0; i < cur->child_count && count < MAX_ENTRIES; i++) {
            FileNode* ch = cur->children[i];
            if (!ch) continue;
            queue[qt++] = ch;
            node_index[count] = ch;
            entries[count].type = (uint8_t)ch->type;
            entries[count].parentIndex = curIdx;
            safe_strcpy(entries[count].name, ch->name, MAX_NAME_LENGTH);
            count++;
        }
    }

    // Write header sector
    uint8_t sector[VDISK_SECTOR_SIZE];
    for (uint32_t i = 0; i < VDISK_SECTOR_SIZE; ++i) sector[i] = 0;
    const char sig[8] = { 'R','S','T','F','S','1','\0','\0' };
    for (int i = 0; i < 8; ++i) sector[i] = (uint8_t)sig[i];
    sector[8] = (uint8_t)(count & 0xFF);
    sector[9] = (uint8_t)((count >> 8) & 0xFF);
    vdisk.write_sector(0, sector);

    // Write entries starting at LBA 1
    const uint32_t entries_per_sector = VDISK_SECTOR_SIZE / sizeof(FsEntryDisk);
    uint32_t written = 0;
    uint32_t lba = 1;
    while (written < count) {
        // pack sector
        for (uint32_t i = 0; i < VDISK_SECTOR_SIZE; ++i) sector[i] = 0;
        uint32_t to_write = entries_per_sector;
        if (to_write > (uint32_t)(count - written)) to_write = (uint32_t)(count - written);
        for (uint32_t i = 0; i < to_write; ++i) {
            const FsEntryDisk* src = &entries[written + i];
            const uint8_t* p = reinterpret_cast<const uint8_t*>(src);
            for (uint32_t b = 0; b < sizeof(FsEntryDisk); ++b) sector[i * sizeof(FsEntryDisk) + b] = p[b];
        }
        vdisk.write_sector(lba++, sector);
        written += to_write;
    }
}

bool FileSystem::load_from_disk() {
    // Read header and validate signature
    uint8_t sector[VDISK_SECTOR_SIZE];
    if (!vdisk.read_sector(0, sector)) return false;
    if (!(sector[0]=='R' && sector[1]=='S' && sector[2]=='T' && sector[3]=='F' && sector[4]=='S' && sector[5]=='1')) {
        return false;
    }
    uint16_t count = (uint16_t)(sector[8] | (sector[9] << 8));
    if (count == 0 || count > 256) return false;

    // Read entries
    FsEntryDisk entries[256];
    const uint32_t entries_per_sector = VDISK_SECTOR_SIZE / sizeof(FsEntryDisk);
    uint32_t read = 0;
    uint32_t lba = 1;
    while (read < count) {
        if (!vdisk.read_sector(lba++, sector)) return false;
        uint32_t to_read = entries_per_sector;
        if (to_read > (uint32_t)(count - read)) to_read = (uint32_t)(count - read);
        for (uint32_t i = 0; i < to_read; ++i) {
            uint8_t* dst = reinterpret_cast<uint8_t*>(&entries[read + i]);
            for (uint32_t b = 0; b < sizeof(FsEntryDisk); ++b) dst[b] = sector[i * sizeof(FsEntryDisk) + b];
        }
        read += to_read;
    }

    // Rebuild node tree from entries
    // Reset pool and allocate nodes
    for (uint32_t i = 0; i < MAX_NODES; i++) node_used[i] = false;
    FileNode* nodes[256];
    for (uint16_t i = 0; i < count; ++i) {
        FileNode* n = allocate_node();
        if (!n) return false;
        safe_strcpy(n->name, entries[i].name, MAX_NAME_LENGTH);
        n->type = (entries[i].type == 0) ? FILE_TYPE_DIRECTORY : FILE_TYPE_FILE;
        n->parent = nullptr;
        n->child_count = 0;
        n->size = 0;
        n->data = nullptr;
        for (uint32_t j = 0; j < MAX_DIRECTORY_ENTRIES; j++) n->children[j] = nullptr;
        nodes[i] = n;
    }
    // Set parent/children relations
    for (uint16_t i = 0; i < count; ++i) {
        uint16_t parentIdx = entries[i].parentIndex;
        if (i == 0) continue; // root
        if (parentIdx < count) {
            FileNode* p = nodes[parentIdx];
            FileNode* c = nodes[i];
            c->parent = p;
            p->children[p->child_count++] = c;
        }
    }
    root = nodes[0];
    return true;
}
