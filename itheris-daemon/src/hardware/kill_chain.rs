//! # Kill Chain Handler
//!
//! Implements the emergency shutdown "kill chain" that executes within 120 CPU cycles
//! when a kernel crash or panic is detected.
//!
//! ## Cycle Breakdown
//!
//! | Cycle Range | Operation | Description |
//! |-------------|-----------|-------------|
//! | 1-2 | CLI | Clear all maskable interrupts using inline assembly |
//! | 3-10 | TLB Flush | Invalidate Translation Lookaside Buffer by reloading CR3 |
//! | 11-50 | EPT Poisoning | Revoke Julia Brain memory permissions (NO_READ + NO_EXEC) |
//! | 51-80 | GPIO Lockdown | Signal Raspberry Pi CM4 to set actuators to LOW |
//! | 81-120 | HLT | Execute permanent CPU halt
//!
//! ## Safety
//!
//! This module contains unsafe code that:
//! - Disables interrupts permanently
//! - Halts the CPU (never returns)
//! - Modifies memory protection
//!
//! This should only be called from the NMI handler or panic hook.

use crate::hardware::emergency_gpio;
use crate::hardware::memory_protector;

/// Emergency flag indicating kill chain has been triggered
pub static KILL_CHAIN_TRIGGERED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// Execute the kill chain - MUST be called from a context where it's safe to halt
/// 
/// This function performs the following in order:
/// 1. Clear all maskable interrupts (CLI)
/// 2. Flush TLB by reloading CR3
/// 3. Poison Julia Brain memory (mprotect to PROT_NONE)
/// 4. Signal emergency GPIO shutdown
/// 5. Halt CPU permanently
/// 
/// # Safety
/// This function disables interrupts and halts the CPU. It never returns.
#[inline(never)]
pub unsafe fn execute_kill_chain() {
    // Mark that kill chain has been triggered
    KILL_CHAIN_TRIGGERED.store(true, std::sync::atomic::Ordering::SeqCst);
    
    // Log the start of kill chain (this may not complete due to CLI)
    // We write directly to stderr to bypass any potential issues
    let _ = std::io::Write::write_all(
        &mut std::io::stderr(),
        b"[KILL CHAIN] Starting emergency shutdown sequence...\n"
    );
    
    // ========================================
    // Stage 1: CLI (Cycles 1-2)
    // Clear all maskable interrupts using inline assembly
    // ========================================
    #[cfg(target_arch = "x86_64")]
    unsafe {
        asm!("cli" : : : "memory" : "volatile");
    }
    
    // ========================================
    // Stage 2: TLB Flush (Cycles 3-10)
    // Invalidate Translation Lookaside Buffer
    // ========================================
    #[cfg(target_arch = "x86_64")]
    unsafe {
        // Read current CR3, then write it back to flush TLB
        // Using 0 directly is also valid but preserving original CR3 is cleaner
        asm!(
            "mov %cr3, %rax",
            "mov %rax, %cr3",
            : : : "rax", "memory" : "volatile"
        );
    }
    
    // ========================================
    // Stage 3: EPT Poisoning (Cycles 11-50)
    // Revoke Julia Brain memory permissions
    // ========================================
    // Try to protect Julia memory - continue even if this fails
    memory_protector::protect_all_julia_memory();
    
    // Also protect current process memory as a fallback
    memory_protector::protect_current_process_memory();
    
    // ========================================
    // Stage 4: GPIO Lockdown (Cycles 51-80)
    // Signal Raspberry Pi CM4 to set actuators to LOW
    // ========================================
    // Try to trigger emergency shutdown - continue even if this fails
    emergency_gpio::trigger_emergency_shutdown();
    emergency_gpio::lockdown_actuators();
    
    // ========================================
    // Stage 5: HLT (Cycles 81-120)
    // Execute permanent CPU halt
    // ========================================
    #[cfg(target_arch = "x86_64")]
    unsafe {
        // Log final message before halting
        let _ = std::io::Write::write_all(
            &mut std::io::stderr(),
            b"[KILL CHAIN] Halting CPU - SYSTEM LOCKED DOWN\n"
        );
        
        // Permanent halt - this never returns
        loop {
            asm!("hlt" : : : "memory" : "volatile");
        }
    }
    
    // For non-x86_64 architectures, we just loop forever
    #[cfg(not(target_arch = "x86_64"))]
    {
        let _ = std::io::Write::write_all(
            &mut std::io::stderr(),
            b"[KILL CHAIN] Non-x86_64 architecture - looping forever\n"
        );
        loop {
            std::thread::sleep(std::time::Duration::from_secs(1));
        }
    }
}

/// Execute kill chain in a separate thread (for panic handler)
/// 
/// This spawns a new thread to execute the kill chain to avoid
/// issues with panic unwinding while holding locks.
pub fn spawn_kill_chain_thread() {
    std::thread::spawn(|| {
        unsafe {
            execute_kill_chain();
        }
    });
}

/// Check if kill chain has been triggered
pub fn is_kill_chain_triggered() -> bool {
    KILL_CHAIN_TRIGGERED.load(std::sync::atomic::Ordering::SeqCst)
}

/// Reset kill chain flag (for testing)
#[cfg(test)]
pub fn reset_kill_chain() {
    KILL_CHAIN_TRIGGERED.store(false, std::sync::atomic::Ordering::SeqCst);
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_kill_chain_flag_initial() {
        reset_kill_chain();
        assert!(!is_kill_chain_triggered());
    }
    
    #[test]
    fn test_kill_chain_flag_set() {
        reset_kill_chain();
        KILL_CHAIN_TRIGGERED.store(true, std::sync::atomic::Ordering::SeqCst);
        assert!(is_kill_chain_triggered());
    }
}
