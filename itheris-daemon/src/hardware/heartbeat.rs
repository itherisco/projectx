//! # Heartbeat Generator
//!
//! GPIO heartbeat signal generation for Raspberry Pi CM4 communication.
//! Generates 100Hz heartbeat (10ms period), 3.3V, 50% duty cycle.
//!
//! GPIO Pin mapping (BCM numbering):
//! - GPIO6 (Pin 31) -> HEARTBEAT_OUT (i9->CM4)

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;
use thiserror::Error;
use serde::{Deserialize, Serialize};

/// GPIO sysfs base path
const GPIO_SYSFS_PATH: &str = "/sys/class/gpio";

/// Heartbeat GPIO pin (BCM numbering)
const HEARTBEAT_PIN: u32 = 6;

/// Heartbeat frequency (100Hz = 10ms period)
const HEARTBEAT_FREQUENCY_HZ: f64 = 100.0;

/// Heartbeat period in microseconds
const HEARTBEAT_PERIOD_US: u64 = 10_000;

/// Errors that can occur during heartbeat operations
#[derive(Error, Debug)]
pub enum HeartbeatError {
    #[error("Failed to export GPIO: {0}")]
    ExportError(String),
    
    #[error("Failed to configure GPIO direction: {0}")]
    DirectionError(String),
    
    #[error("Failed to write GPIO value: {0}")]
    WriteError(String),
    
    #[error("Heartbeat thread error: {0}")]
    ThreadError(String),
    
    #[error("GPIO not available (running in non-privileged environment)")]
    NotAvailable,
}

/// Heartbeat configuration
#[derive(Debug, Clone)]
pub struct HeartbeatConfig {
    /// GPIO pin number (BCM numbering)
    pub pin: u32,
    /// Heartbeat frequency in Hz
    pub frequency_hz: f64,
    /// Duty cycle (0.0 to 1.0)
    pub duty_cycle: f64,
    /// Voltage level (3.3V for Raspberry Pi)
    pub voltage: f32,
}

impl Default for HeartbeatConfig {
    fn default() -> Self {
        HeartbeatConfig {
            pin: HEARTBEAT_PIN,
            frequency_hz: HEARTBEAT_FREQUENCY_HZ,
            duty_cycle: 0.5,
            voltage: 3.3,
        }
    }
}

/// Heartbeat generator state
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct HeartbeatState {
    /// Whether the heartbeat is currently running
    pub running: bool,
    /// Number of heartbeat cycles completed
    pub cycles: u64,
    /// Whether hardware GPIO is available
    pub hardware_available: bool,
}

impl Default for HeartbeatState {
    fn default() -> Self {
        HeartbeatState {
            running: false,
            cycles: 0,
            hardware_available: false,
        }
    }
}

/// GPIO controller using sysfs interface
pub struct GpioController {
    pin: u32,
    exported: bool,
}

impl GpioController {
    /// Create a new GPIO controller for the specified pin
    pub fn new(pin: u32) -> Result<Self, HeartbeatError> {
        let controller = GpioController {
            pin,
            exported: false,
        };
        
        // Try to export the GPIO pin
        controller.try_export()?;
        
        Ok(controller)
    }
    
    /// Try to export the GPIO pin
    fn try_export(&self) -> Result<(), HeartbeatError> {
        let gpio_path = format!("{}/gpio{}", GPIO_SYSFS_PATH, self.pin);
        
        // Check if already exported
        if Path::new(&gpio_path).exists() {
            log::debug!("GPIO {} already exported", self.pin);
            return Ok(());
        }
        
        // Try to export the pin
        let export_path = format!("{}/export", GPIO_SYSFS_PATH);
        
        match std::fs::write(&export_path, format!("{}\n", self.pin)) {
            Ok(_) => {
                log::info!("✅ GPIO {} exported successfully", self.pin);
                Ok(())
            },
            Err(e) => {
                // In non-privileged environment, GPIO access may not be available
                if e.kind() == std::io::ErrorKind::PermissionDenied {
                    log::warn!("⚠️ GPIO permission denied - running in software simulation mode");
                    return Err(HeartbeatError::NotAvailable);
                } else if e.kind() == std::io::ErrorKind::NotFound {
                    log::warn!("⚠️ GPIO sysfs not found - running in software simulation mode");
                    return Err(HeartbeatError::NotAvailable);
                }
                
                // Other errors - try software mode
                log::warn!("⚠️ GPIO export error: {} - running in software simulation mode", e);
                Err(HeartbeatError::ExportError(e.to_string()))
            }
        }
    }
    
    /// Set GPIO direction to output
    pub fn set_output(&self) -> Result<(), HeartbeatError> {
        let direction_path = format!("{}/gpio{}/direction", GPIO_SYSFS_PATH, self.pin);
        
        match std::fs::write(&direction_path, "out\n") {
            Ok(_) => {
                log::debug!("GPIO {} set to output", self.pin);
                Ok(())
            },
            Err(e) => {
                log::warn!("GPIO direction write error: {}", e);
                Err(HeartbeatError::DirectionError(e.to_string()))
            }
        }
    }
    
    /// Write GPIO value (0 or 1)
    pub fn write_value(&self, value: u8) -> Result<(), HeartbeatError> {
        let value_path = format!("{}/gpio{}/value", GPIO_SYSFS_PATH, self.pin);
        
        std::fs::write(&value_path, format!("{}\n", value))
            .map_err(|e| HeartbeatError::WriteError(e.to_string()))
    }
}

impl Drop for GpioController {
    fn drop(&mut self) {
        // Try to unexport the GPIO pin on drop
        if self.exported {
            let unexport_path = format!("{}/unexport", GPIO_SYSFS_PATH);
            let _ = std::fs::write(&unexport_path, format!("{}\n", self.pin));
        }
    }
}

/// Heartbeat generator
pub struct HeartbeatGenerator {
    config: HeartbeatConfig,
    running: Arc<AtomicBool>,
    cycles: Arc<std::sync::atomic::AtomicU64>,
    gpio: Option<GpioController>,
    thread_handle: Option<thread::JoinHandle<()>>,
}

impl HeartbeatGenerator {
    /// Create a new heartbeat generator
    pub fn new(config: HeartbeatConfig) -> Result<Self, HeartbeatError> {
        // Try to initialize GPIO
        let gpio = match GpioController::new(config.pin) {
            Ok(mut ctrl) => {
                // Try to set output direction
                if ctrl.set_output().is_ok() {
                    ctrl.exported = true;
                    Some(ctrl)
                } else {
                    None
                }
            },
            Err(HeartbeatError::NotAvailable) => {
                None
            },
            Err(e) => {
                log::warn!("GPIO initialization failed: {}, using software mode", e);
                None
            }
        };
        
        let hardware_available = gpio.is_some();
        
        if hardware_available {
            log::info!("✅ Heartbeat GPIO initialized (Pin GPIO{})", config.pin);
        } else {
            log::info!("📋 Heartbeat running in software simulation mode");
        }
        
        Ok(HeartbeatGenerator {
            config,
            running: Arc::new(AtomicBool::new(false)),
            cycles: Arc::new(std::sync::atomic::AtomicU64::new(0)),
            gpio,
            thread_handle: None,
        })
    }
    
    /// Start the heartbeat generator
    pub fn start(&mut self) -> Result<(), HeartbeatError> {
        if self.running.load(Ordering::SeqCst) {
            log::warn!("Heartbeat already running");
            return Ok(());
        }
        
        self.running.store(true, Ordering::SeqCst);
        
        let running = self.running.clone();
        let cycles = self.cycles.clone();
        let gpio = self.gpio.take(); // Take ownership for the thread
        
        // Calculate timing
        let period_us = HEARTBEAT_PERIOD_US;
        let high_us = (period_us as f64 * self.config.duty_cycle) as u64;
        let low_us = period_us - high_us;
        
        self.thread_handle = Some(thread::spawn(move || {
            let mut gpio = gpio;
            
            while running.load(Ordering::SeqCst) {
                // Set GPIO HIGH (if available)
                if let Some(ref mut ctrl) = gpio {
                    let _ = ctrl.write_value(1);
                }
                
                // High period
                thread::sleep(Duration::from_micros(high_us));
                
                // Set GPIO LOW (if available)
                if let Some(ref mut ctrl) = gpio {
                    let _ = ctrl.write_value(0);
                }
                
                // Low period
                thread::sleep(Duration::from_micros(low_us));
                
                // Increment cycle counter
                cycles.fetch_add(1, Ordering::SeqCst);
            }
            
            // Return GPIO controller on thread exit
            // Note: In practice, we can't return it easily, so we just drop it
        }));
        
        log::info!("💓 Heartbeat generator started ({} Hz)", self.config.frequency_hz);
        Ok(())
    }
    
    /// Stop the heartbeat generator
    pub fn stop(&mut self) {
        if !self.running.load(Ordering::SeqCst) {
            return;
        }
        
        self.running.store(false, Ordering::SeqCst);
        
        // Wait for thread to finish
        if let Some(handle) = self.thread_handle.take() {
            let _ = handle.join();
        }
        
        log::info!("🛑 Heartbeat generator stopped ({} cycles)", 
                   self.cycles.load(Ordering::SeqCst));
    }
    
    /// Get the current state
    pub fn state(&self) -> HeartbeatState {
        HeartbeatState {
            running: self.running.load(Ordering::SeqCst),
            cycles: self.cycles.load(Ordering::SeqCst),
            hardware_available: self.gpio.is_some(),
        }
    }
}

impl Drop for HeartbeatGenerator {
    fn drop(&mut self) {
        self.stop();
    }
}

// Helper for Path trait
use std::path::Path;

/// Global heartbeat generator (lazily initialized)
static mut HEARTBEAT_GENERATOR: Option<HeartbeatGenerator> = None;

/// Initialize the heartbeat subsystem
pub fn init_heartbeat() -> Result<HeartbeatConfig, HeartbeatError> {
    let config = HeartbeatConfig::default();
    
    unsafe {
        let mut generator = HeartbeatGenerator::new(config.clone())?;
        generator.start()?;
        HEARTBEAT_GENERATOR = Some(generator);
    }
    
    log::info!("💓 Heartbeat subsystem initialized");
    Ok(config)
}

/// Start the heartbeat
pub fn start_heartbeat() -> Result<(), HeartbeatError> {
    unsafe {
        if let Some(ref mut gen) = HEARTBEAT_GENERATOR {
            gen.start()?;
        }
    }
    Ok(())
}

/// Stop the heartbeat
pub fn stop_heartbeat() {
    unsafe {
        if let Some(ref mut gen) = HEARTBEAT_GENERATOR {
            gen.stop();
        }
    }
}

/// Get heartbeat state
pub fn get_heartbeat_state() -> HeartbeatState {
    unsafe {
        HEARTBEAT_GENERATOR.as_ref().map(|g| g.state()).unwrap_or_default()
    }
}

/// Check if heartbeat is running
pub fn is_heartbeat_running() -> bool {
    unsafe {
        HEARTBEAT_GENERATOR.as_ref().map(|g| g.state().running).unwrap_or(false)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_heartbeat_config_default() {
        let config = HeartbeatConfig::default();
        assert_eq!(config.pin, HEARTBEAT_PIN);
        assert_eq!(config.frequency_hz, HEARTBEAT_FREQUENCY_HZ);
        assert_eq!(config.duty_cycle, 0.5);
        assert_eq!(config.voltage, 3.3);
    }
    
    #[test]
    fn test_heartbeat_state_default() {
        let state = HeartbeatState::default();
        assert!(!state.running);
        assert_eq!(state.cycles, 0);
        assert!(!state.hardware_available);
    }
    
    #[test]
    fn test_heartbeat_timing() {
        // Verify heartbeat timing calculations
        let period_us = HEARTBEAT_PERIOD_US;
        let duty_cycle = 0.5;
        let high_us = (period_us as f64 * duty_cycle) as u64;
        let low_us = period_us - high_us;
        
        assert_eq!(high_us, 5000);
        assert_eq!(low_us, 5000);
    }
}
