[org 0x8000]
[bits 16]

%ifndef KERNEL_SECTORS
%ifdef KERNEL_SIZE_BYTES
%assign KERNEL_SECTORS ((KERNEL_SIZE_BYTES + 511) / 512)
%else
%error "KERNEL_SIZE_BYTES must be defined by the build system!"
%endif
%endif

%ifndef LOADER_SECTORS
%define LOADER_SECTORS 2
%endif

kernel_sectors equ KERNEL_SECTORS
SEG_BASE equ 0x1000
; Updated: MBR at LBA 0, Loader at LBA 1, so kernel starts at LBA (1 + LOADER_SECTORS)
KERNEL_LBA_START equ (1 + LOADER_SECTORS)
PART_BASE_PTR equ 0x0600

loader_start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ax, 0x9000
    mov ss, ax
    mov sp, 0xFFFE
    cld

    ; Early print to confirm loader entry
    mov ah, 0x0e
    mov al, 'L'
    int 0x10

    ; Ensure DS/ES match CS so data labels are correct regardless of load seg
    push cs
    pop ds
    push ds
    pop es

    ; Capture boot drive
    mov [boot_drive], dl

    mov si, msg_ld_start
    call bios_print

    ; Prepare DAP to load kernel to 0x20000 (buf_seg=0x2000, buf_off=0)
    mov si, dap
    mov byte [si], 0x10
    mov byte [si+1], 0x00
    mov word [si+2], kernel_sectors
    mov word [si+4], 0x0000     ; buf_off
    mov word [si+6], 0x2000     ; buf_seg
    mov dword [si+8], KERNEL_LBA_START
    mov dword [si+12], 0

    mov si, msg_ld_edd
    call bios_print

    mov dl, [boot_drive]
    mov bx, dap
    mov si, bx
    mov ah, 0x42
    int 0x13
    jnc .edd_ok

    mov [last_status], ah
    jmp disk_error

.edd_ok:
    mov si, msg_ld_done
    call bios_print

    ; Setup GDT
    lgdt [gdt_descriptor]

    ; Enable A20
    in al, 0x92
    or al, 0x02
    out 0x92, al

    ; Enter protected mode
    cli
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp dword 0x08:protected_mode_entry

[bits 32]
protected_mode_entry:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x0090000

    ; Copy kernel to 0x100000
    mov esi, 0x00020000
    mov edi, 0x100000
    mov ecx, (KERNEL_SIZE_BYTES + 3) / 4
    cld
    rep movsd

    jmp dword 0x08:0x100000

; --- Hex helpers and delay ---
hex_digits: db '0123456789ABCDEF'

; BIOS teletype print (SI=ASCIIZ)
bios_print:
    push ax
    push bx
    cld
.prn:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0e
    mov bx, 0x0007
    int 0x10
    jmp .prn
.done:
    pop bx
    pop ax
    ret

; ~100ms crude delay
delay_500ms:
    push cx
    mov cx, 100000
.dl:
    out 0x80, al
    loop .dl
    pop cx
    ret

; --- Disk error with status ---
disk_error:
    mov ax, 0xb800
    mov es, ax
    mov di, 0
    mov al, 'E'
    mov ah, 0x04
    stosw
    mov al, 'R'
    stosw
    mov al, 'R'
    stosw
    mov al, ':'
    mov ah, 0x04
    stosw

    mov al, [last_status]
    ; print two hex digits
    push ax
    mov bl, al
    shr bl, 4
    and bl, 0x0F
    mov si, hex_digits
    mov al, [si+bx]
    mov ah, 0x04
    stosw
    pop ax
    and al, 0x0F
    mov si, hex_digits
    xlat
    mov ah, 0x04
    stosw

    cli
.halt:
    hlt
    jmp .halt

; --- Data ---
boot_drive db 0
retry db 0
last_status db 0
dl_tried_alt db 0

; --- GDT ---
align 8
gdt_start:
    dq 0x0000000000000000       ; null descriptor
    dq 0x00CF9A000000FFFF       ; code descriptor
    dq 0x00CF92000000FFFF       ; data descriptor
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

; --- DAP (Disk Address Packet) ---
dap:
    db 0x10
    db 0x00
count:      dw 0
buf_off:    dw 0
buf_seg:    dw 0
lba_low:    dd 0
lba_high:   dd 0

; --- Messages ---
msg_ld_start db "[LOADER] start", 13,10,0
msg_ld_edd   db "[LOADER] EDD read", 13,10,0
msg_ld_chs   db "[LOADER] CHS read", 13,10,0
msg_ld_done  db "[LOADER] read done", 13,10,0
msg_ld_gdt   db "[LOADER] load GDT", 13,10,0
msg_ld_a20   db "[LOADER] enable A20", 13,10,0
msg_ld_pm    db "[LOADER] enter PM", 13,10,0
msg_ld_copy  db "[LOADER] copy kernel", 13,10,0

; Pad to sector boundary
%if ($-$$) < 510
    times 510-($-$$) db 0
    dw 0xaa55
%elif ($-$$) < 1022
    times 1022-($-$$) db 0
    dw 0xaa55
%else
    %error "Loader too large"
%endif