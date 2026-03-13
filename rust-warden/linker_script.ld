/* 
 * Rust Warden Hypervisor Linker Script
 * Target: x86_64-unknown-none (bare metal)
 * 
 * Memory Layout:
 * - 0x00000000 - 0x00FFFFFF: Warden Space (16MB)
 * - 0x01000000 - 0x01100000: IPC Ring Buffer (64MB)  
 * - 0x10000000+: Julia Guest Space
 */

OUTPUT_FORMAT("elf64-x86-64")
OUTPUT_ARCH("x86_64")
ENTRY(_start)

/* Base address for the hypervisor */
BASE_ADDRESS = 0x10000;

/* Physical memory regions */
WARDEN_CODE_START = 0x10000;
WARDEN_CODE_SIZE = 0x30000;     /* 192KB code */

WARDEN_DATA_START = 0x40000;
WARDEN_DATA_SIZE = 0x10000;      /* 64KB data */

VMCS_START = 0x50000;
VMCS_SIZE = 0x1000;             /* 4KB per CPU */

VMXON_START = 0x51000;
VMXON_SIZE = 0x1000;            /* 4KB VMXON region */

EPT_START = 0x200000;
EPT_SIZE = 0x100000;            /* 1MB EPT tables */

/* IPC Shared Memory */
IPC_BUFFER_START = 0x1000000;    /* 16MB */
IPC_BUFFER_SIZE = 0x4000000;     /* 64MB */

/* Julia Guest Physical Memory */
GUEST_PHYS_START = 0x10000000;   /* 256MB */
GUEST_PHYS_SIZE = 0x10000000;   /* 256MB */

SECTIONS
{
    . = BASE_ADDRESS;

    /* Code section - aligned to 4KB */
    .text : {
        _text_start = .;
        *(.text .text.* .rodata .rodata.*)
        _text_end = .;
    } > ram AT > ram :text

    /* Data section */
    .data : {
        _data_start = .;
        *(.data .data.* .bss .bss.*)
        _data_end = .;
    } > ram AT > ram :data

    /* VMXON region - must be 4KB aligned */
    .vmxon (VMXON_START) : {
        _vmxon_start = .;
        . = . + VMXON_SIZE;
        _vmxon_end = .;
    } > ram

    /* VMCS region - per CPU */
    .vmcs (VMCS_START) : {
        _vmcs_start = .;
        . = . + VMCS_SIZE;
        _vmcs_end = .;
    } > ram

    /* EPT tables */
    .ept (EPT_START) : {
        _ept_start = .;
        . = . + EPT_SIZE;
        _ept_end = .;
    } > ram

    /* IPC Ring Buffer */
    .ipc (IPC_BUFFER_START) : {
        _ipc_start = .;
        . = . + IPC_BUFFER_SIZE;
        _ipc_end = .;
    } > ram

    /* Guest physical memory */
    .guest_phys (GUEST_PHYS_START) : {
        _guest_phys_start = .;
        . = . + GUEST_PHYS_SIZE;
        _guest_phys_end = .;
    } > ram
}

/* Symbols for boot code */
PROVIDE(_start = 0x10000);
PROVIDE(_stack_start = 0x80000);
