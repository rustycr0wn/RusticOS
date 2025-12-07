[org 0x7c00]
[bits 16]

%include "boot/kernel_sectors.inc"
%include "boot/loader_sectors.inc"

%ifndef LOADER_SECTORS
%assign LOADER_SECTORS 1
%endif

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7000
    sti

    mov si, msg_loading
    call print_string

    ; === Load loader from sector 1 ===
    mov ax, 0x1000
    mov es, ax
    xor bx, bx
    
    ; CHS: Cylinder 0, Head 0, Sector 2 (1-indexed)
    mov al, 1               ; read 1 sector
    mov ch, 0               ; cylinder 0
    mov cl, 2               ; sector 2
    mov dh, 0               ; head 0
    mov dl, 0x80            ; drive 0
    mov ah, 0x02            ; read
    int 0x13
    
    jc .load_error

    mov si, msg_loaded
    call print_string

    mov si, msg_jumping
    call print_string

    ; === Jump to loader ===
    push word 0x1000
    push word 0x0000
    retf

.load_error:
    mov si, msg_error
    call print_string
    cli
    hlt

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

msg_loading: db "[MBR] Loading loader...", 0x0D, 0x0A, 0
msg_loaded:  db "[MBR] Loader loaded", 0x0D, 0x0A, 0
msg_jumping: db "[MBR] Jumping to loader", 0x0D, 0x0A, 0
msg_error:   db "[MBR] INT13 ERROR", 0x0D, 0x0A, 0

times (512 - 2 - ($-$$)) db 0
dw 0xAA55