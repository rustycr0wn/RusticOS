[org 0x7c00]
[bits 16]

%include "boot/loader_sectors.inc"

start:
    cli
    ; Set up segments and stack
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    cld

    ; Save boot drive
    mov [boot_drive], dl

    mov si, msg_load
    call bios_print

    ; Prepare DAP for INT 13h AH=42h (EDD) to load loader from LBA 1 to 0x8000
    ; Note: LBA 1 instead of 2 since we're now the MBR (no separate MBR taking LBA 0)
    mov si, dap
    mov byte [si], 16
    mov byte [si+1], 0
    mov word [si+2], LOADER_SECTORS
    mov word [si+4], 0x0000
    mov word [si+6], 0x0800
    mov dword [si+8], 1        ; LBA 1 (was 2 in VBR)
    mov dword [si+12], 0

    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    jc disk_error

    mov si, msg_jump
    call bios_print

    ; Far jump to loader at 0x0800:0x0000
    cli
    mov dl, [boot_drive]
    jmp 0x0800:0x0000

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

disk_error:
    mov si, msg_err
    call bios_print
    cli
.hang:
    hlt
    jmp .hang

msg_load db "[MBR] loading loader...", 13, 10, 0
msg_jump db "[MBR] jumping to loader", 13, 10, 0
msg_err  db "[MBR] disk read error", 13, 10, 0
boot_drive db 0

align 16
dap:
    db 16
    db 0
    dw 0
    dw 0
    dw 0
    dd 0
    dd 0

; Fill to 510 bytes and add boot signature
times 510-($-$$) db 0
dw 0xAA55