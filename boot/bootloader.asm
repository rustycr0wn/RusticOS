[org 0x7c00]
[bits 16]

%include "boot/kernel_sectors.inc"
%include "boot/loader_sectors.inc"

%ifndef LOADER_SECTORS
%assign LOADER_SECTORS 4
%endif

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    sti

    mov si, msg_loading
    call print_string

    ; === Use INT13 Extended Read (LBA mode) ===
    ; Load loader from LBA 1 (sector 1, right after MBR)
    
    ; Set up destination segment FIRST
    mov ax, 0x1000
    mov es, ax
    
    ; Build DAP (Disk Address Packet) on stack
    mov bp, sp
    sub sp, 16                ; allocate DAP on stack
    
    mov byte [bp-16], 0x10    ; DAP size
    mov byte [bp-15], 0x00    ; reserved
    mov word [bp-14], LOADER_SECTORS  ; sector count
    mov word [bp-12], 0x0000  ; offset (ES:0000)
    mov word [bp-10], 0x1000  ; segment
    mov dword [bp-8], 1       ; LBA = 1 (loader is at sector 1)
    mov dword [bp-4], 0       ; LBA high dword
    
    ; Set up for INT13 extended read
    mov ah, 0x42              ; extended read
    mov dl, 0x80              ; drive 0
    mov si, bp
    sub si, 16                ; DS:SI points to DAP
    int 0x13
    jc .load_error

    mov si, msg_loaded
    call print_string

    mov si, msg_jumping
    call print_string

    ; Transfer control to loader (far JMP 0x1000:0x0000)
    db 0xEA
    dw 0x0000
    dw 0x1000

.load_error:
    mov si, msg_error
    call print_string
    
    mov bl, ah
    mov al, bl
    and al, 0x0F
    cmp al, 10
    jl .Ldig
    add al, 'A' - 10
    jmp .Ldone
.Ldig:
    add al, '0'
.Ldone:
    mov ah, 0x0E
    int 0x10

    mov al, bl
    shr al, 4
    and al, 0x0F
    cmp al, 10
    jl .Hdig
    add al, 'A' - 10
    jmp .Hdone
.Hdig:
    add al, '0'
.Hdone:
    mov ah, 0x0E
    int 0x10

.halt:
    cli
    hlt
    jmp .halt

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
msg_error:   db "[MBR] INT13 ERROR: ", 0

times (512 - 2 - ($-$$)) db 0
dw 0xAA55