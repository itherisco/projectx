//! Boot Module - Hardware initialization for bare-metal operation
//! 
//! This module provides the foundation for running the Itheris kernel
//! in Ring 0 (bare-metal mode). It handles:
//! - Global Descriptor Table (GDT) setup
//! - Interrupt Descriptor Table (IDT) setup  
//! - Page table management and virtual memory
//! 
//! # Usage
//! 
//! ```ignore
//! use boot::{gdt, idt, paging};
//! 
//! pub fn init() {
//!     gdt::init();
//!     idt::init();
//!     paging::init();
//! }
//! ```

#[cfg(feature = "bare-metal")]
pub mod gdt;
#[cfg(feature = "bare-metal")]
pub mod idt;
#[cfg(feature = "bare-metal")]
pub mod paging;

/// Initialize all boot components for bare-metal operation
#[cfg(feature = "bare-metal")]
pub fn init() {
    // Initialize GDT first (required for protected mode)
    gdt::init();
    
    // Initialize IDT (interrupt handling)
    idt::init();
    
    // Initialize paging (virtual memory)
    paging::init();
    
    println!("[BOOT] All boot components initialized");
}

/// HAL (Hardware Abstraction Layer) initialization
/// This provides a stable interface for the kernel regardless of
/// whether we're running in bare-metal or user-space mode
pub mod hal {
    /// Initialize the hardware abstraction layer
    pub fn init() {
        #[cfg(feature = "bare-metal")]
        {
            super::init();
        }
        
        #[cfg(not(feature = "bare-metal"))]
        {
            println!("[HAL] Running in user-space fallback mode");
        }
    }
}
