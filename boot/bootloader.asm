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

    ; Write 'B' to VGA text buffer at 0xB8000
    mov ax, 0xB800
    mov es, ax
    mov byte [es:0x00], 'B'
    mov byte [es:0x01], 0x0A

    mov si, msg_loading
    call print_string

    ; === Load loader from sector 2 using CHS ===
    mov ax, 0x0100
    mov es, ax
    xor bx, bx

    mov al, 1               ; read 1 sector
    mov ch, 0               ; cylinder 0
    mov cl, 2               ; sector 2 (1-indexed, loader is here)
    mov dh, 0               ; head 0
    mov dl, 0x80            ; drive 0 (hard drive)
    mov ah, 0x02            ; INT 13h AH=0x02: read sectors
    int 0x13
    jc .load_error

    ; Write 'R' to VGA text buffer
    mov ax, 0xB800
    mov es, ax
    mov byte [es:0x02], 'R'
    mov byte [es:0x03], 0x0A

    mov si, msg_jumping
    call print_string
    
    mov si, msg_before_jump
    call print_string

    ; Reset DS to be safe
    xor ax, ax
    mov ds, ax

    ; === Jump to loader using far jump ===
    ; Write 'J' to VGA text buffer
    mov ax, 0xB800
    mov es, ax
    mov byte [es:0x04], 'J'
    mov byte [es:0x05], 0x0A
    
    ; Push return address and jump via retf
    ; Push segment first (LIFO), then offset
    push 0x0100     ; segment
    push 0x0000     ; offset
    retf            ; far return = far jump
    
    ; Should never reach here
    mov si, msg_after_jump
    call print_string
    cli
    hlt

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

msg_loading:        db "[BOOT] Loading kernel loader...", 0x0D, 0x0A, 0
msg_jumping:        db "[BOOT] Jumping to loader", 0x0D, 0x0A, 0
msg_before_jump:    db "[BOOT] Preparing to jump to loader...", 0x0D, 0x0A, 0
msg_after_jump:     db "[BOOT] Error: Should not reach here", 0x0D, 0x0A, 0
msg_error:          db "[BOOT] Disk read error (INT 13h failed)", 0x0D, 0x0A, 0

times (512 - 2 - ($-$$)) db 0
dw 0xAA55