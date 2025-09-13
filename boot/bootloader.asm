[org 0x7c00]
[bits 16]

%include "boot/loader_sectors.inc"

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00

    ; Preserve BIOS-provided boot drive
    mov [boot_drive], dl

    ; Stage: MBR start
    mov si, msg_mbr_start
    call bios_print
    call delay_500ms

    ; Reset boot drive to a known state
    mov dl, [boot_drive]
    xor ax, ax
    int 0x13

    ; Stage: prepare DAP
    mov si, msg_mbr_prep
    call bios_print
    call delay_500ms

    ; Prepare Disk Address Packet (DAP)
    mov word [dap.count], LOADER_SECTORS
    mov word [dap.buf_off], 0x0000
    mov word [dap.buf_seg], 0x1000
    mov dword [dap.lba_low], 1
    mov dword [dap.lba_high], 0

    ; Check for INT 13h Extensions (EDD) support on this drive
    mov dl, [boot_drive]
    mov ax, 0x4100
    mov bx, 0xaa55
    int 0x13
    jc .edd_fail
    cmp bx, 0xAA55
    jne .edd_fail

    ; Stage: using EDD
    mov si, msg_mbr_edd
    call bios_print
    call delay_500ms

    ; Read loader via LBA (starting at LBA 1)
    mov si, msg_load
    call bios_print

    ; DS:SI must point to DAP - ensure DS is 0
    xor ax, ax
    mov ds, ax
    mov si, dap
    mov byte [retry], 3
.edd_try:
    mov ah, 0x42            ; Extended read
    mov dl, [boot_drive]
    int 0x13
    jnc .success
    ; reset and retry
    xor ah, ah
    int 0x13
    dec byte [retry]
    jnz .edd_try
    jmp .edd_fail

.edd_fail:
    ; Stage: falling back to CHS
    mov si, msg_mbr_chs
    call bios_print
    call delay_500ms

    ; Fallback: CHS read starting at C=0,H=0,S=2
    mov dl, [boot_drive]
    mov ax, 0x1000
    mov es, ax
    xor bx, bx               ; destination offset

    mov cl, 2                ; sector 2
    xor ch, ch               ; cylinder 0
    xor dh, dh               ; head 0

    mov bp, LOADER_SECTORS
.chs_loop:
    cmp bp, 0
    jz .success

    mov byte [retry], 3
.chs_try:
    mov ah, 0x02             ; read
    mov al, 1                ; one sector
    mov dl, [boot_drive]
    int 0x13
    jnc .chs_ok
    ; reset and retry
    xor ah, ah
    int 0x13
    dec byte [retry]
    jnz .chs_try
    jmp disk_error
.chs_ok:
    add bx, 512
    inc cl
    dec bp
    jmp .chs_loop

.success:
    ; Stage: jump to loader
    mov si, msg_mbr_jump
    call bios_print
    ; Remove delay for faster boot
    ; Success: print prompt and jump to loader at 0x1000:0x0000
    xor ax, ax
    mov ds, ax               ; DS=0 for message pointers
    mov ax, 0x1000
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0xFFFE
    mov dl, [boot_drive]
    jmp 0x1000:0x0000

; ----------------------
; BIOS teletype print (SI=ASCIIZ)
; ----------------------
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

; ~500ms delay using PIT tick polling fallback to IO stalls
; (crude but sufficient for staging)
delay_500ms:
    push cx
    push dx
    mov cx, 200000
.dl:
    out 0x80, al
    loop .dl
    pop dx
    pop cx
    ret

; ----------------------
; Data
; ----------------------
boot_drive db 0
retry      db 0

msg_mbr_start db "[MBR] start", 13, 10, 0
msg_mbr_prep  db "[MBR] prep DAP", 13, 10, 0
msg_mbr_edd   db "[MBR] EDD available", 13, 10, 0
msg_mbr_chs   db "[MBR] EDD fail -> CHS", 13, 10, 0
msg_load      db "[MBR] loading loader...", 13, 10, 0
msg_mbr_jump  db "[MBR] jumping to loader", 13, 10, 0
msg_err       db 'Disk read error', 13, 10, 0
msg_mbr       db 'MBR> ', 0

; Disk Address Packet (for INT 13h AH=42h)
; size(16), reserved(0), count, buffer offset, buffer segment, starting LBA (dq)
dap:
    db 16
    db 0
.count:     dw 0
.buf_off:   dw 0
.buf_seg:   dw 0
.lba_low:   dd 0
.lba_high:  dd 0

; ----------------------
; Errors
; ----------------------
disk_error:
    xor ax, ax
    mov ds, ax
    mov si, msg_err
    call bios_print
    sti
.hang:
    hlt
    jmp .hang

; Pad to 512 bytes and add signature
times 510-($-$$) db 0
    dw 0xaa55
