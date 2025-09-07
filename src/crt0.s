# ============================================================================
# RusticOS - 32-bit Startup (crt0)
# ----------------------------------------------------------------------------
# Minimal and robust 32-bit startup:
#   - CPU is already in protected mode (set by the loader)
#   - Set flat data segments and a stack
#   - Safely clear .bss
#   - Run C++ global constructors (.init_array then .ctors fallback)
#   - Call kernel_main()
#
# Notes:
#   - Interrupts remain disabled (cli) to avoid IRQs during early init
#   - No IDT is installed here to keep early boot simple and reliable
#   - VGA text buffer is at 0xB8000 for optional debug
# ============================================================================

.global _start
.extern kernel_main

.section .text
.code32

_start:
    # Disable interrupts during early init
    cli

    # Load flat data segments (match GDT: code=0x08, data=0x10)
    mov $0x10, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    mov %ax, %gs
    mov %ax, %ss

    # Set up a 32-bit stack (grows down)
    mov $0x90000, %esp

    # Optional debug: write 'C' at top-left to confirm entry
    mov $0xb8000, %edi
    mov $0x1f43, %eax   # 'C' white on blue
    mov %eax, (%edi)

    # ------------------------------------------------------------------
    # Zero the .bss section (guarded against mis-ordered symbols)
    # ------------------------------------------------------------------
    cld
    mov $__bss_start, %edi        # EDI = start of .bss
    mov $__bss_end, %ecx          # ECX = end of .bss
    sub %edi, %ecx                # ECX = size in bytes
    jbe .after_bss                # if end <= start, skip
    xor %eax, %eax                # fill with zeros
    rep stosb
.after_bss:

    # ------------------------------------------------------------------
    # Run C++ global constructors (init_array then ctors fallback)
    # ------------------------------------------------------------------
    # init_array: array of pointers to void (*)()
    mov $__init_array_start, %ebx
    mov $__init_array_end, %edx
.init_array_loop:
    cmp %ebx, %edx
    jge .after_init_array
    mov (%ebx), %eax
    add $4, %ebx
    test %eax, %eax
    jz .init_array_loop
    call *%eax
    jmp .init_array_loop
.after_init_array:

    # ctors fallback: iterate backwards, skip -1 sentinel and nulls
    mov $__ctors_end, %ebx      # one past last
    mov $__ctors_start, %edx
.ctors_loop_rev:
    cmp %edx, %ebx
    jge .after_ctors
    sub $4, %ebx
    mov (%ebx), %eax
    cmp $-1, %eax
    je .ctors_loop_rev
    test %eax, %eax
    jz .ctors_loop_rev
    call *%eax
    jmp .ctors_loop_rev
.after_ctors:

    # Optional debug: mark 'M' at (row 0, col 1) before kernel_main
    mov $0xb8002, %edi
    mov $0x1f4d, %eax   # 'M' white on blue
    mov %eax, (%edi)

    # Call C++ kernel main function
    call kernel_main

    # If kernel_main returns, halt forever
.hang:
    hlt
    jmp .hang
