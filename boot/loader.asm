[org 0x0000]
[bits 16]

%ifndef KERNEL_SECTORS
%ifdef KERNEL_SIZE_BYTES
    %assign KERNEL_SECTORS ((KERNEL_SIZE_BYTES + 511) / 512)
%else
    %error "KERNEL_SIZE_BYTES must be defined by the build system!"
%endif
%endif

%ifndef LOADER_SECTORS
    %define LOADER_SECTORS 1
%endif

kernel_sectors      equ KERNEL_SECTORS
SEG_BASE            equ 0x1000
KERNEL_LBA_START    equ (1 + LOADER_SECTORS)

; Code starts immediately
loader_start:
    cli
    push cs
    pop ds
    mov ax, 0x9000
    mov ss, ax 
    mov sp, 0xFFFE
    cld
    mov [boot_drive], dl
    mov byte [dl_tried_alt], 0

    ; Stage: loader start
    mov si, msg_ld_start
    call bios_print
    call delay_500ms

    ; Read kernel from disk using INT 13h Extensions (EDD, AH=0x42) one sector at a time
    mov si, msg_ld_edd
    call bios_print
    call delay_500ms

    mov word [count], 1
    mov word [buf_off], 0x0000
    mov word [buf_seg], 0x2000
    mov dword [lba_low], KERNEL_LBA_START
    mov dword [lba_high], 0
    mov cx, kernel_sectors
.read_lba_loop:
    cmp cx, 0
    je .read_done
    ; Setup DAP fields before each read
    mov ax, [count]
    mov [dap+2], ax
    mov ax, [buf_off]
    mov [dap+4], ax
    mov ax, [buf_seg]
    mov [dap+6], ax
    mov eax, [lba_low]
    mov [dap+8], eax
    mov eax, [lba_high]
    mov [dap+12], eax
    mov si, dap                    ; DS:SI -> DAP
    mov byte [retry], 3
.try_read:
    mov dl, [boot_drive]
    mov ah, 0x42                   ; EDD extended read
    int 0x13
    jnc .ok
    mov [last_status], ah          ; capture status
    ; toggle DL to 0x80 once if not tried
    cmp byte [dl_tried_alt], 0
    jne .after_toggle
    mov dl, 0x80
    mov [boot_drive], dl
    mov byte [dl_tried_alt], 1
.after_toggle:
    ; reset and retry
    xor ah, ah
    int 0x13
    dec byte [retry]
    jnz .try_read
    jmp .chs_fallback              ; if EDD fails entirely, use CHS
.ok:
    ; advance buffer and LBA
    mov ax, [buf_seg]
    add ax, 0x20                   ; 512 bytes = 32 paragraphs
    mov [buf_seg], ax
    add dword [lba_low], 1
    adc dword [lba_high], 0
    dec cx
    jmp .read_lba_loop

.chs_fallback:
    mov si, msg_ld_chs
    call bios_print
    call delay_500ms

    ; CHS fallback: C=0,H=0,S starts at 3 (MBR=1, loader=2), read cx sectors
    mov ax, [buf_seg]
    mov es, ax
    xor bx, bx
    mov byte [retry], 3
    mov dl, [boot_drive]
    xor ch, ch
    xor dh, dh
    mov si, cx                    ; remaining sectors
    mov cl, 3                     ; start at sector 3
.chs_loop:
    cmp si, 0
    je .chs_done
.chs_try:
    mov ah, 0x02
    mov al, 1
    mov dl, [boot_drive]
    int 0x13
    jnc .chs_ok
    mov [last_status], ah
    xor ah, ah
    int 0x13
    dec byte [retry]
    jnz .chs_try
    jmp disk_error
.chs_ok:
    add bx, 512
    inc cl
    dec si
    jmp .chs_loop
.chs_done:
    mov ax, es
    mov [buf_seg], ax
    xor cx, cx

.read_done:
    mov si, msg_ld_done
    call bios_print
    call delay_500ms

    ; Setup GDT
    mov si, msg_ld_gdt
    call bios_print
    call delay_500ms
    lgdt [gdt_descriptor]

    ; Enable A20
    mov si, msg_ld_a20
    call bios_print
    call delay_500ms
    in al, 0x92
    or al, 0x02
    out 0x92, al

    ; Enter protected mode
    mov si, msg_ld_pm
    call bios_print
    call delay_500ms
    call delay_500ms
    cli
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    ; Far jump to physical address of protected_mode_entry
    %define PM_ENTRY_PHYS (protected_mode_entry + (SEG_BASE << 4))
    jmp dword 0x08:PM_ENTRY_PHYS

[bits 32]
protected_mode_entry:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x0090000
    ; Copy kernel
    mov esi, 0x00020000
    mov edi, 0x100000
    mov ecx, ((KERNEL_SIZE_BYTES + 3) / 4)
    cld
    rep movsd
    jmp dword 0x08:0x100000

[bits 16]

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

; Data
boot_drive    db 0
retry         db 0
last_status   db 0
dl_tried_alt  db 0

; GDT
align 8
gdt_start:
    dq 0x0000000000000000
    dq 0x00CF9A000000FFFF
    dq 0x00CF92000000FFFF
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd (gdt_start + (SEG_BASE << 4))

; DAP
dap:
    db 0x10
    db 0x00
count:      dw 0
buf_off:    dw 0
buf_seg:    dw 0
lba_low:    dd 0
lba_high:   dd 0

msg_ld_start db "[LOADER] start", 13,10,0
msg_ld_edd   db "[LOADER] EDD read", 13,10,0
msg_ld_chs   db "[LOADER] CHS read", 13,10,0
msg_ld_done  db "[LOADER] read done", 13,10,0
msg_ld_gdt   db "[LOADER] load GDT", 13,10,0
msg_ld_a20   db "[LOADER] enable A20", 13,10,0
msg_ld_pm    db "[LOADER] enter PM", 13,10,0
msg_ld_copy  db "[LOADER] copy kernel", 13,10,0

%if ($-$$) < 510
    times 510-($-$$) db 0
    dw 0xaa55
%elif ($-$$) < 1022
    times 1022-($-$$) db 0
    dw 0xaa55
%else
    %error "Loader too large"
%endif
