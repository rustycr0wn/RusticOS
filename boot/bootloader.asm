[org 0x7c00]
[bits 16]

%include "boot/loader_sectors.inc"

; Short jump + NOP so strict BIOS accept this as a VBR
jmp short start
nop

; Minimal BIOS Parameter Block (BPB) to satisfy BIOS heuristics
OEMLabel        db 'RUSTICOS'
BytesPerSector  dw 512
SectorsPerCluster db 1
ReservedSectors dw 1
NumberOfFATs    db 1
RootDirEntries  dw 224
TotalSectors16  dw 2880
MediaDescriptor db 0xF0
SectorsPerFAT16 dw 9
SectorsPerTrack dw 18
NumberOfHeads   dw 2
HiddenSectors   dd 0
TotalSectors32  dd 0

PART_BASE_PTR   equ 0x0600            ; physical 0:0x0600 stores partition base LBA (qword)

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x9000

    ; Preserve BIOS-provided boot drive
    mov [boot_drive], dl
    mov byte [dl_toggled], 0

    ; Save partition base LBA (HiddenSectors) to 0:PART_BASE_PTR (8 bytes, high dword 0)
    xor ax, ax
    mov es, ax
    mov di, PART_BASE_PTR
    mov eax, [HiddenSectors]
    stosw                    ; low word
    shr eax, 16
    stosw                    ; low dword high word
    xor ax, ax
    stosw                    ; high dword low word
    stosw                    ; high dword high word

    ; Stage: VBR start
    mov si, msg_mbr_start
    call bios_print

    ; Reset boot drive to a known state
    mov dl, [boot_drive]
    xor ax, ax
    int 0x13

    ; Stage: prepare DAP
    mov si, msg_mbr_prep
    call bios_print

    ; Prepare Disk Address Packet (DAP)
    mov word [dap.count], LOADER_SECTORS
    mov word [dap.buf_off], 0x0000
    mov word [dap.buf_seg], 0x1000
    ; LBA = HiddenSectors + 1 (Loader starts right after VBR within partition)
    mov eax, [HiddenSectors]
    add eax, 1
    mov [dap.lba_low], eax
    mov dword [dap.lba_high], 0

    ; Check for INT 13h Extensions (EDD) support on this drive
    mov dl, [boot_drive]
    mov ax, 0x4100
    mov bx, 0x55aa
    int 0x13
    jc .edd_fail
    cmp bx, 0x55aa
    jne .edd_fail

    ; Stage: using EDD
    mov si, msg_mbr_edd
    call bios_print

    ; Read loader via LBA
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
    ; on first failure try toggling DL to 0x80 once
    cmp byte [dl_toggled], 0
    jne .edd_after_toggle
    mov byte [dl_toggled], 1
    mov dl, 0x80
    mov [boot_drive], dl
.edd_after_toggle:
    ; reset and retry
    xor ah, ah
    int 0x13
    dec byte [retry]
    jnz .edd_try
    jmp .edd_fail

.edd_fail:
    ; EDD not available; cannot reliably CHS relative to partition. Abort.
    jmp disk_error

.success:
    ; Stage: jump to loader
    mov si, msg_mbr_jump
    call bios_print
    ; Jump to loader at 0x1000:0x0000
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

; ----------------------
; Data
; ----------------------
boot_drive db 0
retry      db 0
dl_toggled db 0

msg_mbr_start db "[VBR] start", 13, 10, 0
msg_mbr_prep  db "[VBR] prep DAP", 13, 10, 0
msg_mbr_edd   db "[VBR] EDD available", 13, 10, 0
msg_load      db "[VBR] loading loader...", 13, 10, 0
msg_mbr_jump  db "[VBR] jumping to loader", 13, 10, 0
msg_err       db 'Disk read error', 13, 10, 0

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
    dw 0xAA55
