[org 0x7c00]
[bits 16]

%include "boot/loader_sectors.inc"

jmp short start
nop

; ... BPB ...

start:
    cli
    mov ax, 0x9000
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0xFFFE
    cld

    mov [boot_drive], dl        ; <--- Ensure BIOS drive is saved

    mov si, msg_load
    call bios_print

    ; Prepare DAP for INT 13h AH=42h (EDD) to load loader from LBA 2 to 0x8000
    mov si, dap
    mov byte [si], 16         ; size
    mov byte [si+1], 0        ; reserved
    mov word [si+2], LOADER_SECTORS ; count (from loader_sectors.inc)
    mov word [si+4], 0x8000   ; buf_off
    mov word [si+6], 0x0000   ; buf_seg
    mov dword [si+8], 2       ; lba_low (LBA 2)
    mov dword [si+12], 0      ; lba_high

    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    jc disk_error

    mov si, msg_mbr_jump
    call bios_print

    jmp 0x0000:0x8000

; ... rest of file unchanged ...