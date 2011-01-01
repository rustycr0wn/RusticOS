[org 0x7c00]
[bits 16]

; Real MBR: load active partition's VBR at 0x0000:0x7C00 and chainload
; Also stores the partition base LBA (LBA start) at 0:0x0600 for the VBR/loader

PARTITION_TABLE  equ 0x7C00 + 0x1BE
PART_BASE_PTR    equ 0x0600

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    mov [boot_drive], dl

    ; Find active partition (status 0x80), else first non-empty
    mov si, PARTITION_TABLE
    mov cx, 4
    mov bx, 0xFFFF              ; bx=entry offset of chosen, 0xFFFF=none
.find_active:
    cmp byte [si], 0x80
    jne .next1
    mov bx, si
    jmp .found
.next1:
    add si, 16
    loop .find_active

    ; No active; pick first with type != 0x00
    mov si, PARTITION_TABLE
    mov cx, 4
.find_any:
    cmp byte [si+4], 0x00
    jne .pick
    add si, 16
    loop .find_any
    jmp disk_error
.pick:
    mov bx, si

.found:
    ; Read LBA start from entry (offset +8, dword little-endian)
    mov si, bx
    mov ax, [si+8]
    mov dx, [si+10]
    ; Store full qword to 0:PART_BASE_PTR (high dword = 0)
    xor ax, ax
    mov es, ax
    mov di, PART_BASE_PTR
    ; write low dword
    mov ax, [bx+8]
    stosw
    mov ax, [bx+10]
    stosw
    ; high dword = 0
    xor ax, ax
    stosw
    stosw

    ; Prepare DAP to read VBR (count=1) to 0000:7C00
    mov word [dap.count], 1
    mov word [dap.buf_off], 0x7C00
    mov word [dap.buf_seg], 0x0000
    mov ax, [bx+8]
    mov [dap.lba_low], ax
    mov ax, [bx+10]
    mov [dap.lba_low+2], ax
    xor eax, eax
    mov [dap.lba_high], eax

    ; Check EDD support
    mov dl, [boot_drive]
    mov ax, 0x4100
    mov bx, 0x55AA
    int 0x13
    jc .chs_fallback
    cmp bx, 0x55AA
    jne .chs_fallback

    ; EDD read
    xor ax, ax
    mov ds, ax
    mov si, dap
    mov byte [retry], 3
.edd_try:
    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    jnc .chain
    ; reset + retry
    xor ah, ah
    int 0x13
    dec byte [retry]
    jnz .edd_try
    jmp .chs_fallback

.chs_fallback:
    ; Minimal CHS: read first sector of partition using CHS fields in entry (not portable)
    ; For robustness, just fail if EDD not available
    jmp disk_error

.chain:
    ; Chain to VBR at 0000:7C00 with DL preserved
    jmp 0x0000:0x7C00

; ----------------------
; Error handler (prints message and halts)
; ----------------------
disk_error:
    mov si, msg_err
.print:
    lodsb
    or al, al
    jz .halt
    mov ah, 0x0e
    int 0x10
    jmp .print
.halt:
    cli
.hang:
    hlt
    jmp .hang

; Data
msg_err     db "MBR error", 13, 10, 0
boot_drive  db 0
retry       db 0

; DAP (must be 16 bytes)
dap:
    db 16
    db 0
.count:     dw 0
.buf_off:   dw 0
.buf_seg:   dw 0
.lba_low:   dd 0
.lba_high:  dd 0

; Partition table area (filled by tooling)
 times 446-($-$$) db 0
 ; 4 entries of 16 bytes at 0x1BE will be written by partitioning tool
 times 510-($-$$) db 0
 dw 0xAA55 