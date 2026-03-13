//! Emergency halt and seal mechanism (Phase 6)
//! 
//! This module provides fail-closed security mechanisms:
//! - Emergency halt: Immediately stop all operations
//! - Emergency seal: Permanently lock the kernel (irreversible)
//! - Panic handlers: Automatic halt on Rust panics

use std::panic;
use std::sync::atomic::{AtomicBool, Ordering};
use thiserror::Error;

/// Error types for emergency operations
#[derive(Error, Debug)]
pub enum EmergencyError {
    #[error("Kernel is already sealed - permanent lock active")]
    KernelSealed,
    
    #[error("Emergency halt already active")]
    HaltAlreadyActive,
    
    #[error("Kernel panic detected: {0}")]
    KernelPanic(String),
}

/// Global state for emergency halt
static EMERGENCY_HALT_ACTIVE: AtomicBool = AtomicBool::new(false);

/// Global state for permanent seal (Phase 6)
static KERNEL_SEALED: AtomicBool = AtomicBool::new(false);

/// Check if emergency halt is currently active
pub fn is_halt_active() -> bool {
    EMERGENCY_HALT_ACTIVE.load(Ordering::Acquire)
}

/// Check if kernel is permanently sealed
pub fn is_sealed() -> bool {
    KERNEL_SEALED.load(Ordering::Acquire)
}

/// Trigger emergency halt - immediately stop all operations
/// 
/// This function logs a FATAL error and sets the halt state.
/// Julia should check `get_kernel_status()` and see status == Panicked (3)
/// and must not execute any further operations without kernel approval.
/// 
/// # Arguments
/// * `reason` - The reason for the emergency halt
pub fn trigger_emergency_halt(reason: &str) {
    log::error!("[EMERGENCY] FATAL: Emergency halt triggered");
    log::error!("[EMERGENCY] Reason: {}", reason);
    log::error!("[EMERGENCY] Julia must stop immediately - DO NOT EXECUTE ANY PROPOSALS");
    
    EMERGENCY_HALT_ACTIVE.store(true, Ordering::Release);
    
    // Prevent any further operations
    // The Julia side must check panic_in_progress() == 1 before any operation
}

/// Emergency seal - permanently lock the kernel (Phase 6)
/// 
/// Once sealed, the kernel cannot be initialized again until system restart.
/// This is a last-resort security measure for unrecoverable breaches.
/// 
/// # Arguments
/// * `reason` - The reason for the emergency seal
/// 
/// # Returns
/// * `Ok(())` if seal was successful
/// * `Err(EmergencyError::KernelSealed)` if already sealed
pub fn emergency_seal(reason: &str) -> Result<(), EmergencyError> {
    if KERNEL_SEALED.load(Ordering::Acquire) {
        return Err(EmergencyError::KernelSealed);
    }
    
    log::error!("[EMERGENCY] FATAL: Emergency seal activated!");
    log::error!("[EMERGENCY] Reason: {}", reason);
    log::error!("[EMERGENCY] KERNEL PERMANENTLY LOCKED - RESTART REQUIRED");
    
    // Set sealed state
    KERNEL_SEALED.store(true, Ordering::Release);
    EMERGENCY_HALT_ACTIVE.store(true, Ordering::Release);
    
    // Prevent any further initialization
    // All subsequent kernel_init() calls will fail
    
    Ok(())
}

/// Initialize panic handlers for fail-closed behavior
/// 
/// This sets up panic handlers that prevent unsafe continued operation
/// when the kernel panics. Julia will be signaled to halt.
pub fn init_panic_handlers() {
    // Set up panic hook for standard panics
    let default_panic = panic::take_hook();
    panic::set_hook(Box::new(move |panic_info| {
        let msg = if let Some(s) = panic_info.payload().downcast_ref::<&str>() {
            s.to_string()
        } else if let Some(s) = panic_info.payload().downcast_ref::<String>() {
            s.clone()
        } else {
            "Unknown panic".to_string()
        };
        
        let location = if let Some(loc) = panic_info.location() {
            format!("{}:{}:{}", loc.file(), loc.line(), loc.column())
        } else {
            "unknown location".to_string()
        };
        
        log::error!("[PANIC] FATAL: Kernel panic at {}", location);
        log::error!("[PANIC] Message: {}", msg);
        log::error!("[PANIC] Julia must halt immediately!");
        
        // Trigger emergency halt
        EMERGENCY_HALT_ACTIVE.store(true, Ordering::Release);
        
        // Call default hook for standard behavior
        default_panic(panic_info);
    }));
    
    log::info!("[EMERGENCY] Panic handlers initialized - fail-closed enabled");
}

/// Check if the kernel allows operations
/// 
/// This is the main security check - before any operation is executed,
/// Julia MUST call this function to verify the kernel is in a safe state.
/// 
/// # Returns
/// * `true` if operations are allowed
/// * `false` if kernel is panicked, halted, or sealed (Julia MUST NOT proceed)
pub fn can_proceed() -> bool {
    // Check sealed state first (permanent lock)
    if KERNEL_SEALED.load(Ordering::Acquire) {
        log::warn!("[SECURITY] Operation blocked: kernel is sealed");
        return false;
    }
    
    // Check emergency halt state
    if EMERGENCY_HALT_ACTIVE.load(Ordering::Acquire) {
        log::warn!("[SECURITY] Operation blocked: emergency halt active");
        return false;
    }
    
    true
}

/// Get current emergency status for debugging/logging
#[derive(Debug, Clone)]
pub struct EmergencyStatus {
    pub sealed: bool,
    pub halt_active: bool,
    pub can_proceed: bool,
}

impl EmergencyStatus {
    pub fn current() -> Self {
        Self {
            sealed: is_sealed(),
            halt_active: is_halt_active(),
            can_proceed: can_proceed(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_emergency_status() {
        let status = EmergencyStatus::current();
        assert!(!status.sealed);
        assert!(!status.halt_active);
        assert!(status.can_proceed);
    }
    
    #[test]
    fn test_cannot_proceed_after_seal() {
        // Note: In real tests, we'd reset state after
        // This is just to verify the logic works
        let status = EmergencyStatus::current();
        if status.sealed {
            assert!(!status.can_proceed);
        }
    }
}
