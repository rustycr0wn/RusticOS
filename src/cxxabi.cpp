// Minimal C++ runtime and C library stubs for freestanding -m32 build

#include "types.h"
#include <cstring>
#include <cstddef>

extern "C" {
    // Minimal C library stubs
    void* memcpy(void* dst, const void* src, uint32_t n) {
        uint8_t* d = (uint8_t*)dst;
        const uint8_t* s = (const uint8_t*)src;
        for (uint32_t i = 0; i < n; ++i) d[i] = s[i];
        return dst;
    }

    void* memset(void* p, int c, uint32_t n) {
        uint8_t* d = (uint8_t*)p;
        for (uint32_t i = 0; i < n; ++i) d[i] = (uint8_t)c;
        return p;
    }

    int strcmp(const char* a, const char* b) {
        while (*a && *a == *b) { ++a; ++b; }
        return (int)(unsigned char)*a - (int)(unsigned char)*b;
    }

    char* strncpy(char* dst, const char* src, uint32_t n) {
        uint32_t i;
        for (i = 0; i < n && src[i]; ++i) dst[i] = src[i];
        for (; i < n; ++i) dst[i] = '\0';
        return dst;
    }

    size_t strlen(const char* s) throw() {
        size_t n = 0;
        while (s[n]) ++n;
        return n;
    }

    // Minimal new/delete (simple bump allocator)
    static uint8_t heap_pool[65536];
    static uint32_t heap_pos = 0;
    void* operator new(size_t size) throw() {
        if (heap_pos + size > sizeof(heap_pool)) return nullptr;
        void* ptr = &heap_pool[heap_pos];
        heap_pos += ((size + 7) & ~7); // align
        return ptr;
    }

    void* operator new[](size_t size) throw() {
        if (heap_pos + size > sizeof(heap_pool)) return nullptr;
        void* ptr = &heap_pool[heap_pos];
        heap_pos += ((size + 7) & ~7);
        return ptr;
    }

    void operator delete(void* ptr, uint32_t) throw() { (void)ptr; }
    void operator delete[](void* ptr) throw() { (void)ptr; }

    void __cxa_pure_virtual() { for (;;) {} }

    int __cxa_atexit(void (*func)(void*), void* arg, void* dso) {
        (void)func; (void)arg; (void)dso;
        return 0;
    }

    // Provide missing symbols used by C++ runtime / linker
    // Define non-hidden __dso_handle so link resolves it
    void* __dso_handle = (void*)0x1;

    // Simple stub for stack protector failure (should halt)
    void __stack_chk_fail() {
        // In a freestanding environment, just spin/halt.
        for (;;) { asm volatile("cli; hlt"); }
    }
}