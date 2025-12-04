[org 0x0000]
[bits 16]

loader_start:
    cli
    cld

    ; Set up simple real-mode stack and segments
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7000

    ; === Print [LOADER] message via BIOS INT10 ===
    mov si, loader_msg_start
    call print_string

    ; === Ultra-early VGA markers (direct writes via ES) ===
    mov ax, 0xB800
    mov es, ax
    mov byte [es:0], 'L'
    mov byte [es:1], 0x0F
    mov byte [es:2], '1'
    mov byte [es:3], 0x0F

    ; === Load GDT descriptor: make DS point to the loader's segment (0x1000) ===
    mov ax, 0x1000
    mov ds, ax

    ; Put marker
    mov byte [es:8], '2'
    mov byte [es:9], 0x0F

    ; Load the GDTR from our gdt_descriptor
    lgdt [gdt_descriptor]

    ; mark that LGDT executed
    mov byte [es:16], '3'
    mov byte [es:17], 0x0F

    ; Print kernel loaded message
    mov ax, 0x0000
    mov ds, ax
    mov si, loader_msg_kernel_loaded
    call print_string

    ; Enable protected-mode via CR0
    mov eax, cr0
    or  eax, 1
    mov cr0, eax

    ; mark just before far-jump
    mov ax, 0xB800
    mov es, ax
    mov byte [es:20], '4'
    mov byte [es:21], 0x0F

    ; === CRITICAL FIX: Calculate correct offset for protected_mode_start ===
    ; The far-jump offset must be relative to the code segment base (0x1000:0x0000)
    ; protected_mode_start label is at a fixed offset in our binary
    ; We pass that offset directly to the far-jump
    
    ; Far jump into protected-mode code (EA offset16 selector16)
    db 0xEA
    dw (protected_mode_start - loader_start)  ; offset from start of loader
    dw 0x0008                                  ; code selector

; ============ Protected-mode (32-bit) ============
[bits 32]
protected_mode_start:
    ; Load data segment selectors for protected mode
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax

    ; initialize stack in protected mode
    mov esp, 0x90000

    ; mark in VGA (32-bit absolute video address)
    mov byte [0xB8000], 'P'
    mov byte [0xB8001], 0x07
    mov byte [0xB8002], 'M'
    mov byte [0xB8003], 0x07

    cli
    hlt

; ============ Print function (real-mode) ============
[bits 16]
print_string:
    mov ah, 0x0E
.ps_loop:
    lodsb
    test al, al
    jz .ps_done
    int 0x10
    jmp .ps_loop
.ps_done:
    ret

; ============ Messages ============
loader_msg_start: db "[LOADER] Started", 0x0D, 0x0A, 0
loader_msg_kernel_loaded: db "[LOADER] Kernel loaded", 0x0D, 0x0A, 0

; ============ GDT (place at the end of file) ============
align 8
gdt:
    dq 0x0000000000000000
    dq 0x00cf9a000000ffff
    dq 0x00cf92000000ffff

gdt_descriptor:
    dw 23
    dd 0x10000 + gdt