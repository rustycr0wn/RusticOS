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

    ; === VGA marker: '1' at column 0 (start) ===
    mov ax, 0xB800
    mov es, ax
    mov byte [es:0], '1'
    mov byte [es:1], 0x0F

    mov si, msg_loading
    call print_string

    ; === VGA marker: '2' at column 2 (before INT13) ===
    mov ax, 0xB800
    mov es, ax
    mov byte [es:4], '2'
    mov byte [es:5], 0x0F

    ; Set up destination segment FIRST
    mov ax, 0x1000
    mov es, ax
    xor bx, bx

    ; NOW set up INT13 read parameters
    mov ah, 0x02
    mov al, LOADER_SECTORS
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, 0x80
    int 0x13
    
    ; === VGA marker: '3' at column 4 (after INT13 returned) ===
    mov ax, 0xB800
    mov es, ax
    mov byte [es:8], '3'
    mov byte [es:9], 0x0F
    
    jc .load_error

    ; === VGA marker: '4' at column 6 (INT13 success) ===
    mov ax, 0xB800
    mov es, ax
    mov byte [es:12], '4'
    mov byte [es:13], 0x0F

    mov si, msg_loaded
    call print_string

    mov si, msg_jumping
    call print_string

    ; === VGA marker: '5' at column 8 (before far transfer) ===
    mov ax, 0xB800
    mov es, ax
    mov byte [es:16], '5'
    mov byte [es:17], 0x0F

    ; Transfer control to loader
    push word 0x1000
    push word 0x0000
    retf

.load_error:
    ; === VGA marker: 'E' at column 10 (INT13 error) ===
    mov ax, 0xB800
    mov es, ax
    mov byte [es:20], 'E'
    mov byte [es:21], 0x0F
    
    mov bl, ah
    mov si, msg_error
    call print_string

    ; Print error code (BL) as hex
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

msg_loading: db "[MBR] Loading loader...", 0x0D,0x0A,0
msg_loaded:  db "[MBR] Loader loaded", 0x0D,0x0A,0
msg_jumping: db "[MBR] Jumping to loader", 0x0D,0x0A,0
msg_error:   db "[MBR] INT13 ERROR: ", 0

times (512 - 2 - ($-$$)) db 0
dw 0xAA55