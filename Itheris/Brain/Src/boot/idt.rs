//! Interrupt Descriptor Table (IDT) Implementation
//!
//! The IDT handles hardware interrupts (IRQs) and software exceptions.
//! It defines handlers for:
//! - CPU exceptions (divide error, page fault, etc.)
//! - Hardware IRQs (keyboard, timer, etc.)
//! - System calls (via interrupt gates)

use bitflags::bitflags;
use x86_64::structures::idt::{InterruptDescriptorTable, InterruptStackFrame, PageFaultErrorCode};
use x86_64::instructions::tables::lidt;
use x86_64::registers::control::Cr2;

/// Interrupt vector numbers
pub mod vectors {
    // CPU Exceptions (0-31)
    pub const DIVIDE_ERROR: u8 = 0;
    pub const DEBUG: u8 = 1;
    pub const NON_MASKABLE_INTERRUPT: u8 = 2;
    pub const BREAKPOINT: u8 = 3;
    pub const OVERFLOW: u8 = 4;
    pub const BOUND_RANGE_EXCEEDED: u8 = 5;
    pub const INVALID_OPCODE: u8 = 6;
    pub const DEVICE_NOT_AVAILABLE: u8 = 7;
    pub const DOUBLE_FAULT: u8 = 8;
    pub const COPROCESSOR_SEGMENT_OVERRUN: u8 = 9; // Deprecated
    pub const INVALID_TSS: u8 = 10;
    pub const SEGMENT_NOT_PRESENT: u8 = 11;
    pub const STACK_SEGMENT_FAULT: u8 = 12;
    pub const GENERAL_PROTECTION_FAULT: u8 = 13;
    pub const PAGE_FAULT: u8 = 14;
    pub const X87_FLOATING_POINT: u8 = 16;
    pub const ALIGNMENT_CHECK: u8 = 17;
    pub const MACHINE_CHECK: u8 = 18;
    pub const SIMD_FLOATING_POINT: u8 = 19;
    pub const VIRTUALIZATION: u8 = 20;
    pub const SECURITY_EXCEPTION: u8 = 30;
    
    // IRQs (32-47 typically)
    pub const IRQ0_TIMER: u8 = 32;
    pub const IRQ1_KEYBOARD: u8 = 33;
    pub const IRQ2_CASCADE: u8 = 34;
    pub const IRQ3_COM2: u8 = 35;
    pub const IRQ4_COM1: u8 = 36;
    pub const IRQ5_LPT2: u8 = 37;
    pub const IRQ6_FLOPPY: u8 = 38;
    pub const IRQ7_LPT1: u8 = 39;
    pub const IRQ8_RTC: u8 = 40;
    pub const IRQ9_ACPI: u8 = 41;
    pub const IRQ10_OPEN: u8 = 42;
    pub const IRQ11_OPEN: u8 = 43;
    pub const IRQ12_MOUSE: u8 = 44;
    pub const IRQ13_FPU: u8 = 45;
    pub const IRQ14_PRIMARY_IDE: u8 = 46;
    pub const IRQ15_SECONDARY_IDE: u8 = 47;
    
    // System calls (128 = 0x80)
    pub const SYSCALL: u8 = 128;
}

/// IDT entry type flags
#[bitflags]
#[repr(u8)]
#[derive(Clone, Copy, Debug)]
pub enum IdtFlags {
    Present = 0x80,
    DplRing0 = 0x00,
    DplRing3 = 0x60,
    Size32 = 0x08,
    Size64 = 0x00,
    StorageSegment = 0x10,
    InterruptGate = 0x0E,
    TrapGate = 0x0F,
}

/// Page fault handler information
#[derive(Debug)]
pub struct PageFaultInfo {
    pub faulting_address: u64,
    pub present: bool,
    pub write: bool,
    pub user: bool,
    pub reserved_write: bool,
    pub instruction_fetch: bool,
}

impl From<PageFaultErrorCode> for PageFaultInfo {
    fn from(code: PageFaultErrorCode) -> Self {
        PageFaultInfo {
            faulting_address: Cr2::read(),
            present: code.contains(PageFaultErrorCode::PRESENT),
            write: code.contains(PageFaultErrorCode::WRITE_ACCESS),
            user: code.contains(PageFaultErrorCode::USER_MODE),
            reserved_write: code.contains(PageFaultErrorCode::RESERVED_BIT),
            instruction_fetch: code.contains(PageFaultErrorCode::INSTRUCTION_FETCH),
        }
    }
}

/// The Interrupt Descriptor Table
pub struct Idt {
    /// The x86_64 IDT structure
    idt: InterruptDescriptorTable,
}

impl Idt {
    /// Create and initialize a new IDT with handlers
    pub fn new() -> Self {
        let mut idt = InterruptDescriptorTable::new();
        
        // Set up exception handlers (0-31)
        Self::setup_exception_handlers(&mut idt);
        
        // Set up IRQ handlers (32-47)
        Self::setup_irq_handlers(&mut idt);
        
        // Set up system call handler
        Self::setup_syscall_handler(&mut idt);
        
        Idt { idt }
    }
    
    /// Set up CPU exception handlers
    fn setup_exception_handlers(idt: &mut InterruptDescriptorTable) {
        // Division by zero
        idt[vectors::DIVIDE_ERROR]
            .set_handler_fn(divide_error_handler)
            .set_stack_index(0);
        
        // Debug
        idt[vectors::DEBUG]
            .set_handler_fn(debug_handler)
            .set_stack_index(0);
        
        // Non-maskable interrupt
        idt[vectors::NON_MASKABLE_INTERRUPT]
            .set_handler_fn(nmi_handler)
            .set_stack_index(0);
        
        // Breakpoint
        idt[vectors::BREAKPOINT]
            .set_handler_fn(breakpoint_handler)
            .set_stack_index(0);
        
        // Overflow
        idt[vectors::OVERFLOW]
            .set_handler_fn(overflow_handler)
            .set_stack_index(0);
        
        // Bound range exceeded
        idt[vectors::BOUND_RANGE_EXCEEDED]
            .set_handler_fn(bound_range_handler)
            .set_stack_index(0);
        
        // Invalid opcode
        idt[vectors::INVALID_OPCODE]
            .set_handler_fn(invalid_opcode_handler)
            .set_stack_index(0);
        
        // Device not available
        idt[vectors::DEVICE_NOT_AVAILABLE]
            .set_handler_fn(device_not_available_handler)
            .set_stack_index(0);
        
        // Double fault - uses special handler that cannot return
        idt[vectors::DOUBLE_FAULT]
            .set_handler_fn(double_fault_handler)
            .set_stack_index(1); // Uses IST1
        
        // Invalid TSS
        idt[vectors::INVALID_TSS]
            .set_handler_fn(invalid_tss_handler)
            .set_stack_index(0);
        
        // Segment not present
        idt[vectors::SEGMENT_NOT_PRESENT]
            .set_handler_fn(segment_not_present_handler)
            .set_stack_index(0);
        
        // Stack segment fault
        idt[vectors::STACK_SEGMENT_FAULT]
            .set_handler_fn(stack_segment_fault_handler)
            .set_stack_index(0);
        
        // General protection fault
        idt[vectors::GENERAL_PROTECTION_FAULT]
            .set_handler_fn(general_protection_fault_handler)
            .set_stack_index(0);
        
        // Page fault - critical for memory management
        idt[vectors::PAGE_FAULT]
            .set_handler_fn(page_fault_handler)
            .set_stack_index(1); // Uses IST1
        
        // x87 floating point
        idt[vectors::X87_FLOATING_POINT]
            .set_handler_fn(x87_floating_point_handler)
            .set_stack_index(0);
        
        // SIMD floating point
        idt[vectors::SIMD_FLOATING_POINT]
            .set_handler_fn(simd_floating_point_handler)
            .set_stack_index(0);
    }
    
    /// Set up IRQ handlers
    fn setup_irq_handlers(idt: &mut InterruptDescriptorTable) {
        // Timer (IRQ0)
        idt[vectors::IRQ0_TIMER]
            .set_handler_fn(timer_handler)
            .set_stack_index(0);
        
        // Keyboard (IRQ1)
        idt[vectors::IRQ1_KEYBOARD]
            .set_handler_fn(keyboard_handler)
            .set_stack_index(0);
        
        // Other IRQs use default handler for now
        for i in 34..48 {
            idt[i].set_handler_fn(default_handler).set_stack_index(0);
        }
    }
    
    /// Set up system call handler (INT 0x80)
    fn setup_syscall_handler(idt: &mut InterruptDescriptorTable) {
        idt[vectors::SYSCALL]
            .set_handler_fn(syscall_handler)
            .set_stack_index(0)
            .set_privilege_level(PrivilegeLevel::Ring3);
    }
    
    /// Load the IDT into the CPU
    pub fn load(&self) {
        let idtr = self.idt.into();
        unsafe {
            lidt(&idtr);
        }
        println!("[IDT] Interrupt Descriptor Table loaded");
    }
}

// ============================================================================
// Exception Handlers
// ============================================================================

extern "x86-interrupt" fn divide_error_handler(stack_frame: InterruptStackFrame) {
    println!("[EXCEPTION] Divide Error\n{:#?}", stack_frame);
    panic!("Divide by zero");
}

extern "x86-interrupt" fn debug_handler(stack_frame: InterruptStackFrame) {
    println!("[EXCEPTION] Debug\n{:#?}", stack_frame);
}

extern "x86-interrupt" fn nmi_handler(stack_frame: InterruptStackFrame) {
    println!("[EXCEPTION] NMI\n{:#?}", stack_frame);
}

extern "x86-interrupt" fn breakpoint_handler(stack_frame: InterruptStackFrame) {
    println!("[EXCEPTION] Breakpoint\n{:#?}", stack_frame);
}

extern "x86-interrupt" fn overflow_handler(stack_frame: InterruptStackFrame) {
    println!("[EXCEPTION] Overflow\n{:#?}", stack_frame);
}

extern "x86-interrupt" fn bound_range_handler(stack_frame: InterruptStackFrame) {
    println!("[EXCEPTION] Bound Range Exceeded\n{:#?}", stack_frame);
}

extern "x86-interrupt" fn invalid_opcode_handler(stack_frame: InterruptStackFrame) {
    println!("[EXCEPTION] Invalid Opcode\n{:#?}", stack_frame);
    panic!("Invalid opcode executed");
}

extern "x86-interrupt" fn device_not_available_handler(stack_frame: InterruptStackFrame) {
    println!("[EXCEPTION] Device Not Available\n{:#?}", stack_frame);
    panic!("FPU not available");
}

extern "x86-interrupt" fn double_fault_handler(
    stack_frame: InterruptStackFrame,
    _error_code: u64,
) -> ! {
    println!("[EXCEPTION] Double Fault\n{:#?}", stack_frame);
    panic!("Double fault - critical error");
}

extern "x86-interrupt" fn invalid_tss_handler(
    stack_frame: InterruptStackFrame,
    error_code: u64,
) {
    println!("[EXCEPTION] Invalid TSS (error: {})\n{:#?}", error_code, stack_frame);
}

extern "x86-interrupt" fn segment_not_present_handler(
    stack_frame: InterruptStackFrame,
    error_code: u64,
) {
    println!("[EXCEPTION] Segment Not Present (error: {})\n{:#?}", error_code, stack_frame);
}

extern "x86-interrupt" fn stack_segment_fault_handler(
    stack_frame: InterruptStackFrame,
    error_code: u64,
) {
    println!("[EXCEPTION] Stack Segment Fault (error: {})\n{:#?}", error_code, stack_frame);
}

extern "x86-interrupt" fn general_protection_fault_handler(
    stack_frame: InterruptStackFrame,
    error_code: u64,
) {
    println!("[EXCEPTION] General Protection Fault (error: {})\n{:#?}", error_code, stack_frame);
    panic!("GPF - privilege violation");
}

extern "x86-interrupt" fn page_fault_handler(
    stack_frame: InterruptStackFrame,
    error_code: PageFaultErrorCode,
) {
    let info = PageFaultInfo::from(error_code);
    println!("[EXCEPTION] Page Fault\n{:#?}", stack_frame);
    println!("[PAGE FAULT] Address: 0x{:016x}", info.faulting_address);
    println!("[PAGE FAULT] Present: {}, Write: {}, User: {}", 
        info.present, info.write, info.user);
    panic!("Page fault - memory protection violation");
}

extern "x86-interrupt" fn x87_floating_point_handler(stack_frame: InterruptStackFrame) {
    println!("[EXCEPTION] x87 Floating Point\n{:#?}", stack_frame);
}

extern "x86-interrupt" fn simd_floating_point_handler(stack_frame: InterruptStackFrame) {
    println!("[EXCEPTION] SIMD Floating Point\n{:#?}", stack_frame);
}

// ============================================================================
// IRQ Handlers
// ============================================================================

extern "x86-interrupt" fn timer_handler(_stack_frame: InterruptStackFrame) {
    // Acknowledge timer interrupt (would need PIC/PIT interaction)
    println!("[IRQ] Timer tick");
}

extern "x86-interrupt" fn keyboard_handler(_stack_frame: InterruptStackFrame) {
    // Read keyboard scancode
    println!("[IRQ] Keyboard input");
}

extern "x86-interrupt" fn default_handler(_stack_frame: InterruptStackFrame) {
    println!("[IRQ] Unhandled interrupt");
}

// ============================================================================
// System Call Handler
// ============================================================================

extern "x86-interrupt" fn syscall_handler(stack_frame: InterruptStackFrame) {
    // System call handling for IPC
    // In a bare-metal environment, this would handle:
    // - IPC notifications from Julia
    // - Memory mapping requests
    // - Capability verification requests
    println!("[SYSCALL] System call from Ring 3");
    println!("{:#?}", stack_frame);
}

/// Initialize the IDT
pub fn init() {
    let idt = Idt::new();
    idt.load();
    println!("[IDT] Interrupt Descriptor Table initialized");
}
