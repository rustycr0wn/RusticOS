[org 0x7c00]
[bits 16]

; Simple MBR that loads loader and jumps to it
start:
    ; Initialize segments
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00

    ; Set DS to our code segment (0x07C0) for accessing data labels
    mov ax, 0x07C0
    mov ds, ax

    ; Save boot drive
    mov [boot_drive], dl

    ; Print loading message
    mov si, msg_loading
    call bios_print

    ; Load loader from sector 2 to 0x1000:0x0000
    mov ah, 0x02             ; read
    mov al, LOADER_SECTORS   ; sectors to read (provided by Makefile)
    mov ch, 0                ; cylinder 0
    mov cl, 2                ; sector 2 (immediately after MBR)
    mov dh, 0                ; head 0
    mov dl, [boot_drive]     ; drive
    mov bx, 0x1000           ; segment
    mov es, bx
    xor bx, bx               ; offset 0
    int 0x13
    jc disk_error

    ; Print success message
    mov si, msg_success
    call bios_print

    ; Jump to loader
    jmp 0x1000:0x0000

; BIOS print function
bios_print:
    cld
.next:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0e
    int 0x10
    jmp .next
.done:
    ret

; Data
boot_drive db 0
msg_loading db 'Loading loader...', 13, 10, 0
msg_success db 'Loader loaded, jumping...', 13, 10, 0

; Error handler
disk_error:
    mov si, msg_error
    call bios_print
    call disk_reset
    cli
    hlt

disk_reset:
    xor ah, ah
    int 0x13
    ret

msg_error db 'Disk error!', 13, 10, 0

; Pad to 512 bytes
%ifndef LOADER_SECTORS
%define LOADER_SECTORS 2
%endif

times 510-($-$$) db 0
    dw 0xAA55
