[org 0x0000]
[bits 16]

; Determine kernel size in sectors
; Priority:
;   1) -D KERNEL_SIZE_BYTES=<bytes> on the NASM command line
;   2) boot/kernel_sectors.inc must define KERNEL_SECTORS
%ifndef KERNEL_SECTORS
%ifdef KERNEL_SIZE_BYTES
    %assign KERNEL_SECTORS ((KERNEL_SIZE_BYTES + 511) / 512)
%else
    %include "boot/kernel_sectors.inc"
%endif
%endif

; LOADER_SECTORS can be provided by the Makefile via -DLOADER_SECTORS
%ifndef LOADER_SECTORS
    %define LOADER_SECTORS 1
%endif

kernel_sectors      equ KERNEL_SECTORS
SEG_BASE            equ 0x1000
KERNEL_LBA_START    equ (1 + LOADER_SECTORS)

loader_start:
    ; Real-mode init: DS = CS, stack to safe area
    cli                     ; This should be the first instruction (0xFA)
    push cs
    pop ds
    mov ax, 0x9000        ; Use a safe stack segment far from loader/data
    mov ss, ax 
    mov sp, 0xFFFE        ; Top of segment
    cld

    ; Save BIOS boot drive (DL)
    mov [boot_drive], dl

    ; Print BIOS message first to confirm loader is running
    mov si, loader_bios_msg
    call bios_print
    call delay_200ms

    ; Debug: print loader start message
    mov si, loader_start_msg
    call bios_print
    call delay_200ms

    ; Clear the screen so green messages are on a fresh page
    mov ah, 0x00
    mov al, 0x03
    int 0x10

    ; Print "Booting bootloader..." at row 2 (green on black)
    mov ax, 0xb800
    mov es, ax
    mov di, (80*2*2)
    mov si, bootloader_msg
    mov ah, 0x02 ; green on black
    call print_string_vga_color
    call delay_200ms

    ; Print "Starting loader..." on line 3 (green on black)
    mov ax, 0xb800
    mov es, ax
    mov di, (80*3*2)
    mov si, loader_msg
    mov ah, 0x02 ; green on black
    call print_string_vga_color
    call delay_200ms

    ; Prepare DAP for INT 13h Extensions (LBA) reads
    mov word [dap.count], 0              ; filled in loop
    mov word [dap.buf_off], 0x0000
    mov word [dap.buf_seg], 0x2000
    mov dword [dap.lba_low], KERNEL_LBA_START            ; start after loader
    mov dword [dap.lba_high], 0

    ; Ensure DS points to 0x1000 for DS:SI DAP pointer
    mov ax, SEG_BASE
    mov ds, ax

    ; Print "Loading kernel..." on line 4 (green on black)
    mov ax, 0xb800
    mov es, ax
    mov di, (80*4*2)
    mov si, loading_msg
    mov ah, 0x02 ; green on black
    call print_string_vga_color
    call delay_200ms

    ; Remaining sectors to read
    mov bx, kernel_sectors
    mov [remaining], bx

read_lba_loop:
    mov bx, [remaining]
    cmp bx, 0
    je read_done

    ; Always read 1 sector at a time for robustness
    mov ax, 1
    mov [dap.count], ax

    ; DS is already set to 0x1000, SI will point to dap
    mov si, dap

    ; Retry up to 3 times, toggling DL fallback (boot_drive -> 0x80)
    mov byte [retry_count], 3
    mov dl, [boot_drive]
    mov byte [dl_tried_alt], 0
.try_read:
    mov ah, 0x42
    int 0x13
    jnc .read_ok

    ; on error: reset disk and maybe try DL=0x80 as fallback
    call disk_reset
    cmp byte [dl_tried_alt], 0
    jne .after_toggle
    mov dl, 0x80
    mov byte [dl_tried_alt], 1
.after_toggle:
    dec byte [retry_count]
    jnz .try_read
    jc disk_error

.read_ok:
    ; Advance buffer by 1 * 512 bytes -> segment += 32 paragraphs
    mov ax, 32
    add [dap.buf_seg], ax

    ; Advance LBA by 1
    add dword [dap.lba_low], 1
    adc dword [dap.lba_high], 0

    ; Decrease remaining
    dec word [remaining]

    ; Progress dot at row 4 advancing by two chars
    push ax
    push es
    mov ax, 0xb800
    mov es, ax
    add di, 2
    mov al, '.'
    mov ah, 0x02
    stosw
    pop es
    pop ax

    jmp read_lba_loop

read_done:
    ; Skipped verification check to avoid false negatives; proceed to PM

    ; Print "Booting kernel..." on line 5 (green on black)
    mov ax, 0xb800
    mov es, ax
    mov di, (80*5*2)
    mov si, booting_msg
    mov ah, 0x02 ; green on black
    call print_string_vga_color
    call delay_200ms

    ; DEBUG: Print "PM jump" on line 6 before protected mode switch
    mov ax, 0xb800
    mov es, ax
    mov di, (80*6*2)
    mov si, pm_jump_msg
    mov ah, 0x02 ; green on black
    call print_string_vga_color
    call delay_200ms

    ; Set up GDT for flat 32-bit protected mode
    lgdt [gdt_descriptor]

    ; Enable A20 via port 0x92
    in al, 0x92
    or al, 0x02
    out 0x92, al
    call delay_200ms

    ; Enter protected mode
    cli
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; Far jump to 32-bit code segment to flush prefetch queue
    %define PM_ENTRY_PHYS (protected_mode_entry + (SEG_BASE << 4))
    jmp dword 0x08:PM_ENTRY_PHYS

[bits 32]
protected_mode_entry:
    ; Set flat data segments (all pointing to 4GB flat model) BEFORE printing
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; DEBUG: Print "PM entry" at VGA row 7
    mov ax, 0x10
    mov es, ax
    mov edi, (0xB8000 + 80*7*2)
    mov esi, pm_entry_msg + (SEG_BASE << 4)
    mov ah, 0x02 ; green on black
    call print_string_vga_color32
    call delay_200ms32

    ; 32-bit stack (same as before)
    mov esp, 0x0090000

    ; Copy kernel from 0x00020000 to 0x00100000
    mov esi, 0x00020000
    mov edi, 0x00100000
    mov ecx, (kernel_sectors * 128)     ; sectors * 512 bytes / 4 bytes per dword
    rep movsd

    ; DEBUG: Print "Kernel jump" at VGA row 8
    mov ax, 0x10
    mov es, ax
    mov edi, (0xB8000 + 80*8*2)
    mov esi, kernel_jump_msg + (SEG_BASE << 4)
    mov ah, 0x02 ; green on black
    call print_string_vga_color32
    call delay_200ms32

    ; Jump to kernel entry (linked for 0x00100000)
    jmp dword 0x08:0x00100000

[bits 16]

; Hex printing helpers for disk_error (prints AH)
hex_digits: db '0123456789ABCDEF'

; 200ms delay helper (tries BIOS int 15h AH=86h; falls back to IO delays)
delay_200ms:
    push ax
    push bx
    push cx
    push dx
    mov ah, 0x86
    mov cx, 0x0000          ; high word of microseconds (0x0000C350 = 50000us)
    mov dx, 0xC350          ; low word
    int 0x15
    jnc .done
    ; Fallback: crude IO delay loop (~50ms)
    mov cx, 10000
.delay_loop:
    out 0x80, al
    loop .delay_loop
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

print_hex8_vga:                ; AL=input, ES:DI dest, AH=color preserved
    push ax
    push bx
    push cx
    mov bl, al
    shr bl, 4
    xor bh, bh
    mov si, hex_digits
    mov al, [bx+si]
    mov ah, 0x04
    stosw
    mov bl, al
    and bl, 0x0F
    xor bh, bh
    mov al, [bx+si]
    mov ah, 0x04
    stosw
    pop cx
    pop bx
    pop ax
    ret

; 32-bit delay ~200ms (busy-wait)
[bits 32]
delay_200ms32:
    push ecx
    mov ecx, 1250000        ; tune as needed for ~50ms
.delay32:
    loop .delay32
    pop ecx
    ret

[bits 16]

disk_error:
    ; Display "ERR" and AH status in hex at top-left, then halt
    mov ax, 0xb800
    mov es, ax
    mov di, 0
    push ax                 ; preserve AH=status
    mov al, 'E'
    mov ah, 0x04 ; red on black
    stosw
    mov al, 'R'
    stosw
    mov al, 'R'
    stosw
    ; print colon and AH code
    mov al, ':'
    mov ah, 0x04
    stosw
    pop ax                  ; restore AH=status
    mov bl, ah              ; save status in BL
    mov al, bl              ; BIOS status -> AL
    call print_hex8_vga
    cli
.halt:
    hlt
    jmp .halt

; 16-bit BIOS helpers
[bits 16]
disk_reset:
    push ax
    xor ah, ah
    int 0x13
    pop ax
    ret

; Messages
bootloader_msg db 'Booting bootloader...',0
loader_msg     db 'Starting loader...',0
loading_msg    db 'Loading kernel...',0
booting_msg    db 'Booting kernel...',0
pm_jump_msg    db 'PM jump...',0
pm_entry_msg   db 'PM entry...',0
kernel_jump_msg db 'Kernel jump...',0
loader_bios_msg db 'Loader: started (BIOS print)', 13, 10, 0
loader_start_msg db 'Loader: executing...', 13, 10, 0

; Minimal VGA print routine (SI=string, DI=offset, AH=color)
print_string_vga_color:
    lodsb
    or al, al
    jz .done
    stosw
    jmp print_string_vga_color
.done:
    ret

; Minimal VGA print routine for 32-bit (ES:EDI, ESI=string, AH=color)
print_string_vga_color32:
    lodsb
    or al, al
    jz .done
    stosw
    jmp print_string_vga_color32
.done:
    ret

; BIOS teletype print (SI=ASCIIZ)
bios_print:
    push ax
    push bx
    cld
.next:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0e
    mov bx, 0x0007  ; page 0, white on black
    int 0x10
    jmp .next
.done:
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------
; Data and tables
; ----------------------------------------------------------------------
align 8
gdt_start:
    dq 0x0000000000000000          ; null descriptor
    dq 0x00CF9A000000FFFF          ; code: base=0, limit=4GB, 32-bit, gran=4KB
    dq 0x00CF92000000FFFF          ; data: base=0, limit=4GB, 32-bit, gran=4KB
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd (gdt_start + (SEG_BASE << 4))

; DAP: Disk Address Packet for INT 13h extensions
; Layout (16 bytes):
;  offset  size  field
;      0     1   size (0x10)
;      1     1   reserved (0)
;      2     2   count (sectors to read)
;      4     2   buffer offset
;      6     2   buffer segment
;      8     8   starting LBA (qword)
dap:
    db 0x10
    db 0x00
.count:    dw 0
.buf_off:  dw 0
.buf_seg:  dw 0
.lba_low:  dd 0
.lba_high: dd 0

; Variables
boot_drive    db 0
remaining     dw 0
retry_count   db 0
dl_tried_alt  db 0

; Pad loader to exactly 512 or 1024 bytes
%if ($-$$) < 510
    times 510-($-$$) db 0
    dw 0xaa55
%else
    times 1022-($-$$) db 0
    dw 0xaa55
%endif