[org 0x0000]
[bits 16]

%include "boot/kernel_sectors.inc"

; ------------------------------------------
; Serial output macro (for debugging)
; Usage: serial_write 'A'
; ------------------------------------------
; (serial output removed — using INT 10h print_string for diagnostics)

; ------------------------------------------
; PM Entry stub (placed early so offset is known)
; This is a small 32-bit routine that initializes
; segment registers and jumps to the kernel
; ------------------------------------------
pm_entry_start:
    ; This will be reached after a far jump with selector 0x08
    ; At this point, we're in protected mode but still executing from the loader at linear 0x1000
    ; The offset of pm_entry_stub within the loader binary is pm_entry_start - loader_start
    ; For now we'll calculate this explicitly below
    
; Actually, move pm_entry to the end of the file for easier offset calculation
; For now, skip ahead to main loader code

loader_start:
    cli
    cld
    sti
    
    ; Set up segment registers for loader
    mov ax, 0x0100
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x1000      ; Stack at 0x01000:0x1000 = 0x2000 linear
    
    ; Print startup message to verify loader is executing
    mov si, msg_loader_here
    call print_string
    
    ; Debug: print message before reading kernel
    mov si, msg_about_read
    call print_string

    ; NOW: Load kernel from disk via INT 13 CHS read (REAL MODE, safe)
    ; Kernel is KERNEL_SECTORS sectors, starting at sector 3 (1-based CHS)
    ; (Sector 1 = bootloader, Sector 2 = loader, Sector 3+ = kernel)
    ; Destination: 0x90000 (linear) = ES:0x0000 with ES=0x9000
    
    ; Set up segments for disk read
    mov ax, 0x9000
    mov es, ax              ; ES = destination segment
    xor bx, bx              ; BX = offset within ES (0x0000)
    
    ; Prepare to read KERNEL_SECTORS sectors starting at sector 3 (1-based CHS)
    ; Try reading with drive 0x80 (hard drive) since floppy (0x00) might not work
    mov dl, 0x80            ; Drive 0 (as hard drive)
    mov dh, 0x00            ; Head 0
    mov ch, 0x00            ; Cylinder 0
    mov cl, 0x03            ; Sector 3 (1-based)
    
    ; Read KERNEL_SECTORS sectors, but limit to 18 at a time for CHS safety
    ; (CHS can wrap, but 18 sectors should fit in one track)
    mov ah, 0x02            ; INT 13 AH=02: read sectors
    mov al, 18              ; Read 18 sectors at a time (limits CHS wrapping issues)
    cmp al, KERNEL_SECTORS
    jle .read_kernel
    mov al, KERNEL_SECTORS  ; If KERNEL_SECTORS < 18, read only what we need
    
.read_kernel:
    int 0x13
    
    ; Restore segment registers for code execution
    mov ax, 0x0100
    mov ds, ax
    mov es, ax
    
    ; Check carry flag for error
    jc .read_error
    
    ; Success!
    mov si, msg_kernel_ok
    call print_string
    jmp .kernel_valid
    
.read_error:
    ; Error reading kernel
    mov si, msg_kernel_err
    call print_string
    jmp .halt_error
    
.kernel_valid:
    ; About to enter PM
    mov si, msg_pm_entry
    call print_string
    
    ; About to enter PM - write to VGA first
    mov ax, 0xB800
    mov es, ax
    mov byte [es:0x00], 'P'
    mov byte [es:0x01], 0x0A
    mov byte [es:0x02], 'M'
    mov byte [es:0x03], 0x0A
    
    ; Prepare to enter protected mode and jump to kernel at 0x90000

    ; Load GDT - load address directly 
    mov ax, 0x0100
    mov ds, ax
    lea bx, [gdt_ptr]
    lgdt [bx]

    ; Disable interrupts during mode switch
    cli

    ; Set CR0.PE to enter protected mode
    mov eax, cr0
    or eax, 0x00000001     ; Set PE bit
    mov cr0, eax

    ; CRITICAL: Far jump immediately after PE bit set
    ; This jumps to protected mode code and reloads CS
    ; Use hardcoded address 0x1190 which is where pm_entry_32 actually is
    jmp 0x08:0x1190

.halt:
    hlt
    jmp .halt

.halt_error:
    hlt
    jmp .halt_error

; ========== MESSAGES ==========
msg_loader_here:    db "[LOADER] Loader executing", 0x0D, 0x0A, 0
msg_loader_start:   db "[LOADER] Loader started", 0x0D, 0x0A, 0
msg_about_read:     db "[LOADER] Reading kernel from disk...", 0x0D, 0x0A, 0
msg_kernel_ok:      db "[LOADER] Kernel loaded successfully", 0x0D, 0x0A, 0
msg_kernel_err:     db "[LOADER] Failed to read kernel from disk", 0x0D, 0x0A, 0
msg_pm_entry:       db "[LOADER] Entering protected mode...", 0x0D, 0x0A, 0

; ========== GDT (Global Descriptor Table) =========
; Print string using INT 10h (teletype mode) - same as bootloader
; This ensures consistent color and automatic cursor handling

; ========== HELPERS ==========
; Print string using INT 10h (teletype mode)
print_string:
    mov ah, 0x0E            ; INT 10h AH=0x0E: teletype output
    xor bx, bx              ; BH=0 (page 0)
.loop:
    lodsb
    test al, al
    jz .done
    int 0x10
    jmp .loop
.done:
    ret
; (all messages now inline VGA writes to avoid INT 10h overhead)

; ========== GDT (Global Descriptor Table) ==========
; 3-entry GDT: null, code (0x08), data (0x10)
; Both code and data have base=0x00000000, limit=0xFFFFF (4GB with granularity=1)
gdt:
    ; GDT Entry 0: Null descriptor
    dq 0x0000000000000000
    
    ; GDT Entry 1 (offset 0x08): 32-bit Code segment (flat memory, base=0)
    ; Base=0x00000000, Limit=0xFFFFF, Type=Code, P=1, S=1, DPL=0, DB=1, G=1
    dw 0xFFFF           ; Limit 15:0
    dw 0x0000           ; Base 15:0 (low 16 bits of 0x00000000)
    db 0x00             ; Base 23:16
    db 0x9A             ; P=1, DPL=0, S=1, Type=1010 (code)
    db 0xCF             ; G=1, DB=1, L=0, AVL=0, Limit 19:16=1111
    db 0x00             ; Base 31:24
    
    ; GDT Entry 2 (offset 0x10): 32-bit Data segment (flat memory, base=0)
    ; Base=0x00000000, Limit=0xFFFFF, Type=Data, P=1, S=1, DPL=0, DB=1, G=1
    dw 0xFFFF           ; Limit 15:0
    dw 0x0000           ; Base 15:0 (low 16 bits of 0x00000000)
    db 0x00             ; Base 23:16
    db 0x92             ; P=1, DPL=0, S=1, Type=0010 (data)
    db 0xCF             ; G=1, DB=1, L=0, AVL=0, Limit 19:16=1111
    db 0x00             ; Base 31:24

; ---------------------------
; Protected-mode entry stub (32-bit)
; - Reached after retf with CS=0x08 (code selector)
; - Initializes data selectors and ESP, then jumps to kernel
; ---------------------------
align 4
pm_entry_32:
    bits 32
    ; Write "Jumping!" to VGA at row 2 to confirm PM entry
    mov dword [0xB8140], 0x0A4A  ; 'J' at row 2, col 0
    mov dword [0xB8144], 0x0A75  ; 'u'
    mov dword [0xB8148], 0x0A6D  ; 'm'
    mov dword [0xB814C], 0x0A70  ; 'p'
    mov dword [0xB8150], 0x0A69  ; 'i'
    mov dword [0xB8154], 0x0A6E  ; 'n'
    mov dword [0xB8158], 0x0A67  ; 'g'
    mov dword [0xB815C], 0x0A21  ; '!'
    
    mov ax, 0x10                ; data selector (linear addressing)
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    ; Set a safe 32-bit stack
    mov esp, 0x00088000
    
    
    ; Jump to kernel at physical 0x00090000
    mov eax, 0x00090000
    jmp eax
    ; Unreachable, but return to 16-bit mode for NASM segment tracking
    bits 16

; GDT Pointer for LGDT
; The GDT is at offset (gdt - loader_start) within the loader segment (0x0100)
; In linear address space: 0x0100 * 16 + (gdt - loader_start) = 0x1000 + (gdt - loader_start)
gdt_ptr:
    dw 0x0017           ; GDT limit (23 bytes = 3 entries - 1)
    dd gdt - loader_start + 0x1000  ; GDT base: relative offset + 0x1000
gdt_end:
