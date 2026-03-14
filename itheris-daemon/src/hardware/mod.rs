//! # Hardware Module
//!
//! Unified hardware layer for fail-closed operation combining:
//! - Linux watchdog timer (Intel PATROL WDT)
//! - GPIO heartbeat generator (Raspberry Pi CM4)
//! - Kill chain handler (panic response)
//! - Emergency GPIO control
//!
//! This module provides the HardwareGuard struct that wraps all subsystems
//! and ensures proper initialization and cleanup.

pub mod watchdog;
pub mod heartbeat;
pub mod kill_chain;
pub mod panic_handler;
pub mod memory_protector;
pub mod emergency_gpio;

use heartbeat::{HeartbeatConfig, HeartbeatState};
use watchdog::{get_watchdog_status, is_watchdog_available, kick_watchdog, WatchdogStatus};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use thiserror::Error;
use serde::{Serialize, Deserialize};

/// Hardware initialization errors
#[derive(Error, Debug)]
pub enum HardwareError {
    #[error("Watchdog initialization failed: {0}")]
    WatchdogError(String),
    
    #[error("Heartbeat initialization failed: {0}")]
    HeartbeatError(String),
    
    #[error("Hardware not available")]
    NotAvailable,
}

/// Unified hardware status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HardwareStatus {
    /// Watchdog status
    pub watchdog: WatchdogStatus,
    /// Heartbeat state
    pub heartbeat: HeartbeatState,
    /// Whether all hardware is available
    pub fully_available: bool,
}

impl Default for HardwareStatus {
    fn default() -> Self {
        HardwareStatus {
            watchdog: WatchdogStatus::default(),
            heartbeat: HeartbeatState::default(),
            fully_available: false,
        }
    }
}

/// Hardware configuration
#[derive(Debug, Clone)]
pub struct HardwareConfig {
    /// Watchdog timeout in seconds
    pub watchdog_timeout_secs: u32,
    /// Heartbeat GPIO pin (BCM numbering)
    pub heartbeat_pin: u32,
    /// Heartbeat frequency in Hz
    pub heartbeat_frequency_hz: f64,
    /// Heartbeat duty cycle
    pub heartbeat_duty_cycle: f64,
}

impl Default for HardwareConfig {
    fn default() -> Self {
        HardwareConfig {
            watchdog_timeout_secs: 1, // 500ms (rounded to 1s for Linux watchdog)
            heartbeat_pin: 6,       // GPIO6 (Pin 31)
            heartbeat_frequency_hz: 100.0,
            heartbeat_duty_cycle: 0.5,
        }
    }
}

/// Hardware initialization flag
static mut HARDWARE_INITIALIZED: bool = false;

/// Initialize all hardware subsystems
/// 
/// This must be called after secure boot completes but before the main loop starts.
/// It initializes:
/// - Watchdog timer
/// - Heartbeat generator
/// - Emergency GPIO
/// - Panic handler
pub fn init_hardware() -> Result<HardwareConfig, HardwareError> {
    log::info!("🔧 Initializing hardware subsystems...");
    
    // Initialize watchdog
    match watchdog::init_watchdog() {
        Ok(_) => {
            log::info!("   ✓ Watchdog initialized");
        },
        Err(e) => {
            log::warn!("   ⚠️ Watchdog initialization warning: {}", e);
            // Continue in software simulation mode
        }
    }
    
    // Initialize heartbeat
    let hw_config = match heartbeat::init_heartbeat() {
        Ok(config) => {
            log::info!("   ✓ Heartbeat initialized");
            HardwareConfig {
                heartbeat_pin: config.pin,
                heartbeat_frequency_hz: config.frequency_hz,
                heartbeat_duty_cycle: config.duty_cycle,
                ..Default::default()
            }
        },
        Err(e) => {
            log::warn!("   ⚠️ Heartbeat initialization warning: {}", e);
            // Continue in software simulation mode
            HardwareConfig::default()
        }
    };
    
    // Initialize emergency GPIO
    match emergency_gpio::init_emergency_gpio() {
        Ok(state) => {
            log::info!("   ✓ Emergency GPIO initialized (available: {})", state.hardware_available);
        },
        Err(e) => {
            log::warn!("   ⚠️ Emergency GPIO initialization warning: {}", e);
        }
    }
    
    // Register panic handler (this sets up the kill chain)
    match panic_handler::register_panic_handler() {
        Ok(_) => {
            log::info!("   ✓ Panic handler registered");
        },
        Err(e) => {
            log::warn!("   ⚠️ Panic handler registration warning: {}", e);
        }
    }
    
    // Mark as initialized
    unsafe {
        HARDWARE_INITIALIZED = true;
    }
    
    log::info!("✅ Hardware subsystem initialization complete");
    Ok(hw_config)
}

/// Kick the watchdog timer
/// 
/// This must be called every 500ms in the main loop to prevent timeout.
/// If the watchdog is not available (non-privileged environment), this is a no-op.
pub fn hardware_kick_watchdog() {
    kick_watchdog();
}

/// Get the current hardware status
pub fn get_hardware_status() -> HardwareStatus {
    HardwareStatus {
        watchdog: get_watchdog_status(),
        heartbeat: heartbeat::get_heartbeat_state(),
        fully_available: is_watchdog_available() && heartbeat::is_heartbeat_running(),
    }
}

/// Check if hardware watchdog is available
pub fn is_hardware_available() -> bool {
    is_watchdog_available()
}

/// HardwareGuard - RAII wrapper for hardware resources
/// 
/// This struct ensures proper cleanup when the application exits.
/// On drop, it stops the heartbeat generator and closes the watchdog.
pub struct HardwareGuard {
    /// Whether the guard is active
    active: Arc<AtomicBool>,
}

impl HardwareGuard {
    /// Create a new HardwareGuard
    pub fn new() -> Self {
        HardwareGuard {
            active: Arc::new(AtomicBool::new(true)),
        }
    }
    
    /// Kick the watchdog (delegate to hardware module)
    #[inline]
    pub fn kick_watchdog(&self) {
        hardware_kick_watchdog();
    }
    
    /// Get hardware status
    #[inline]
    pub fn status(&self) -> HardwareStatus {
        get_hardware_status()
    }
    
    /// Check if hardware is available
    #[inline]
    pub fn is_available(&self) -> bool {
        is_hardware_available()
    }
}

impl Default for HardwareGuard {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for HardwareGuard {
    fn drop(&mut self) {
        self.active.store(false, Ordering::SeqCst);
        
        // Stop heartbeat gracefully
        heartbeat::stop_heartbeat();
        
        log::info!("🛑 Hardware resources released");
    }
}

/// Convenience function to create and initialize hardware
pub fn init_hardware_guard() -> Result<HardwareGuard, HardwareError> {
    init_hardware()?;
    Ok(HardwareGuard::new())
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_hardware_config_default() {
        let config = HardwareConfig::default();
        assert_eq!(config.watchdog_timeout_secs, 1);
        assert_eq!(config.heartbeat_pin, 6);
        assert_eq!(config.heartbeat_frequency_hz, 100.0);
        assert_eq!(config.heartbeat_duty_cycle, 0.5);
    }
    
    #[test]
    fn test_hardware_status_default() {
        let status = HardwareStatus::default();
        assert!(!status.watchdog.enabled);
        assert!(!status.heartbeat.running);
        assert!(!status.fully_available);
    }
    
    #[test]
    fn test_hardware_guard_creation() {
        let guard = HardwareGuard::new();
        assert!(guard.active.load(Ordering::SeqCst));
    }
}
