[org 0x0000]
[bits 16]

; ensure CPU starts at loader_start when MBR does a far jmp 0x1000:0x0000
jmp loader_start

%include "boot/kernel_sectors.inc"
%ifndef KERNEL_LBA_START
%assign KERNEL_LBA_START 2
%endif

; ---------------- print_string ----------------
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

; ---------------- loader entry ----------------
loader_start:
    ; ULTRA-EARLY debug: write 'L' directly at VGA before any other code
    ; This confirms CPU is executing loader code
    pushf
    push ax
    push es
    mov ax, 0xB800
    mov es, ax
    mov byte [es:0], 'L'
    mov byte [es:1], 0x0F      ; bright white
    pop es
    pop ax
    popf
    
    cli
    ; set segment registers (loader loaded at 0x1000:0x0000 by MBR)
    mov ax, 0x1000
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0xFFFF

    ; print started
    mov si, loader_msg_start
    call print_string

    ; ---------------- load kernel (CHS) ----------------
    ; Do NOT overwrite DL - BIOS supplied drive in DL
    mov ah, 0x02              ; INT13 CHS read
    mov al, KERNEL_SECTORS    ; sectors to read
    mov ch, 0                 ; cylinder 0
    mov cl, 2                 ; sector 2 (kernel starts at sector 2)
    mov dh, 0                 ; head 0
    ; load to ES:BX = 0x9000:0x0000 (physical 0x00090000)
    mov ax, 0x9000
    mov es, ax
    xor bx, bx
    int 0x13
    jc dump_int13_err

    ; print loaded
    mov si, loader_msg_loaded
    call print_string

    ; prepare for protected mode
    cli
    mov si, loader_msg_pm
    call print_string

    ; mask PICs
    mov al, 0xFF
    out 0x21, al
    out 0xA1, al

    ; ensure DS points to loader segment (for gdtr/jmp_ptr)
    mov ax, 0x1000
    mov ds, ax

    ; load GDT (gdtr base is physical 0x10000 + gdt)
    lgdt [gdt_descriptor]

    ; enable protected mode
    mov eax, cr0
    or  eax, 1
    mov cr0, eax

    ; far jmp via memory pointer to reload CS
    jmp far [jmp_ptr]

dump_int13_err:
    ; AH has BIOS status - display hex and halt
    push ax
    mov bl, ah

    ; low nibble -> AL
    mov al, bl
    and al, 0x0F
    cmp al, 10
    jl L_low_digit
    add al, 'A' - 10
    jmp L_low_done
L_low_digit:
    add al, '0'
L_low_done:

    ; high nibble -> BH
    mov bh, bl
    shr bh, 4
    and bh, 0x0F
    cmp bh, 10
    jl L_high_digit
    add bh, 'A' - 10
    jmp L_high_done
L_high_digit:
    add bh, '0'
L_high_done:

    ; write two chars to VGA text buffer (B800:0)
    push es
    mov ax, 0xB800
    mov es, ax
    xor di, di
    mov [es:di], al
    mov byte [es:di+1], 0x07
    mov [es:di+2], bh
    mov byte [es:di+3], 0x07
    pop es

    pop ax
.halt_loop:
    cli
    hlt
    jmp .halt_loop

; ---------------- Data ----------------
align 8
gdt:
    dq 0x0000000000000000
    dq 0x00cf9a000000ffff
    dq 0x00cf92000000ffff

gdt_descriptor:
    dw (3*8 - 1)
    dd 0x10000 + gdt

jmp_ptr:
    dd 0x10000 + protected_mode_start
    dw 0x08

loader_msg_start:  db "[LOADER] Started",0x0D,0x0A,0
loader_msg_loaded: db "[LOADER] Kernel loaded",0x0D,0x0A,0
loader_msg_pm:     db "[LOADER] Entering protected mode",0x0D,0x0A,0
loader_msg_error:  db "[LOADER] KERNEL LOAD ERROR",0x0D,0x0A,0

[bits 32]
protected_mode_start:
    ; reload selectors
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; set protected-mode stack
    mov esp, 0x00088000

    ; debug marker: 'P' at top-left
    mov edi, 0x000B8000
    mov byte [edi], 'P'
    mov byte [edi+1], 0x07

    ; jump to kernel (flat binary must be at 0x00090000)
    jmp 0x00090000