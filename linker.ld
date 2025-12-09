/* Linker script for RusticOS 32-bit kernel */

OUTPUT_FORMAT("elf32-i386")
ENTRY(_start)

/* define two program headers: text (R|X) and data (R|W) */
PHDRS
{
  text PT_LOAD FLAGS(5); /* PF_R | PF_X */
  data PT_LOAD FLAGS(6); /* PF_R | PF_W */
}

/* Define sections */
SECTIONS
{
  /* load address */
  . = 0x00090000;

  .text : 
  {
    . = ALIGN(0x1000);
    *(.multiboot)
    build/crt0.o(.text._start)
    build/crt0.o(.text)
    build/crt0.o(.text.*)
    *(.text.*)
    *(.text)
    *(.rodata)
    *(.rodata.*)
  } :text

  .data :
  {
    . = ALIGN(0x1000);
    *(.data)
    *(.data.*)
    PROVIDE(__data_start = .);
  } :data

  .bss :
  {
    . = ALIGN(0x1000);
    PROVIDE(__bss_start = .);
    *(.bss)
    *(.bss.*)
    *(COMMON)
    PROVIDE(__bss_end = .);
  } :data

  /DISCARD/ : { *(.eh_frame) *(.eh_frame*) }
}