[org 0x7c00]
[bits 16]

; Minimal test MBR
start:
    ; Print a simple message
    mov si, msg_test
    call bios_print
    
    ; Hang
    cli
    hlt

; BIOS teletype print
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

msg_test db 'MBR Test - Working!', 13, 10, 0

; Pad to 512 bytes and add signature
times 510-($-$$) db 0
    dw 0xAA55 