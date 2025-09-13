/* Linker script for RusticOS 32-bit kernel */

ENTRY(_start)

/* Define sections */
SECTIONS
{
    /* Kernel starts at 1 MiB */
    . = 0x100000;
    
    /* Text section (code) */
    .text : {
        KEEP(*(.text._start))
        *(.text)
        *(.text.*)
    }
    
    /* Read-only data */
    .rodata : {
        *(.rodata)
        *(.rodata.*)
    }
    
    /* Data section */
    .data : {
        *(.data)
        *(.data.*)
    }

    /* C++ static constructors (.init_array preferred; .ctors as fallback) */
    .init_array : {
        __init_array_start = .;
        KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)))
        KEEP(*(.init_array))
        __init_array_end = .;
    }

    .ctors : {
        __ctors_start = .;
        KEEP(*(.ctors))
        KEEP(*(.ctors.*))
        __ctors_end = .;
    }
    
    /* BSS section (uninitialized data) */
    .bss : {
        __bss_start = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
        __bss_end = .;
    }
    
    /* Discard other sections */
    /DISCARD/ : {
        *(.comment)
        *(.note)
        *(.eh_frame)
        *(.eh_frame_hdr)
    }
}