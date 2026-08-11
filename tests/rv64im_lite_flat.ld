OUTPUT_ARCH(riscv)
ENTRY(__start)

MEMORY
{
    ROM (rwx) : ORIGIN = 0x00000000, LENGTH = 0x00200000
}

__edge_dtcm_base = 0x40000000;
__edge_dtcm_size = 0x00020000;
__edge_dtcm_mask = 0xfffffffffffe0000;

SECTIONS
{
    .text : ALIGN(4) { KEEP(*(.init)) *(.text .text.*) } > ROM
    .rodata : ALIGN(8) { *(.srodata .srodata.*) *(.rodata .rodata.*) } > ROM
    .data : ALIGN(8) {
        __global_pointer$ = . + 0x800;
        *(.sdata .sdata.*) *(.data .data.*)
    } > ROM
    .bss (NOLOAD) : ALIGN(8) {
        __bss_start = .;
        *(.sbss .sbss.*) *(.bss .bss.*) *(COMMON)
        __bss_end = .;
    } > ROM
}
