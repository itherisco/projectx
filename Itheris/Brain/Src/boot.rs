//! Boot Entry Point - Ring 0 Kernel Start
//!
//! This file provides the entry point for the bare-metal kernel.
//! It replaces main() when running in bare-metal mode.
//!
//! The bootloader jumps to `_start` which initializes all kernel components.

#![no_std]
#![no_main]

use core::panic::PanicInfo;
use panic_translation::install_panic_hook;

/// Initialize IPC ring buffer for Julia communication
/// Available for both bare-metal and user-space modes
pub fn init_ipc() -> Option<ipc::ring_buffer::IpcRingBuffer> {
    println!("[BOOT] Initializing IPC...");
    let ipc = ipc::ring_buffer::IpcRingBuffer::new();
    println!("[BOOT] IPC ring buffer initialized");
    Some(ipc)
}

/// The entry point for the Itheris Kernel (Ring 0)
/// The bootloader expects a symbol named `_start`
#[no_mangle]
pub extern "C" fn _start() -> ! {
    // Install panic translation hook before anything else
    // This ensures panics are caught and translated at the FFI boundary
    install_panic_hook();
    
    // Early println before serial is initialized
    println!("[BOOT] Itheris Kernel starting...");
    
    // 1. Initialize Hardware Abstraction Layer
    // This sets up GDT, IDT, and paging
    #[cfg(feature = "bare-metal")]
    {
        println!("[BOOT] Initializing HAL...");
        boot::hal::init();
    }
    
    // 2. Initialize Memory Manager
    // Set up the kernel heap and memory layout
    #[cfg(feature = "bare-metal")]
    {
        println!("[BOOT] Initializing memory manager...");
        let _heap = memory::init_heap();
    }
    
    // 3. Initialize Crypto Authority with TPM
    // Load sovereign keys from TPM 2.0 or fall back to software
    println!("[BOOT] Initializing crypto authority...");
    let mut authority = tpm::TPMAuthority::boot_secure();
    
    // 4. Initialize IPC Shared Memory
    // Carve out protected region for Julia communication
    #[cfg(feature = "bare-metal")]
    {
        let _ipc = init_ipc();
    }
    
    // 5. Initialize Container Subsystem
    // Set up namespace isolation
    #[cfg(feature = "bare-metal")]
    {
        println!("[BOOT] Initializing container subsystem...");
        container::init();
    }
    
    // 6. Initialize the Kernel
    // Create the ItherisKernel with cognitive identities
    println!("[BOOT] Creating kernel...");
    let mut kernel = kernel::ItherisKernel::new(vec![
        "STRATEGIST", "CRITIC", "SCOUT", "EXECUTOR", "OBSERVER",
    ]);
    
    // Set up initial capabilities
    kernel.grant_capability(
        "STRATEGIST",
        vec!["REQUEST_EXECUTION", "QUERY_STATE"],
        86400,
    );
    kernel.grant_capability("CRITIC", vec!["VALIDATE", "CHALLENGE"], 86400);
    kernel.grant_capability("EXECUTOR", vec!["EXECUTE", "REPORT_RESULT"], 86400);
    
    println!("[BOOT] Kernel initialized successfully");
    
    // 7. Spawn Julia Runtime (PID 1)
    // This would be done via spawn_julia_brain() in a real implementation
    #[cfg(feature = "bare-metal")]
    {
        println!("[BOOT] Spawning Julia runtime...");
        // spawn_julia_brain(ipc_buffer);
    }
    
    // 8. Enter the Kernel Enforcement Loop
    // This is the main loop that handles IPC requests
    println!("[BOOT] Entering enforcement loop...");
    
    #[cfg(feature = "bare-metal")]
    loop {
        // Poll for IPC entries
        // if let Some(thought) = ipc_buffer.poll() {
        //     kernel.enforce(thought);
        // }
        
        // Save power while idling
        // x86_64::instructions::hlt();
    }
    
    // If not bare-metal, exit (shouldn't happen)
    #[cfg(not(feature = "bare-metal"))]
    {
        println!("[BOOT] Running in fallback mode");
        loop {}
    }
}

/// Panic handler for bare-metal mode
#[cfg(feature = "bare-metal")]
#[panic_handler]
fn panic(info: &PanicInfo) -> ! {
    println!("[PANIC] Kernel panic!");
    if let Some(location) = info.location() {
        println!("[PANIC] Location: {}:{}:{}",
            location.file(),
            location.line(),
            location.column()
        );
    }
    if let Some(message) = info.message() {
        println!("[PANIC] Message: {:?}", message);
    }
    
    // Halt the system
    loop {
        x86_64::instructions::hlt();
    }
}
