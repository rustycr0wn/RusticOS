[bits 32]
; Minimal kernel stub: stays in protected mode and halts

; Allow Makefile to pass KERNEL_SIZE_BYTES
%ifndef KERNEL_SIZE_BYTES
%assign KERNEL_SIZE_BYTES 32768
%endif

global start

start:
    cli
.halt:
    hlt
    jmp .halt

; Pad kernel to KERNEL_SIZE_BYTES
%if ($-$$) < KERNEL_SIZE_BYTES
    times (KERNEL_SIZE_BYTES - ($ - $$)) db 0
%endif