# ============================================================================
# RusticOS - 32-bit Startup (crt0)
# ----------------------------------------------------------------------------
# Minimal and robust 32-bit startup
# ============================================================================

.global _start
.extern kernel_main

.section .text._start
.code32

_start:
    cli
    # Early serial trace: write "KERNEL PM\n" to COM1 (port 0x3F8)
    leal serial_msg, %esi
    movw $0x3F8, %dx
1:  lodsb
    testb %al, %al
    je 2f
    movw $0x3F8, %dx
    outb %al, (%dx)
    jmp 1b
2:
    
    # Print 'K' to VGA text buffer to confirm entry
    movl $0xb8004, %esi
    movb $'K', (%esi)
    movb $0x0A, 1(%esi)
    
    movl $0xb8000, %edi
    movl $0x1f4b, %eax   # K in green
    movl %eax, (%edi)

    # Load GDT
    lea gdt_ptr, %eax
    lgdt (%eax)

    movl $0xb8002, %edi
    movl $0x1f47, %eax   # G in green
    movl %eax, (%edi)

    # Set segment registers (must be after GDT load)
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    movw %ax, %ss

    movl $0xb8004, %edi
    movl $0x1f53, %eax   # S in green
    movl %eax, (%edi)

    # Disable NMI and mask PIC IRQs
    movw $0x70, %dx
    inb (%dx), %al
    orb $0x80, %al
    outb %al, (%dx)
    movw $0x21, %dx
    movb $0xFF, %al
    outb %al, (%dx)
    movw $0xA1, %dx
    outb %al, (%dx)

    movl $0xb8006, %edi
    movl $0x1f4e, %eax   # N in green
    movl %eax, (%edi)

    # Build IDT with halting handler for all vectors
    lea idt, %edi
    xorl %eax, %eax
    movl $256*8/4, %ecx
    rep stosl                      # zero IDT

    # Fill all 256 IDT entries with interrupt gate to isr_stub
    lea isr_stub, %ebx             # ebx = handler address (save it)
    movl $0, %esi                  # esi = current IDT entry offset (0..255*8)
.fill_idt:
    cmpl $256*8, %esi
    jge .fill_idt_done
    
    movw %bx, idt+0(%esi)          # offset_low (16-bit)
    movw $0x08, idt+2(%esi)        # selector (16-bit)
    movl $0, idt+4(%esi)           # reserved (32-bit, zero)
    movb $0x8E, idt+5(%esi)        # type_attr (8-bit)
    movl %ebx, %eax
    shrl $16, %eax                 # eax = high 16 bits of handler
    movw %ax, idt+6(%esi)          # offset_high (16-bit)
    
    addl $8, %esi
    jmp .fill_idt

.fill_idt_done:
    # Load IDT
    lea idt_ptr, %eax
    lidt (%eax)

    movl $0xb8008, %edi
    movl $0x1f49, %eax   # I in green
    movl %eax, (%edi)

    # Stack: use 0x00090000 (kernel at 0x00090000, stack below it)
    movl $0x00088000, %esp
    andl $~0xF, %esp          # align to 16 bytes

    movl $0xb800A, %edi
    movl $0x1f42, %eax   # B in green
    movl %eax, (%edi)

    # Clear .bss
    cld
    movl $__bss_start, %edi
    movl $__bss_end, %ecx
    subl %edi, %ecx
    jbe .after_bss
    xorl %eax, %eax
    rep stosb
.after_bss:

    movl $0xb8002, %edi
    movl $0x1f4d, %eax   # D in green
    movl %eax, (%edi)

    movl $0xb800C, %edi
    movl $0x1f4D, %eax   # M in green
    movl %eax, (%edi)

    call kernel_main

.hang:
    hlt
    jmp .hang

# IDT
.section .data
.align 8
idt:
    .space 256*8, 0
idt_ptr:
    .word (256*8 - 1)
    .long idt

# Serial message used by early kernel trace
.align 1
serial_msg:
    .ascii "KERNEL PM\n\0"

# GDT
.align 8
gdt:
    .quad 0x0000000000000000     # Null descriptor
    .quad 0x00cf9a000000ffff     # Code segment
    .quad 0x00cf92000000ffff     # Data segment

gdt_ptr:
    .word (3*8 - 1)
    .long gdt

# ISR stub
.section .text
.align 16
isr_stub:
    cli
1:  hlt
    jmp 1b
