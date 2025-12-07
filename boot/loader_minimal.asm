[org 0x1000]
[bits 16]

; Minimal loader that:
; 1. Loads kernel from disk to 0x90000
; 2. Sets up GDT and IDT
; 3. Enters protected mode
; 4. Jumps to kernel

loader_start:
    cli
    cld
    
    ; Set up segment registers
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    
    ; Move loader to 0x1000 segment
    mov ax, 0x1000
    mov ds, ax
    mov es, ax
    
    ; Print "Started"
    mov si, msg_started
    call print_string
    
    ; Read kernel from disk to 0x90000
    ; Setup DAP structure
    mov byte [dap], 0x10        ; DAP size
    mov byte [dap+1], 0
    mov word [dap+2], 1         ; Read 1 sector (will be updated)
    mov word [dap+4], 0         ; Offset 0x0000
    mov word [dap+6], 0x9000    ; Segment 0x9000 (= address 0x90000)
    mov dword [dap+8], 7        ; LBA start (sectors 1-6 = loader, sector 7+ = kernel)
    mov dword [dap+12], 0
    
    ; Call INT13 extended read
    mov si, dap
    mov ah, 0x42
    mov dl, 0x80
    int 0x13
    jc .read_error
    
    ; Print "Kernel loaded"
    mov si, msg_kernel_loaded
    call print_string
    
    ; Setup GDT
    lgdt [gdt_ptr]
    mov si, msg_gdt_loaded
    call print_string
    
    ; Setup IDT (minimal)
    lidt [idt_ptr]
    mov si, msg_idt_loaded
    call print_string
    
    ; Disable NMI via CMOS
    mov al, 0x80
    out 0x70, al
    
    ; Mask all PIC interrupts
    mov al, 0xFF
    out 0x21, al
    out 0xA1, al
    
    ; Enable protected mode
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    
    mov si, msg_before_pm
    call print_string
    
    ; Far jump to protected mode entry
    db 0xEA
    dd 0x12902              ; pm_entry offset in loader at 0x10000 + 0x2902
    dw 0x08                 ; Code selector
    
    ; Should not reach here
    .halt:
    cli
    hlt
    jmp .halt

.read_error:
    mov si, msg_read_error
    call print_string
    jmp .halt

print_string:
    mov ah, 0x0E
.loop:
    lodsb
    test al, al
    jz .done
    int 0x10
    jmp .loop
.done:
    ret

; ============ GDT ==========
align 8
gdt:
    dq 0x0000000000000000
    dq 0x00cf9a000000ffff  ; Code selector 0x08
    dq 0x00cf92000000ffff  ; Data selector 0x10

gdt_ptr:
    dw 23
    dd 0x10000 + gdt

; ============ IDT ==========
align 8
idt_table:
    times 256 dq 0

idt_ptr:
    dw 2047
    dd 0x10000 + idt_table

; ============ DAP Structure ==========
align 8
dap:
    db 0
    db 0
    dw 0
    dw 0
    dw 0
    dq 0

; ============ Messages ==========
msg_started:        db "[LOADER] Started", 0x0D, 0x0A, 0
msg_kernel_loaded:  db "[LOADER] Kernel loaded", 0x0D, 0x0A, 0
msg_gdt_loaded:     db "[LOADER] GDT loaded", 0x0D, 0x0A, 0
msg_idt_loaded:     db "[LOADER] IDT loaded", 0x0D, 0x0A, 0
msg_before_pm:      db "[LOADER] Entering PM", 0x0D, 0x0A, 0
msg_read_error:     db "[LOADER] Read error", 0x0D, 0x0A, 0

; ============ 32-bit PM Entry Code ==========
; We stay in 16-bit mode for assembler but CPU will be in 32-bit PM
; Use explicit prefixes and byte sequences for 32-bit operations

pm_entry:
    ; mov ax, 0x10 (16-bit, still valid in 32-bit PM for segment setup)
    db 0xB8, 0x10, 0x00
    ; mov ds, ax
    db 0x8E, 0xD8
    ; mov es, ax
    db 0x8E, 0xC0
    ; mov ss, ax
    db 0x8E, 0xD0
    
    ; mov esp, 0x88000 (32-bit mov with 0x66 prefix)
    db 0x66, 0xBC, 0x00, 0x80, 0x08, 0x00
    
    ; mov eax, 0xDEADBEEF (32-bit mov)
    db 0x66, 0xB8, 0xEF, 0xBE, 0xAD, 0xDE
    
    ; mov edx, 0x3F8 (32-bit mov for port number)
    db 0x66, 0xBA, 0xF8, 0x03, 0x00, 0x00
    
    ; mov al, 'E'
    db 0xB0, 0x45
    
    ; out dx, al
    db 0xEE
    
    ; Jump to kernel at 0x90000
    ; mov eax, 0x90000
    db 0x66, 0xB8, 0x00, 0x00, 0x09, 0x00
    ; jmp eax
    db 0x66, 0xFF, 0xE0
    
    ; Should not reach
    db 0xF4  ; hlt
