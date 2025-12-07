[bits 16]

%include "boot/kernel_sectors.inc"

loader_start:
    cli
    cld
    xor ax, ax
    mov ss, ax
    mov sp, 0x7c00

    mov ax, 0x1000
    mov ds, ax
    mov es, ax

    ; Initialize COM1 serial port safely
    ; Wait for transmitter empty (LSR bit 5) to avoid mixing with BIOS output
    mov dx, 0x3FD        ; LSR (base 0x3F8 + 5)
    mov cx, 0x4000
.wait_txe:
    in al, dx
    test al, 0x20        ; THR empty?
    jnz .tempty
    loop .wait_txe
.tempty:

    ; Set DLAB and program divisor for 9600 baud (115200/9600 = 12)
    mov dx, 0x3FB        ; LCR (base + 3)
    mov al, 0x80         ; Set DLAB
    out dx, al
    mov dx, 0x3F8        ; DLL (base + 0)
    mov al, 12           ; Divisor low byte
    out dx, al
    mov dx, 0x3F9        ; DLM (base + 1)
    mov al, 0            ; Divisor high byte
    out dx, al
    mov dx, 0x3FB        ; LCR
    mov al, 0x03         ; 8N1, clear DLAB
    out dx, al

    ; Enable and reset FIFOs (optional, improves reliability)
    mov dx, 0x3FA        ; FCR (base + 2)
    mov al, 0x07         ; Enable FIFO, clear RX/TX FIFO
    out dx, al

    ; Small stabilization delay
    mov cx, 2000
.init_delay:
    loop .init_delay

    mov si, msg_started
    call print_string

    ; Copy DAP to low memory 0x0000:0x0700
    mov ax, 0x1000
    mov ds, ax
    mov si, dap
    mov ax, 0x0000
    mov es, ax
    mov di, 0x0700
    mov cx, 8
    cld
    rep movsw

    ; Call extended INT13 with DAP at 0x0000:0x0700
    mov ax, 0x0000
    mov ds, ax
    mov si, 0x0700
    mov ah, 0x42
    mov dl, 0x80
    int 0x13

    ; Restore DS and check result
    mov ax, 0x1000
    mov ds, ax

    jc .read_error

    mov si, msg_kernel_loaded
    call print_string

    ; DEBUG: dump first 8 bytes at 0x90000 to serial to verify load
    mov dx, 0x3F8
    mov ax, 0x9000
    mov ds, ax
    xor si, si
    mov cx, 8
.dump_loop:
    mov al, [si]
    out dx, al
    inc si
    loop .dump_loop

    ; Skip in-memory validation and go straight to PM entry
    ; minimal PM-entry marker (avoid print_string complexity)
    mov dx, 0x3F8
    mov al, 'P'
    out dx, al
    ; also write to VGA
    push ax
    mov ah, 0x0E
    mov al, 'P'
    int 0x10
    pop ax

    cli

    ; Load GDT and IDT
    lgdt [gdt_ptr]
    ; marker after LGDT
    mov dx, 0x3F8
    mov al, 'G'
    out dx, al
    lidt [idt_ptr]
    ; marker after LIDT
    mov dx, 0x3F8
    mov al, 'I'
    out dx, al

    ; Mask PICs
    ; Disable NMI via CMOS index port (set top bit of port 0x70)
    mov dx, 0x70
    in al, dx
    or al, 0x80
    out dx, al
    ; marker after NMI disable
    mov dx, 0x3F8
    mov al, 'N'
    out dx, al
    mov al, 0xFF
    mov dx, 0x21
    out dx, al
    mov dx, 0xA1
    out dx, al
    ; marker after PIC mask
    mov dx, 0x3F8
    mov al, 'M'
    out dx, al

    ; Enter protected mode
    mov eax, cr0
    or eax, 0x00000001
    mov cr0, eax

    ; marker before far-jump
    mov dx, 0x3F8
    mov al, 'F'
    out dx, al

    ; Far jump with operand-size override into loader's PM trampoline
    ; Runtime address: 0x10000 + pm_entry_offset (0x2902 = pm_entry offset in binary)
    ; Use explicit encoding to ensure correct far jump in PM
    db 0x66, 0xEA
    dd 0x12902
    dw 0x08
    
    ; Pad to align (should never reach here)
    align 16

    jmp .halt

.chs_error:
    mov ax, 0x1000
    mov ds, ax
    mov si, msg_chs_error
    call print_string
    jmp .halt

.kernel_invalid_chs:
    mov ax, 0x1000
    mov ds, ax
    mov si, msg_kernel_invalid_chs
    call print_string
    jmp .halt

.kernel_invalid:
    mov ax, 0x1000
    mov ds, ax
    mov si, msg_kernel_invalid
    call print_string
    
    jmp .halt

.read_error:
    mov ax, 0x1000
    mov ds, ax
    mov si, msg_read_error
    call print_string
    jmp .halt

; ========== HELPERS ==========
print_string:
.loop:
    lodsb
    test al, al
    jz .done
    mov dx, 0x3F8
    out dx, al
    ; Also print to VGA via BIOS teletype (INT 0x10 AH=0x0E)
    push ax
    push bx
    mov ah, 0x0E
    mov bh, 0x00
    int 0x10
    pop bx
    pop ax
    ; Long delay between characters to avoid serial garbling
    mov cx, 5000
.delay:
    loop .delay
    jmp .loop
.done:
    ret

.halt:
    cli
    hlt
    jmp .halt

; ========== MESSAGES ==========
msg_started:            db "[LOADER] Started", 0x0D, 0x0A, 0
msg_kernel_loaded:      db "[LOADER] Kernel loaded (from disk)", 0x0D, 0x0A, 0
msg_validating:         db "[LOADER] Validating kernel at 0x90000...", 0x0D, 0x0A, 0
msg_chs_fallback:       db "[LOADER] Extended read OK but memory zero. Trying CHS fallback...", 0x0D, 0x0A, 0
msg_chs_complete:       db "[LOADER] CHS read complete", 0x0D, 0x0A, 0
msg_chs_still_zero:     db "[LOADER] FATAL: CHS read OK but kernel still zero at 0x90000", 0x0D, 0x0A, 0
msg_kernel_valid:       db "[LOADER] Kernel validated in memory", 0x0D, 0x0A, 0
msg_before_pm:          db "[LOADER] Before PM entry...", 0x0D, 0x0A, 0
msg_kernel_invalid:     db "[LOADER] Kernel invalid (first dword is zero)", 0x0D, 0x0A, 0
msg_kernel_invalid_chs: db "[LOADER] CHS read: Kernel still invalid", 0x0D, 0x0A, 0
msg_chs_error:          db "[LOADER] CHS read failed", 0x0D, 0x0A, 0
msg_read_error:         db "[LOADER] INT13 extended read failed", 0x0D, 0x0A, 0

; ========== DAP ==========
align 16
dap:
    db 0x10, 0x00
    dw KERNEL_SECTORS
    dw 0x0000
    dw 0x9000
    ; Starting LBA placeholder - patched by Makefile after assembling loader
    ; Unique marker: 0x1122334455667788
    dq 0x1122334455667788

; ========== GDT ==========
align 16
gdt:
    dq 0x0000000000000000
    dq 0x00cf9a000000ffff  ; Code
    dq 0x00cf92000000ffff  ; Data
gdt_end:

align 4
gdt_ptr:
    dw gdt_end - gdt - 1
    dd 0x10000 + gdt  ; GDT base (runtime = 0x10000 + label offset)

; ========== Minimal IDT ==========
align 4
idt_table:
    times 256 dq 0        ; 256 empty IDT entries (8 bytes each)
idt_end:

align 4
idt_ptr:
    dw idt_end - idt_table - 1
    dd 0x10000 + idt_table ; IDT base (runtime = 0x10000 + label offset)

; ========== 32-bit PM Entry Code (raw bytes) ==========
; The CPU is in 32-bit PM when this code executes
; We use explicit byte sequences for all 32-bit operations

pm_entry:
    db 0x66, 0xB8, 0xEF, 0xBE, 0xAD, 0xDE  ; mov eax, 0xDEADBEEF
    db 0x66, 0xBA, 0xF8, 0x03, 0x00, 0x00  ; mov edx, 0x3F8
    db 0xB0, 0x45                           ; mov al, 0x45
    db 0xEE                                 ; out dx, al
    db 0xB8, 0x10, 0x00                     ; mov ax, 0x10
    db 0x8E, 0xD8                           ; mov ds, ax
    db 0x8E, 0xC0                           ; mov es, ax
    db 0x8E, 0xE0                           ; mov fs, ax
    db 0x8E, 0xE8                           ; mov gs, ax
    db 0x8E, 0xD0                           ; mov ss, ax
    db 0x66, 0xBC, 0x00, 0x80, 0x08, 0x00  ; mov esp, 0x88000
    db 0x66, 0xB8, 0x00, 0x00, 0x09, 0x00  ; mov eax, 0x90000
    db 0x66, 0xFF, 0xE0                     ; jmp eax
pm_entry.halt:
    db 0xF4                                 ; HLT
